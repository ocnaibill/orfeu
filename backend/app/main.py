from fastapi import FastAPI, HTTPException, Query, Request, Response, BackgroundTasks, Depends, status, UploadFile, File
from fastapi.responses import StreamingResponse, RedirectResponse, HTMLResponse, FileResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from pydantic import BaseModel
from typing import Optional, Dict, List
from .database import engine, get_db, Base
from . import models, auth_utils
import os
import re
import asyncio
import httpx
import subprocess
import mutagen
from urllib.parse import quote
from unidecode import unidecode
from thefuzz import fuzz
import hashlib
import time
import json
import uuid

# Importação dos Serviços
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider
from app.services.analytics_service import AnalyticsService
from app.services.release_date_provider import ReleaseDateProvider
from app.services.recommendation_service import MusicRecommender
from app.services.metadata_provider import MetadataProvider




# Importação de Banco de Dados e Auth
from .database import engine, get_db, Base
from . import models, auth_utils


# Cria tabelas se não existirem
models.Base.metadata.create_all(bind=engine)


app = FastAPI(title="Orfeu API", version="2.4.0")

# Esquema de Segurança
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")
SECRET_KEY = os.getenv("SECRET_KEY", "uma_chave_super_secreta")
ALGORITHM = "HS256"

# --- Configuração de Arquivos Estáticos (OTA Updates) ---
os.makedirs("/downloads_public", exist_ok=True)
app.mount("/downloads", StaticFiles(directory="/downloads_public"), name="downloads")

# --- Configuração de Capas de Playlist ---
PLAYLIST_COVERS_DIR = "/downloads_public/playlist_covers"
os.makedirs(PLAYLIST_COVERS_DIR, exist_ok=True)

# --- Constantes ---
TIERS = {"low": "128k", "medium": "192k", "high": "320k", "lossless": "original"}

# --- Cache de Proxy de Imagem ---
SHORT_URL_MAP: Dict[str, dict] = {} 
PROXY_EXPIRY_SECONDS = 3600

# --- Modelos Pydantic para API ---
class UserCreate(BaseModel):
    username: str
    email: str
    password: str
    full_name: str

class Token(BaseModel):
    access_token: str
    token_type: str

# --- Modelos de Dados ---
class DownloadRequest(BaseModel):
    username: str
    filename: str
    size: Optional[int] = None

class AutoDownloadRequest(BaseModel):
    search_id: str

class SmartDownloadRequest(BaseModel):
    artist: str
    track: str
    album: Optional[str] = None
    tidalId: Optional[int] = None
    artworkUrl: Optional[str] = None

class FavoriteRequest(BaseModel):
    filename: str
    title: str
    artist: str
    album: Optional[str] = None

class HistoryRequest(BaseModel):
    filename: str
    duration_listened: float
    album_id: Optional[str] = None  # ID do álbum no catálogo (Tidal/YTMusic)
    genre: Optional[str] = None  # Gênero do álbum

class PlaylistCreate(BaseModel):
    name: str
    is_public: bool = False

class PlaylistItemAdd(BaseModel):
    filename: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None

# --- Helper de Usuário Atual ---
async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    from jose import JWTError, jwt
    try:
        payload = jwt.decode(token, auth_utils.SECRET_KEY, algorithms=[auth_utils.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Token inválido")
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido")
    
    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise HTTPException(status_code=401, detail="Usuário não encontrado")
    return user

# --- Helpers ---
async def download_file_background(url: str, dest_path: str, metadata: dict, cover_url: str = None):
    try:
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        temp_path = dest_path + ".tmp"
        async with httpx.AsyncClient() as client:
            async with client.stream('GET', url) as response:
                response.raise_for_status()
                with open(temp_path, 'wb') as f:
                    async for chunk in response.aiter_bytes():
                        f.write(chunk)
        
        cover_bytes = None
        target_cover = cover_url or await LyricsProvider.get_online_cover(dest_path)
        if target_cover:
            try:
                async with httpx.AsyncClient() as client:
                    resp = await client.get(target_cover, timeout=10.0)
                    if resp.status_code == 200: cover_bytes = resp.content
            except: pass
        
        if os.path.exists(dest_path):
             os.remove(dest_path)

        os.rename(temp_path, dest_path)
        if metadata: await run_in_threadpool(AudioManager.embed_metadata, dest_path, metadata, cover_bytes)
        print(f"✅ Download HTTP concluído e tagueado: {dest_path}")
    except Exception as e:
        print(f"❌ Erro download background: {e}")
        if os.path.exists(temp_path): os.remove(temp_path)

def normalize_text(text: str) -> str:
    if not text: return ""
    return unidecode(text.lower().replace("$", "s").replace("&", "and")).strip()

def get_db_session():
    """Helper para obter sessão do banco fora de contexto de request."""
    from .database import SessionLocal
    return SessionLocal()

def find_local_match_by_tidal_id(tidal_id: int) -> Optional[str]:
    """
    Busca arquivo local pelo tidal_id na tabela downloaded_tracks.
    Esta é a forma preferida de encontrar arquivos - garante unicidade.
    """
    if not tidal_id:
        return None
    
    db = get_db_session()
    try:
        downloaded = db.query(models.DownloadedTrack).filter(
            models.DownloadedTrack.tidal_id == tidal_id
        ).first()
        
        if downloaded and downloaded.local_path:
            full_path = os.path.join("/downloads", downloaded.local_path)
            if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
                return full_path
    except Exception as e:
        print(f"⚠️ Erro ao buscar por tidal_id: {e}")
    finally:
        db.close()
    
    return None

def find_local_match(artist: str, track: str, album: str = None, tidal_id: int = None) -> Optional[str]:
    """
    Busca arquivo local. Prioridade:
    1. tidal_id (mais preciso - garante unicidade)
    2. artist + track + album (match EXATO no banco)
    3. NÃO faz mais fallback fuzzy para evitar falsos positivos
    """
    print(f"🔍 find_local_match: artist='{artist}', track='{track}', album='{album}', tidal_id={tidal_id}")
    
    # 1. Primeiro tenta pelo tidal_id (mais confiável)
    if tidal_id:
        result = find_local_match_by_tidal_id(tidal_id)
        if result:
            print(f"   ✅ Encontrado por tidal_id: {result}")
            return result
        else:
            print(f"   ❌ Não encontrado por tidal_id")
    
    # 2. Busca no banco downloaded_tracks - precisa ter TODOS os campos batendo
    db = get_db_session()
    try:
        # Normaliza para comparação
        artist_norm = normalize_text(artist).lower() if artist else ""
        track_norm = normalize_text(track).lower() if track else ""
        album_norm = normalize_text(album).lower() if album else ""
        
        # Busca todos os registros do artista
        candidates = db.query(models.DownloadedTrack).filter(
            models.DownloadedTrack.artist.ilike(f"%{artist}%")
        ).all()
        
        for candidate in candidates:
            candidate_title = normalize_text(candidate.title or "").lower()
            candidate_album = normalize_text(candidate.album or "").lower()
            
            # Verifica se o título bate (usando fuzzy com threshold alto)
            title_score = fuzz.ratio(track_norm, candidate_title)
            
            # Precisa de score >= 85 para o título
            if title_score >= 85:
                # Se temos álbum, verifica também
                if album:
                    album_score = fuzz.ratio(album_norm, candidate_album)
                    if album_score < 70:
                        print(f"   ⚠️ Álbum não bate: '{album}' vs '{candidate.album}' (score: {album_score})")
                        continue
                
                full_path = os.path.join("/downloads", candidate.local_path)
                if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
                    print(f"   ✅ Encontrado no banco: {candidate.title} -> {full_path}")
                    return full_path
        
        print(f"   ❌ Não encontrado no banco (nenhum match de título >= 85%)")
        
    except Exception as e:
        print(f"⚠️ Erro ao buscar downloaded_tracks: {e}")
    finally:
        db.close()
    
    # NÃO faz mais fallback para busca fuzzy no disco
    # Isso evita falsos positivos como músicas diferentes do mesmo álbum
    print(f"   ❌ Nenhum match local encontrado para '{artist} - {track}'")
    return None

def register_download(tidal_id: int = None, ytmusic_id: str = None, 
                      title: str = None, artist: str = None, album: str = None,
                      local_path: str = None, source: str = "Tidal"):
    """
    Registra um download na tabela downloaded_tracks para rastreamento preciso.
    """
    db = get_db_session()
    try:
        # Verifica se já existe
        existing = None
        if tidal_id:
            existing = db.query(models.DownloadedTrack).filter(
                models.DownloadedTrack.tidal_id == tidal_id
            ).first()
        elif ytmusic_id:
            existing = db.query(models.DownloadedTrack).filter(
                models.DownloadedTrack.ytmusic_id == ytmusic_id
            ).first()
        
        if existing:
            # Atualiza o path se mudou
            existing.local_path = local_path
            db.commit()
            return existing
        
        # Cria novo registro
        new_download = models.DownloadedTrack(
            tidal_id=tidal_id,
            ytmusic_id=ytmusic_id,
            title=title,
            artist=artist,
            album=album,
            local_path=local_path,
            source=source
        )
        db.add(new_download)
        db.commit()
        db.refresh(new_download)
        return new_download
    except Exception as e:
        print(f"❌ Erro ao registrar download: {e}")
        db.rollback()
    finally:
        db.close()
    return None

def fetch_and_assign_genre(artist: str, album: str = None, title: str = None) -> str:
    """
    Busca o gênero de uma track usando a API do iTunes.
    Retorna o gênero encontrado ou None.
    """
    try:
        genre = MetadataProvider.get_genre(artist or "", album or "", title or "")
        if genre and genre != "Desconhecido":
            print(f"🎵 Gênero encontrado: {artist} - {title} → {genre}")
            return genre
    except Exception as e:
        print(f"⚠️ Erro ao buscar gênero: {e}")
    return None

def get_short_cover_url(filename: str) -> str:
    hash_object = hashlib.sha256(filename.encode())
    short_hash = hash_object.hexdigest()[:12]
    SHORT_URL_MAP[short_hash] = {
        "filename": filename,
        "expires": time.time() + PROXY_EXPIRY_SECONDS
    }
    # Substitua pelo seu domínio real em produção se necessário, ou use relativa
    return f"https://orfeu.ocnaibill.dev/cover/short/{short_hash}"

def get_update_config() -> dict:
    config_path = "/app/updates.json" 
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            return json.load(f)
    return {"latest_version": "0.0.0"}

# =====================================================
# CACHE DE GÊNEROS - Sistema de atualização automática
# =====================================================

# Lista de todos os gêneros suportados
SUPPORTED_GENRES = [
    "pop", "rock", "hip hop", "rap", "r&b", "electronic", "edm",
    "jazz", "classical", "country", "latin", "reggaeton", "k-pop",
    "j-pop", "metal", "indie", "alternative", "soul", "funk", 
    "blues", "reggae", "folk", "acoustic", "dance", "house",
    "techno", "ambient", "soundtrack", "anime", "brazilian",
    "mpb", "sertanejo", "pagode", "forró", "bossa nova"
]

# Queries otimizadas para cada gênero
GENRE_QUERIES = {
    "pop": "top pop hits 2024",
    "rock": "best rock songs",
    "hip hop": "hip hop hits 2024",
    "hip-hop": "hip hop hits 2024",
    "rap": "rap hits 2024",
    "r&b": "r&b hits 2024",
    "rnb": "r&b hits 2024",
    "electronic": "electronic dance music",
    "edm": "edm hits",
    "jazz": "jazz classics",
    "classical": "classical music popular",
    "country": "country hits 2024",
    "latin": "latin hits 2024",
    "reggaeton": "reggaeton hits 2024",
    "k-pop": "kpop hits 2024",
    "kpop": "kpop hits 2024",
    "j-pop": "jpop hits",
    "jpop": "jpop hits",
    "metal": "metal songs",
    "indie": "indie music hits",
    "alternative": "alternative rock hits",
    "soul": "soul music classics",
    "funk": "funk music hits",
    "blues": "blues music",
    "reggae": "reggae hits",
    "folk": "folk music",
    "acoustic": "acoustic songs",
    "dance": "dance music hits",
    "house": "house music",
    "techno": "techno music",
    "ambient": "ambient music",
    "soundtrack": "movie soundtracks popular",
    "anime": "anime openings",
    "brazilian": "brazilian music hits",
    "mpb": "mpb musica popular brasileira",
    "sertanejo": "sertanejo 2024",
    "pagode": "pagode hits",
    "forró": "forró hits",
    "bossa nova": "bossa nova classics",
}

# Cache em memória para evitar I/O constante (atualizado quando o banco é atualizado)
_genre_cache_memory: Dict[str, dict] = {}
_cache_last_refresh: float = 0
CACHE_MEMORY_TTL = 3600  # 1 hora em memória antes de revalidar com banco

async def fetch_genre_tracks_from_api(genre_name: str, limit: int = 100) -> list:
    """Busca tracks de um gênero no YouTube Music (chamada à API real)."""
    genre_lower = genre_name.lower().strip()
    search_query = GENRE_QUERIES.get(genre_lower, f"{genre_name} music hits")
    
    print(f"🎵 [API] Buscando tracks do gênero '{genre_name}' com query: '{search_query}'")
    
    results = await run_in_threadpool(
        CatalogProvider.search_catalog, 
        search_query, 
        "song", 
        limit
    )
    
    if not results:
        return []
    
    tracks = []
    seen_tracks = set()
    
    for item in results:
        track_key = f"{item.get('artistName', '').lower()}_{item.get('trackName', '').lower()}"
        if track_key in seen_tracks:
            continue
        seen_tracks.add(track_key)
        
        duration_ms = item.get('durationMs', 0)
        
        # Filtra tracks muito longas ou curtas
        if duration_ms > 600000 or (duration_ms > 0 and duration_ms < 30000):
            continue
        
        tracks.append({
            "trackName": item.get('trackName', ''),
            "artistName": item.get('artistName', ''),
            "collectionName": item.get('collectionName', ''),
            "artworkUrl": item.get('artworkUrl', ''),
            "videoId": item.get('videoId'),
            "duration": item.get('duration', ''),
            "durationMs": duration_ms,
            "source": "YTMusic",
            "genre": genre_name,
        })
    
    return tracks

async def update_genre_cache_single(db: Session, genre_name: str) -> bool:
    """Atualiza o cache de um único gênero."""
    try:
        tracks = await fetch_genre_tracks_from_api(genre_name)
        
        if not tracks:
            print(f"⚠️ Nenhuma track encontrada para '{genre_name}'")
            return False
        
        genre_lower = genre_name.lower().strip()
        
        # Upsert no banco de dados
        existing = db.query(models.GenreCache).filter(
            models.GenreCache.genre_name == genre_lower
        ).first()
        
        if existing:
            existing.tracks = tracks
            existing.track_count = len(tracks)
            existing.source = "ytmusic"
        else:
            cache_entry = models.GenreCache(
                genre_name=genre_lower,
                tracks=tracks,
                track_count=len(tracks),
                source="ytmusic"
            )
            db.add(cache_entry)
        
        db.commit()
        
        # Atualiza cache em memória
        _genre_cache_memory[genre_lower] = {
            "tracks": tracks,
            "track_count": len(tracks),
            "source": "ytmusic"
        }
        
        print(f"✅ Cache atualizado para '{genre_name}': {len(tracks)} tracks")
        return True
        
    except Exception as e:
        print(f"❌ Erro ao atualizar cache de '{genre_name}': {e}")
        db.rollback()
        return False

async def update_all_genres_cache():
    """Atualiza o cache de todos os gêneros. Executado em background."""
    from .database import SessionLocal
    
    print("🔄 Iniciando atualização completa do cache de gêneros...")
    start_time = time.time()
    
    db = SessionLocal()
    success_count = 0
    
    try:
        for genre in SUPPORTED_GENRES:
            try:
                if await update_genre_cache_single(db, genre):
                    success_count += 1
                # Delay entre requests para não sobrecarregar a API
                await asyncio.sleep(2)
            except Exception as e:
                print(f"❌ Erro no gênero '{genre}': {e}")
                continue
        
        elapsed = time.time() - start_time
        print(f"✅ Cache de gêneros atualizado! {success_count}/{len(SUPPORTED_GENRES)} gêneros em {elapsed:.1f}s")
        
        global _cache_last_refresh
        _cache_last_refresh = time.time()
        
    finally:
        db.close()

def get_cached_genre_tracks(db: Session, genre_name: str) -> Optional[dict]:
    """Busca tracks do cache (memória primeiro, depois banco)."""
    genre_lower = genre_name.lower().strip()
    
    # Tenta cache em memória primeiro
    if genre_lower in _genre_cache_memory:
        return _genre_cache_memory[genre_lower]
    
    # Se não está em memória, busca no banco
    cached = db.query(models.GenreCache).filter(
        models.GenreCache.genre_name == genre_lower
    ).first()
    
    if cached:
        # Carrega em memória para próximas requisições
        _genre_cache_memory[genre_lower] = {
            "tracks": cached.tracks,
            "track_count": cached.track_count,
            "source": cached.source,
            "updated_at": cached.updated_at.isoformat() if cached.updated_at else None
        }
        return _genre_cache_memory[genre_lower]
    
    return None

# Background task scheduler
_genre_cache_task: Optional[asyncio.Task] = None

async def genre_cache_scheduler():
    """Loop que atualiza o cache a cada 24 horas."""
    while True:
        try:
            await update_all_genres_cache()
        except Exception as e:
            print(f"❌ Erro no scheduler de cache: {e}")
        
        # Aguarda 24 horas
        await asyncio.sleep(24 * 60 * 60)

@app.on_event("startup")
async def startup_event():
    """Inicializa o scheduler de cache de gêneros na inicialização."""
    global _genre_cache_task
    
    # Carrega cache existente do banco para memória
    from .database import SessionLocal
    db = SessionLocal()
    try:
        cached_genres = db.query(models.GenreCache).all()
        for cached in cached_genres:
            _genre_cache_memory[cached.genre_name] = {
                "tracks": cached.tracks,
                "track_count": cached.track_count,
                "source": cached.source,
                "updated_at": cached.updated_at.isoformat() if cached.updated_at else None
            }
        print(f"📦 Cache carregado: {len(cached_genres)} gêneros em memória")
    finally:
        db.close()
    
    # Inicia o scheduler em background
    _genre_cache_task = asyncio.create_task(genre_cache_scheduler())
    print("🚀 Scheduler de cache de gêneros iniciado (atualização a cada 24h)")

@app.on_event("shutdown")
async def shutdown_event():
    """Cancela o scheduler ao desligar."""
    global _genre_cache_task
    if _genre_cache_task:
        _genre_cache_task.cancel()
        print("⏹️ Scheduler de cache de gêneros encerrado")

# =====================================================
# FIM DO SISTEMA DE CACHE DE GÊNEROS
# =====================================================

# --- Configuração do Web App ---
WEB_APP_DIR = "/downloads_public/web"
if os.path.exists(WEB_APP_DIR):
    app.mount("/app", StaticFiles(directory=WEB_APP_DIR, html=True), name="webapp")
    print(f"🌐 Web App montado em /app")

# --- Rotas ---
@app.get("/")
def read_root(request: Request):
    """
    Rota raiz: 
    - Se acessado de navegador: redireciona para /app (web app)
    - Se acessado de API: retorna status JSON
    """
    # Verifica se é um navegador pelo header Accept
    accept = request.headers.get("accept", "")
    user_agent = request.headers.get("user-agent", "").lower()
    
    # Se é um navegador pedindo HTML e o web app existe
    is_browser = "text/html" in accept or "mozilla" in user_agent or "chrome" in user_agent
    web_app_exists = os.path.exists(f"{WEB_APP_DIR}/index.html")
    
    if is_browser and web_app_exists:
        return RedirectResponse(url="/app", status_code=302)
    
    # Caso contrário, retorna status da API
    return {"status": "Orfeu is alive", "service": "Backend", "version": "2.4.0"}


# --- ROTAS DE AUTENTICAÇÃO ---

@app.post("/auth/register", response_model=Token)
def register(user: UserCreate, db: Session = Depends(get_db)):
    # Verifica se existe
    db_user = db.query(models.User).filter(models.User.username == user.username).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Username já cadastrado")
    
    # Cria usuário
    hashed_pwd = auth_utils.get_password_hash(user.password)
    db_user = models.User(
        username=user.username, 
        email=user.email, 
        full_name=user.full_name, 
        hashed_password=hashed_pwd
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    
    # Gera Token
    access_token = auth_utils.create_access_token(data={"sub": db_user.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/token", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if not user or not auth_utils.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuário ou senha incorretos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = auth_utils.create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/users/me")
def read_users_me(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Calcula horas totais ouvidas
    total_seconds = db.query(func.sum(models.ListenHistory.duration_listened))\
        .filter(models.ListenHistory.user_id == current_user.id)\
        .scalar() or 0
    
    # Top gêneros (do histórico)
    top_genres = db.query(models.Track.genre, func.count(models.ListenHistory.id).label('count'))\
        .join(models.ListenHistory)\
        .filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.genre.isnot(None),
            models.Track.genre != ''
        )\
        .group_by(models.Track.genre)\
        .order_by(desc('count'))\
        .limit(5)\
        .all()
    
    # Total de playlists
    playlist_count = db.query(models.Playlist).filter(models.Playlist.user_id == current_user.id).count()
    
    # Total de favoritos
    favorites_count = db.query(models.Favorite).filter(models.Favorite.user_id == current_user.id).count()
    
    return {
        "username": current_user.username, 
        "full_name": current_user.full_name,
        "email": current_user.email,
        "profile_image_url": current_user.profile_image_url,
        "stats": {
            "hours_listened": round(total_seconds / 3600, 1),
            "minutes_listened": int(total_seconds / 60),
            "top_genres": [{"genre": g, "plays": c} for g, c in top_genres],
            "playlist_count": playlist_count,
            "favorites_count": favorites_count
        },
        "created_at": current_user.created_at.isoformat() if current_user.created_at else None
    }

class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    profile_image_url: Optional[str] = None  # URL da imagem
    current_password: Optional[str] = None  # Senha atual (para verificação)
    new_password: Optional[str] = None  # Nova senha

@app.put("/users/me")
def update_profile(profile: ProfileUpdate, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """Atualiza dados do perfil do usuário"""
    if profile.full_name is not None:
        current_user.full_name = profile.full_name
    if profile.email is not None:
        # Verifica se email já está em uso por outro usuário
        existing = db.query(models.User).filter(
            models.User.email == profile.email, 
            models.User.id != current_user.id
        ).first()
        if existing:
            raise HTTPException(400, "Email já está em uso")
        current_user.email = profile.email
    if profile.profile_image_url is not None:
        current_user.profile_image_url = profile.profile_image_url
    
    # Alteração de senha
    if profile.new_password is not None:
        if not profile.current_password:
            raise HTTPException(400, "Senha atual é obrigatória")
        # Verifica senha atual
        if not verify_password(profile.current_password, current_user.password_hash):
            raise HTTPException(400, "Senha atual incorreta")
        # Atualiza para nova senha
        current_user.password_hash = hash_password(profile.new_password)
    
    db.commit()
    db.refresh(current_user)
    
    return {"status": "updated", "username": current_user.username}

# Upload de imagem de perfil
class ProfileImageUpload(BaseModel):
    image_data: str  # Base64 da imagem (pode ser PNG, JPG, GIF, WebP)
    content_type: str = "image/png"  # Tipo MIME da imagem

@app.post("/users/me/profile-image")
def upload_profile_image(
    upload: ProfileImageUpload,
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    """
    Faz upload da imagem de perfil do usuário.
    Aceita PNG, JPG, GIF, WebP em formato base64.
    """
    import base64
    import uuid
    
    # Valida tipo de imagem
    allowed_types = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/gif": ".gif",
        "image/webp": ".webp",
    }
    
    if upload.content_type not in allowed_types:
        raise HTTPException(400, f"Tipo de imagem não suportado: {upload.content_type}. Use PNG, JPG, GIF ou WebP.")
    
    extension = allowed_types[upload.content_type]
    
    try:
        # Decodifica base64
        image_bytes = base64.b64decode(upload.image_data)
        
        # Limite de 10MB
        if len(image_bytes) > 10 * 1024 * 1024:
            raise HTTPException(400, "Imagem muito grande. Máximo: 10MB")
        
        # Gera nome único para o arquivo
        filename = f"profile_{current_user.id}_{uuid.uuid4().hex[:8]}{extension}"
        
        # Salva na pasta pública
        profile_images_dir = "/downloads_public/profile_images"
        os.makedirs(profile_images_dir, exist_ok=True)
        
        filepath = os.path.join(profile_images_dir, filename)
        with open(filepath, "wb") as f:
            f.write(image_bytes)
        
        # Remove imagem antiga se existir
        if current_user.profile_image_url:
            old_filename = current_user.profile_image_url.split("/")[-1]
            old_path = os.path.join(profile_images_dir, old_filename)
            if os.path.exists(old_path) and old_filename.startswith("profile_"):
                try:
                    os.remove(old_path)
                except:
                    pass
        
        # Atualiza URL no banco
        image_url = f"https://orfeu.ocnaibill.dev/downloads/profile_images/{filename}"
        current_user.profile_image_url = image_url
        db.commit()
        
        return {"status": "uploaded", "url": image_url}
        
    except base64.binascii.Error:
        raise HTTPException(400, "Dados de imagem inválidos (não é base64 válido)")
    except Exception as e:
        raise HTTPException(500, f"Erro ao salvar imagem: {str(e)}")

# Favoritos
@app.post("/users/me/favorites")
def toggle_favorite(req: FavoriteRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    # 1. Garante que a track existe no DB (Sincronização Lazy)
    track = db.query(models.Track).filter(models.Track.filename == req.filename).first()
    if not track:
        # Tenta pegar duração real
        duration = 0
        try:
            fp = AudioManager.find_local_file(req.filename)
            meta = AudioManager.get_audio_metadata(fp)
            duration = meta.get('duration', 0)
        except: pass
        
        # Busca gênero automaticamente
        genre = fetch_and_assign_genre(req.artist, req.album, req.title)
        
        track = models.Track(
            filename=req.filename, 
            title=req.title, 
            artist=req.artist, 
            album=req.album, 
            duration=duration,
            genre=genre
        )
        db.add(track)
        db.commit()
        db.refresh(track)
    
    # 2. Toggle Favorito
    fav = db.query(models.Favorite).filter(models.Favorite.user_id == current_user.id, models.Favorite.track_id == track.id).first()
    if fav:
        db.delete(fav)
        db.commit()
        return {"status": "removed", "track": req.title}
    else:
        new_fav = models.Favorite(user_id=current_user.id, track_id=track.id)
        db.add(new_fav)
        db.commit()
        return {"status": "added", "track": req.title}

@app.get("/users/me/favorites")
def get_favorites(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    favorites = db.query(models.Track).join(models.Favorite).filter(models.Favorite.user_id == current_user.id).all()
    # Retorna no formato compatível com o LibraryScreen
    return [{
        "filename": t.filename,
        "display_name": t.title,
        "artist": t.artist,
        "album": t.album,
        "duration": t.duration,
        "format": t.filename.split('.')[-1] if t.filename else "",
        "coverProxyUrl": get_short_cover_url(t.filename) if t.filename else None,
        "isFavorite": True,
        "tidalId": t.tidal_id  # Inclui tidal_id para verificação de favoritos
    } for t in favorites]

# --- BIBLIOTECA DE ÁLBUNS E ARTISTAS ---
class SaveAlbumRequest(BaseModel):
    album_id: str
    title: str
    artist: str
    artwork_url: Optional[str] = None
    year: Optional[int] = None

class SaveArtistRequest(BaseModel):
    artist_id: str
    name: str
    image_url: Optional[str] = None

@app.get("/users/me/albums")
def get_saved_albums(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    albums = db.query(models.SavedAlbum).filter(models.SavedAlbum.user_id == current_user.id).order_by(models.SavedAlbum.added_at.desc()).all()
    return [{
        "id": a.album_id,
        "title": a.title,
        "artist": a.artist,
        "artworkUrl": a.artwork_url,
        "year": a.year,
        "isPinned": a.is_pinned,
        "savedAt": a.added_at.isoformat() if a.added_at else None
    } for a in albums]

@app.post("/users/me/albums")
def save_album(req: SaveAlbumRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    # Verifica se já está salvo
    existing = db.query(models.SavedAlbum).filter(
        models.SavedAlbum.user_id == current_user.id,
        models.SavedAlbum.album_id == req.album_id
    ).first()
    if existing:
        return {"message": "Álbum já está na biblioteca", "id": existing.id}
    
    album = models.SavedAlbum(
        user_id=current_user.id,
        album_id=req.album_id,
        title=req.title,
        artist=req.artist,
        artwork_url=req.artwork_url,
        year=req.year
    )
    db.add(album)
    db.commit()
    db.refresh(album)
    return {"message": "Álbum adicionado à biblioteca", "id": album.id}

@app.delete("/users/me/albums/{album_id}")
def remove_saved_album(album_id: str, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    album = db.query(models.SavedAlbum).filter(
        models.SavedAlbum.user_id == current_user.id,
        models.SavedAlbum.album_id == album_id
    ).first()
    if not album:
        raise HTTPException(404, "Álbum não encontrado na biblioteca")
    db.delete(album)
    db.commit()
    return {"message": "Álbum removido da biblioteca"}

@app.patch("/users/me/albums/{album_id}/pin")
def toggle_album_pin(album_id: str, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    album = db.query(models.SavedAlbum).filter(
        models.SavedAlbum.user_id == current_user.id,
        models.SavedAlbum.album_id == album_id
    ).first()
    if not album:
        raise HTTPException(404, "Álbum não encontrado na biblioteca")
    album.is_pinned = not album.is_pinned
    db.commit()
    return {"isPinned": album.is_pinned}

@app.get("/users/me/artists")
def get_saved_artists(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    artists = db.query(models.SavedArtist).filter(models.SavedArtist.user_id == current_user.id).order_by(models.SavedArtist.added_at.desc()).all()
    return [{
        "id": a.artist_id,
        "name": a.name,
        "imageUrl": a.image_url,
        "isPinned": a.is_pinned,
        "savedAt": a.added_at.isoformat() if a.added_at else None
    } for a in artists]

@app.post("/users/me/artists")
def save_artist(req: SaveArtistRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    existing = db.query(models.SavedArtist).filter(
        models.SavedArtist.user_id == current_user.id,
        models.SavedArtist.artist_id == req.artist_id
    ).first()
    if existing:
        return {"message": "Artista já está na biblioteca", "id": existing.id}
    
    artist = models.SavedArtist(
        user_id=current_user.id,
        artist_id=req.artist_id,
        name=req.name,
        image_url=req.image_url
    )
    db.add(artist)
    db.commit()
    db.refresh(artist)
    return {"message": "Artista adicionado à biblioteca", "id": artist.id}

@app.delete("/users/me/artists/{artist_id}")
def remove_saved_artist(artist_id: str, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    artist = db.query(models.SavedArtist).filter(
        models.SavedArtist.user_id == current_user.id,
        models.SavedArtist.artist_id == artist_id
    ).first()
    if not artist:
        raise HTTPException(404, "Artista não encontrado na biblioteca")
    db.delete(artist)
    db.commit()
    return {"message": "Artista removido da biblioteca"}

# --- PLAYLISTS (NOVAS ROTAS) ---
@app.post("/users/me/playlists")
def create_playlist(playlist: PlaylistCreate, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    db_playlist = models.Playlist(name=playlist.name, is_public=playlist.is_public, user_id=current_user.id)
    db.add(db_playlist)
    db.commit()
    db.refresh(db_playlist)
    return db_playlist

@app.get("/users/me/playlists")
def get_playlists(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return db.query(models.Playlist).filter(models.Playlist.user_id == current_user.id).all()

@app.post("/users/me/playlists/{playlist_id}/tracks")
def add_track_to_playlist(playlist_id: int, item: PlaylistItemAdd, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id, models.Playlist.user_id == current_user.id).first()
    if not playlist: raise HTTPException(404, "Playlist não encontrada ou acesso negado")
    
    # Lazy creation da Track se não existir
    track = db.query(models.Track).filter(models.Track.filename == item.filename).first()
    if not track:
        duration = 0
        try:
            fp = AudioManager.find_local_file(item.filename)
            meta = AudioManager.get_audio_metadata(fp)
            duration = meta.get('duration', 0)
        except: pass
        
        # Busca gênero automaticamente
        genre = fetch_and_assign_genre(item.artist, item.album, item.title)
        
        track = models.Track(
            filename=item.filename, 
            title=item.title or "Desconhecido", 
            artist=item.artist or "Desconhecido", 
            album=item.album, 
            duration=duration,
            genre=genre
        )
        db.add(track)
        db.commit()
        db.refresh(track)
        
    # Adiciona à playlist no fim da lista
    last_item = db.query(models.PlaylistItem).filter(models.PlaylistItem.playlist_id == playlist_id).order_by(models.PlaylistItem.order.desc()).first()
    new_order = (last_item.order + 1) if last_item else 0
    
    playlist_item = models.PlaylistItem(playlist_id=playlist.id, track_id=track.id, order=new_order)
    db.add(playlist_item)
    db.commit()
    return {"status": "added", "track": track.title}

@app.get("/users/me/playlists/{playlist_id}")
def get_playlist_details(playlist_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id).first()
    if not playlist: raise HTTPException(404, "Playlist não encontrada")
    
    if not playlist.is_public and playlist.user_id != current_user.id:
        raise HTTPException(403, "Playlist privada")

    tracks_data = []
    # Ordena pelo campo 'order'
    for item in sorted(playlist.items, key=lambda x: x.order):
        t = item.track
        tracks_data.append({
            "filename": t.filename,
            "display_name": t.title,
            "artist": t.artist,
            "album": t.album,
            "duration": t.duration,
            "format": t.filename.split('.')[-1] if t.filename else "",
            "coverProxyUrl": get_short_cover_url(t.filename) if t.filename else None,
            "id": t.id,
            "playlist_item_id": item.id
        })
        
    return {
        "id": playlist.id,
        "name": playlist.name,
        "is_public": playlist.is_public,
        "cover_url": playlist.cover_url,
        "tracks": tracks_data
    }

class PlaylistUpdateRequest(BaseModel):
    name: Optional[str] = None
    cover_url: Optional[str] = None
    is_public: Optional[bool] = None

@app.put("/users/me/playlists/{playlist_id}")
def update_playlist(playlist_id: int, req: PlaylistUpdateRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """Atualiza nome, capa ou visibilidade da playlist."""
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(404, "Playlist não encontrada")
    
    if playlist.user_id != current_user.id:
        raise HTTPException(403, "Sem permissão para editar esta playlist")
    
    if req.name is not None:
        playlist.name = req.name
    if req.cover_url is not None:
        playlist.cover_url = req.cover_url
    if req.is_public is not None:
        playlist.is_public = req.is_public
    
    db.commit()
    db.refresh(playlist)
    
    return {
        "status": "updated",
        "playlist": {
            "id": playlist.id,
            "name": playlist.name,
            "cover_url": playlist.cover_url,
            "is_public": playlist.is_public
        }
    }


@app.post("/users/me/playlists/{playlist_id}/cover")
async def upload_playlist_cover(
    playlist_id: int, 
    file: UploadFile = File(...), 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    """Faz upload de uma imagem para ser a capa da playlist."""
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(404, "Playlist não encontrada")
    
    if playlist.user_id != current_user.id:
        raise HTTPException(403, "Sem permissão para editar esta playlist")
    
    # Valida tipo de arquivo
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(400, "O arquivo deve ser uma imagem")
    
    # Gera nome único para o arquivo
    ext = file.filename.split(".")[-1] if file.filename and "." in file.filename else "jpg"
    unique_filename = f"playlist_{playlist_id}_{uuid.uuid4().hex[:8]}.{ext}"
    file_path = os.path.join(PLAYLIST_COVERS_DIR, unique_filename)
    
    # Remove capa antiga se existir (e for do mesmo sistema)
    if playlist.cover_url and "/playlist_covers/" in playlist.cover_url:
        old_filename = playlist.cover_url.split("/")[-1]
        old_path = os.path.join(PLAYLIST_COVERS_DIR, old_filename)
        if os.path.exists(old_path):
            os.remove(old_path)
    
    # Salva o arquivo
    contents = await file.read()
    with open(file_path, "wb") as f:
        f.write(contents)
    
    # Atualiza URL no banco
    cover_url = f"https://orfeu.ocnaibill.dev/downloads/playlist_covers/{unique_filename}"
    playlist.cover_url = cover_url
    db.commit()
    
    return {
        "status": "uploaded",
        "cover_url": cover_url
    }


# --- ROTAS DA HOME (FEED & ANALYTICS)  ---
@app.get("/home/continue-listening")
def get_continue_listening(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_recently_played(db, current_user.id, limit)

@app.get("/home/trajectory")
def get_trajectory(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    retro_playlists = db.query(models.Playlist)\
        .filter(models.Playlist.user_id == current_user.id, models.Playlist.name.like("Retrospectiva%"))\
        .order_by(models.Playlist.created_at.desc())\
        .all()
    return [{
        "id": p.id,
        "title": p.name,
        "artist": "Orfeu Rewind",
        "imageUrl": f"https://ui-avatars.com/api/?name={quote(p.name)}&background=D4AF37&color=000&size=300",
        "type": "playlist"
    } for p in retro_playlists]

@app.get("/home/discover")
async def get_discover_weekly(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Descobertas da Semana - Artistas que você ainda não ouviu mas pode gostar.
    Baseado em artistas similares aos seus favoritos.
    """
    try:
        # 1. Top 5 artistas do usuário
        top_artists = db.query(models.Track.artist, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == current_user.id)\
            .group_by(models.Track.artist)\
            .order_by(desc('count'))\
            .limit(5)\
            .all()
        
        known_artists = {a[0].lower() for a in top_artists if a[0]}
        discoveries = []
        seen_artists = set()
        
        if not top_artists:
            # Usuário novo - mostra artistas populares variados
            search_terms = ["indie pop", "alternative", "r&b soul", "electronic"]
        else:
            # Busca "artista similar" ou "fans also like"
            search_terms = [f"{a[0]} similar artists" for a in top_artists[:3]]
        
        for search_term in search_terms:
            try:
                results = await run_in_threadpool(TidalProvider.search_catalog, search_term, 10, "album")
                
                for item in results:
                    artist_lower = item.get('artistName', '').lower()
                    
                    # Pula artistas já conhecidos ou já adicionados
                    if artist_lower in known_artists or artist_lower in seen_artists:
                        continue
                    
                    seen_artists.add(artist_lower)
                    discoveries.append({
                        "title": item['collectionName'],
                        "artist": item['artistName'],
                        "imageUrl": item['artworkUrl'],
                        "type": "album",
                        "id": item['collectionId'],
                        "reason": "Descoberta para você"
                    })
                    
                    if len(discoveries) >= limit:
                        break
                        
            except Exception as e:
                continue
            
            if len(discoveries) >= limit:
                break
        
        return discoveries[:limit]
        
    except Exception as e:
        print(f"❌ Erro em discover: {e}")
        return []

@app.get("/home/recommendations")
async def get_recommendations(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Recomendações personalizadas baseadas no histórico real do usuário.
    
    Estratégia em 3 níveis:
    1. OURO: Outros álbuns dos artistas mais ouvidos (descoberta dentro do mesmo artista)
    2. PRATA: Álbuns de artistas do mesmo gênero que o usuário ouve
    3. BRONZE: Baseado em álbuns/artistas salvos na biblioteca
    """
    try:
        recommendations = []
        seen_ids = set()
        seen_artists = set()
        
        # =========================================================
        # 1. COLETA DE DADOS DO USUÁRIO
        # =========================================================
        
        # 1.1 Artistas mais ouvidos (com contagem)
        top_artists_data = db.query(
            models.Track.artist, 
            func.count(models.ListenHistory.id).label('play_count')
        ).join(models.ListenHistory).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.artist.isnot(None),
            models.Track.artist != "",
            models.Track.artist != "Desconhecido"
        ).group_by(models.Track.artist).order_by(desc('play_count')).limit(10).all()
        
        top_artists = [a[0] for a in top_artists_data if a[0]]
        top_artists_lower = {a.lower() for a in top_artists}
        
        # 1.2 Álbuns já ouvidos (para não recomendar repetidos)
        listened_albums = db.query(models.Track.album).join(models.ListenHistory).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.album.isnot(None)
        ).distinct().all()
        listened_albums_set = {normalize_text(a[0]) for a in listened_albums if a[0]}
        
        # 1.3 Gêneros mais ouvidos
        top_genres = db.query(models.Track.genre, func.count(models.ListenHistory.id).label('count')).join(
            models.ListenHistory
        ).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.genre.isnot(None),
            models.Track.genre != "",
            models.Track.genre != "Desconhecido"
        ).group_by(models.Track.genre).order_by(desc('count')).limit(3).all()
        
        user_genres = [g[0] for g in top_genres] if top_genres else []
        
        # 1.4 Artistas salvos na biblioteca
        saved_artists = db.query(models.SavedArtist).filter(
            models.SavedArtist.user_id == current_user.id
        ).limit(5).all()
        saved_artist_names = [a.name for a in saved_artists]
        
        print(f"🎯 Recomendações para {current_user.username}:")
        print(f"   Top Artistas: {top_artists[:5]}")
        print(f"   Gêneros: {user_genres}")
        print(f"   Álbuns ouvidos: {len(listened_albums_set)}")
        
        # =========================================================
        # 2. FASE OURO: Outros álbuns dos artistas favoritos
        # =========================================================
        if top_artists and len(recommendations) < limit:
            print(f"🥇 Fase OURO: Buscando discografia dos top artistas...")
            
            for artist in top_artists[:5]:  # Top 5 artistas
                if len(recommendations) >= limit:
                    break
                    
                try:
                    # Busca o artista no Tidal para pegar o ID
                    artist_search = await run_in_threadpool(
                        TidalProvider.search_catalog, artist, 1, "artist"
                    )
                    
                    if not artist_search:
                        continue
                    
                    # Verifica se é realmente o artista certo
                    found_artist = artist_search[0]
                    if fuzz.token_sort_ratio(
                        normalize_text(artist), 
                        normalize_text(found_artist.get('artistName', ''))
                    ) < 85:
                        continue
                    
                    artist_id = found_artist.get('artistId')
                    if not artist_id:
                        continue
                    
                    # Busca detalhes do artista (inclui álbuns)
                    artist_details = await run_in_threadpool(
                        TidalProvider.get_artist_details, artist_id
                    )
                    
                    if not artist_details:
                        continue
                    
                    # Pega álbuns e singles
                    all_releases = artist_details.get('albums', []) + artist_details.get('singles', [])
                    
                    # Ordena por data de lançamento (mais recente primeiro)
                    all_releases.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                    
                    for release in all_releases[:3]:  # Top 3 releases por artista
                        album_name = release.get('collectionName', '')
                        album_id = release.get('collectionId')
                        
                        if not album_id or album_id in seen_ids:
                            continue
                        
                        # Não recomenda álbuns já ouvidos
                        if normalize_text(album_name) in listened_albums_set:
                            continue
                        
                        seen_ids.add(album_id)
                        recommendations.append({
                            "title": album_name,
                            "artist": release.get('artistName', artist),
                            "imageUrl": release.get('artworkUrl', ''),
                            "type": "album",
                            "id": album_id,
                            "year": release.get('year', ''),
                            "reason": f"Mais de {artist}"
                        })
                        
                        if len(recommendations) >= limit:
                            break
                            
                except Exception as e:
                    print(f"   ⚠️ Erro buscando álbuns de {artist}: {e}")
                    continue
        
        # =========================================================
        # 3. FASE PRATA: Artistas do mesmo gênero
        # =========================================================
        if user_genres and len(recommendations) < limit:
            print(f"🥈 Fase PRATA: Buscando artistas dos gêneros {user_genres}...")
            
            for genre in user_genres:
                if len(recommendations) >= limit:
                    break
                
                try:
                    # Busca artistas específicos do gênero (não genérico)
                    # Usa o gênero + "artist" para buscar artistas reais
                    genre_artists = await run_in_threadpool(
                        TidalProvider.search_catalog, f"{genre}", 10, "artist"
                    )
                    
                    if not genre_artists:
                        continue
                    
                    for genre_artist in genre_artists:
                        artist_name = genre_artist.get('artistName', '')
                        
                        # Pula artistas já ouvidos
                        if artist_name.lower() in top_artists_lower:
                            continue
                        
                        # Pula artistas já recomendados
                        if artist_name.lower() in seen_artists:
                            continue
                        
                        seen_artists.add(artist_name.lower())
                        
                        # Busca o álbum mais popular desse artista
                        try:
                            artist_id = genre_artist.get('artistId')
                            if artist_id:
                                artist_details = await run_in_threadpool(
                                    TidalProvider.get_artist_details, artist_id
                                )
                                
                                if artist_details and artist_details.get('albums'):
                                    top_album = artist_details['albums'][0]
                                    album_id = top_album.get('collectionId')
                                    
                                    if album_id and album_id not in seen_ids:
                                        seen_ids.add(album_id)
                                        recommendations.append({
                                            "title": top_album.get('collectionName', ''),
                                            "artist": artist_name,
                                            "imageUrl": top_album.get('artworkUrl', ''),
                                            "type": "album",
                                            "id": album_id,
                                            "year": top_album.get('year', ''),
                                            "reason": f"Porque você curte {genre}"
                                        })
                                        
                                        if len(recommendations) >= limit:
                                            break
                        except:
                            continue
                            
                except Exception as e:
                    print(f"   ⚠️ Erro buscando gênero {genre}: {e}")
                    continue
        
        # =========================================================
        # 4. FASE BRONZE: Baseado em artistas salvos
        # =========================================================
        if saved_artist_names and len(recommendations) < limit:
            print(f"🥉 Fase BRONZE: Recomendações de artistas salvos...")
            
            for saved_artist in saved_artist_names:
                if saved_artist.lower() in top_artists_lower:
                    continue  # Já coberto na fase ouro
                    
                if len(recommendations) >= limit:
                    break
                
                try:
                    artist_search = await run_in_threadpool(
                        TidalProvider.search_catalog, saved_artist, 1, "artist"
                    )
                    
                    if artist_search:
                        artist_id = artist_search[0].get('artistId')
                        if artist_id:
                            artist_details = await run_in_threadpool(
                                TidalProvider.get_artist_details, artist_id
                            )
                            
                            if artist_details and artist_details.get('albums'):
                                for album in artist_details['albums'][:2]:
                                    album_id = album.get('collectionId')
                                    album_name = album.get('collectionName', '')
                                    
                                    if album_id in seen_ids:
                                        continue
                                    if normalize_text(album_name) in listened_albums_set:
                                        continue
                                    
                                    seen_ids.add(album_id)
                                    recommendations.append({
                                        "title": album_name,
                                        "artist": saved_artist,
                                        "imageUrl": album.get('artworkUrl', ''),
                                        "type": "album",
                                        "id": album_id,
                                        "year": album.get('year', ''),
                                        "reason": f"Da sua biblioteca"
                                    })
                                    
                                    if len(recommendations) >= limit:
                                        break
                except:
                    continue
        
        # =========================================================
        # 5. Embaralha levemente para variedade (mantendo prioridade)
        # =========================================================
        import random
        if len(recommendations) > 5:
            # Divide em grupos de prioridade e embaralha dentro de cada grupo
            high_priority = recommendations[:len(recommendations)//2]
            low_priority = recommendations[len(recommendations)//2:]
            random.shuffle(high_priority)
            random.shuffle(low_priority)
            recommendations = high_priority + low_priority
        
        print(f"✅ Retornando {len(recommendations)} recomendações personalizadas")
        return recommendations[:limit]
        
    except Exception as e:
        print(f"❌ Erro em recommendations: {e}")
        import traceback
        traceback.print_exc()
        return []

# --- NOVIDADES PERSONALIZADAS ---
@app.get("/home/new-releases")
async def get_new_releases(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Seção 'Novidades dos seus favoritos':
    - Se o usuário tem histórico: busca novidades dos artistas mais ouvidos
    - Se não tem: busca lançamentos populares recentes
    """
    try:
        # 1. Identifica Top Artistas do usuário
        top_artists_query = db.query(models.Track.artist, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == current_user.id)\
            .group_by(models.Track.artist)\
            .order_by(desc('count'))\
            .limit(10)\
            .all()
        
        top_artists_names = [a[0] for a in top_artists_query if a[0] and a[0] != "Desconhecido"]
        
        # 2. Se tem artistas favoritos, busca novidades deles
        if top_artists_names:
            recommender = MusicRecommender()
            news = await recommender.get_new_releases(top_artists_names, limit=limit)
            if news:
                return news
        
        # 3. Fallback: Busca lançamentos populares no Tidal
        print("📢 Usuário sem histórico suficiente, buscando novidades gerais...")
        try:
            # Busca álbuns populares/novos
            results = await run_in_threadpool(TidalProvider.search_catalog, "new releases 2024", limit, "album")
            
            if results:
                return [{
                    "title": item.get('collectionName', 'Álbum'),
                    "artist": item.get('artistName', 'Artista'),
                    "imageUrl": item.get('artworkUrl', ''),
                    "type": "album",
                    "id": item.get('collectionId'),
                    "vibrantColorHex": "#D4AF37",
                    "tags": ["Popular"]
                } for item in results[:limit]]
        except Exception as fallback_e:
            print(f"⚠️ Fallback também falhou: {fallback_e}")
        
        return []

    except Exception as e:
        print(f"❌ Erro crítico em new-releases: {e}")
        return []


# --- ANALYTICS (PERFIL) ---
@app.get("/users/me/analytics/summary")
async def get_my_analytics(days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return await AnalyticsService.get_user_stats_async(db, current_user.id, days)

@app.get("/users/me/analytics/top-tracks")
def get_my_top_tracks(limit: int = 10, days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_top_tracks(db, current_user.id, limit, days)


@app.get("/analytics/rankings")
def get_global_rankings(db: Session = Depends(get_db)):
    """
    Retorna o ranking global de usuários (quem ouviu mais).
    """
    return AnalyticsService.get_global_rankings(db)

@app.post("/users/me/analytics/generate-playlist")
def generate_retro_playlist(month: int, year: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Gera a playlist automática do mês e salva na conta do usuário.
    """
    pl = AnalyticsService.create_retro_playlist(db, current_user.id, month, year)
    if not pl:
        raise HTTPException(400, "Não há dados suficientes para gerar playlist.")
    return {"status": "created", "playlist_id": pl.id, "name": pl.name}


# --- GENRES (GÊNEROS MUSICAIS) ---
from app.services.genre_config import get_all_genres, get_genre_config, get_featured_genres

@app.get("/genres")
def list_all_genres():
    """
    Retorna a lista completa de gêneros disponíveis para explorar.
    Usado na seção 'Conheça mais' da busca.
    """
    return {"genres": get_all_genres()}

@app.get("/genres/stats")
def get_genre_statistics(db: Session = Depends(get_db)):
    """
    Retorna estatísticas dos gêneros das músicas baixadas.
    Útil para mostrar gêneros reais na biblioteca.
    """
    # Conta tracks por gênero
    genre_counts = db.query(
        models.Track.genre, 
        func.count(models.Track.id).label('count')
    ).filter(
        models.Track.genre.isnot(None), 
        models.Track.genre != '',
        models.Track.genre != 'Desconhecido'
    ).group_by(models.Track.genre).order_by(desc('count')).all()
    
    # Cores padrão para gêneros populares
    genre_colors = {
        'Pop': 0xFFE91E63,
        'Rock': 0xFFF44336,
        'Jazz': 0xFF9C27B0,
        'Hip-Hop': 0xFF673AB7,
        'R&B': 0xFF3F51B5,
        'R&B/Soul': 0xFF3F51B5,
        'Electronic': 0xFF00BCD4,
        'Dance': 0xFF00BCD4,
        'Classical': 0xFF795548,
        'Country': 0xFFFF9800,
        'Latin': 0xFFFFEB3B,
        'Reggae': 0xFF4CAF50,
        'Blues': 0xFF2196F3,
        'Metal': 0xFF424242,
        'Folk': 0xFF8BC34A,
        'Soul': 0xFF9C27B0,
        'Funk': 0xFFFF5722,
        'Punk': 0xFFE91E63,
        'Indie': 0xFF009688,
        'Alternative': 0xFF607D8B,
        'J-Pop': 0xFFFF4081,
        'K-Pop': 0xFFE040FB,
        'Anime': 0xFFFF6E40,
        'Soundtrack': 0xFF7C4DFF,
        'Video Game': 0xFF536DFE,
        'Bossa Nova': 0xFF26A69A,
        'MPB': 0xFF66BB6A,
        'Singer-Songwriter': 0xFFAB47BC,
    }
    
    genres = []
    for genre, count in genre_counts:
        config = get_genre_config(genre)
        color = genre_colors.get(genre, config.get("color", 0xFF9E9E9E) if config else 0xFF9E9E9E)
        genres.append({
            "name": genre,
            "count": count,
            "color": color,
            "search_query": config.get("search_query", genre) if config else genre,
        })
    
    return {"genres": genres, "total_tracks": sum(c for _, c in genre_counts)}

@app.get("/genres/featured")
def list_featured_genres(limit: int = 20):
    """
    Retorna os gêneros em destaque para a seção 'Conheça mais'.
    """
    return {"genres": get_featured_genres(limit)}

@app.get("/users/me/genres/favorites")
def get_user_favorite_genres(
    limit: int = 6, 
    days: int = 90, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    """
    Retorna os gêneros favoritos do usuário baseado no histórico de escuta.
    Os gêneros são ordenados pelo tempo total de escuta.
    """
    favorites = AnalyticsService.get_user_favorite_genres(db, current_user.id, limit, days)
    
    # Enriquece com cores e configs do genre_config se disponível
    enriched = []
    for fav in favorites:
        config = get_genre_config(fav["name"])
        enriched.append({
            "name": fav["name"],
            "total_minutes": fav["total_minutes"],
            "play_count": fav["play_count"],
            "color": config.get("color", 0xFF9E9E9E) if config else 0xFF9E9E9E,
            "search_query": config.get("search_query", fav["name"]) if config else fav["name"],
            "playlist_id": config.get("playlist_id") if config else None,
        })
    
    return {"favorites": enriched}

@app.get("/genres/{genre_name}/tracks")
async def get_genre_top_tracks(
    genre_name: str,
    limit: int = 100,
    force_refresh: bool = False,
    db: Session = Depends(get_db),
):
    """
    Retorna as top tracks de um gênero específico.
    Usa cache atualizado a cada 24h para resposta instantânea.
    Use force_refresh=true para forçar atualização do cache.
    """
    try:
        genre_lower = genre_name.lower().strip()
        
        # Tenta buscar do cache primeiro (se não forçar refresh)
        if not force_refresh:
            cached = get_cached_genre_tracks(db, genre_lower)
            if cached and cached.get("tracks"):
                tracks = cached["tracks"][:limit]  # Aplica limit
                print(f"📦 [CACHE] Retornando {len(tracks)} tracks de '{genre_name}' do cache")
                return {
                    "genre": genre_name,
                    "source": "cache",
                    "cached": True,
                    "updated_at": cached.get("updated_at"),
                    "tracks": tracks
                }
        
        # Se não tem cache ou force_refresh, busca da API e atualiza cache
        print(f"🔄 [LIVE] Buscando tracks de '{genre_name}' da API...")
        
        tracks = await fetch_genre_tracks_from_api(genre_name, limit)
        
        if tracks:
            # Atualiza cache em background
            await update_genre_cache_single(db, genre_name)
            
            print(f"✅ Encontradas {len(tracks)} tracks para o gênero '{genre_name}'")
            return {
                "genre": genre_name,
                "source": "ytmusic",
                "cached": False,
                "tracks": tracks[:limit]
            }
        
        print(f"⚠️ Nenhum resultado para o gênero '{genre_name}'")
        return {"genre": genre_name, "source": "ytmusic", "cached": False, "tracks": []}
                
    except Exception as e:
        print(f"❌ Erro ao buscar tracks do gênero {genre_name}: {e}")
        import traceback
        traceback.print_exc()
    
    return {"genre": genre_name, "source": "error", "cached": False, "tracks": []}

@app.post("/genres/refresh-cache")
async def refresh_genres_cache(
    genre: Optional[str] = None,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
):
    """
    Força atualização do cache de gêneros.
    Se 'genre' for especificado, atualiza apenas esse gênero.
    Caso contrário, atualiza todos os gêneros em background.
    """
    if genre:
        # Atualiza um gênero específico
        success = await update_genre_cache_single(db, genre)
        if success:
            return {"status": "success", "message": f"Cache de '{genre}' atualizado"}
        return {"status": "error", "message": f"Falha ao atualizar cache de '{genre}'"}
    
    # Atualiza todos em background
    background_tasks.add_task(update_all_genres_cache)
    return {
        "status": "started",
        "message": f"Atualização de {len(SUPPORTED_GENRES)} gêneros iniciada em background"
    }

@app.get("/genres/cache-status")
async def get_genres_cache_status(db: Session = Depends(get_db)):
    """
    Retorna o status do cache de gêneros.
    """
    cached_genres = db.query(models.GenreCache).all()
    
    status = []
    for cached in cached_genres:
        status.append({
            "genre": cached.genre_name,
            "track_count": cached.track_count,
            "updated_at": cached.updated_at.isoformat() if cached.updated_at else None,
        })
    
    return {
        "total_cached": len(cached_genres),
        "total_supported": len(SUPPORTED_GENRES),
        "memory_cache_size": len(_genre_cache_memory),
        "genres": status
    }


# Histórico
@app.post("/users/me/history")
def log_history(req: HistoryRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    track = db.query(models.Track).filter(models.Track.filename == req.filename).first()
    
    # Se track não existir, cria uma entrada básica
    if not track:
        try:
            fp = AudioManager.find_local_file(req.filename)
            meta = AudioManager.get_audio_metadata(fp)
            tags = AudioManager.get_audio_tags(fp)
            
            # Busca gênero: primeiro dos metadados, depois online
            genre = tags.get('genre')
            artist_name = tags.get('artist') or "Desconhecido"
            album_name = tags.get('album')
            title_name = tags.get('title') or os.path.splitext(req.filename)[0]
            
            if not genre or genre == "" or genre == "Desconhecido":
                genre = fetch_and_assign_genre(artist_name, album_name, title_name)
            
            track = models.Track(
                filename=req.filename,
                title=title_name,
                artist=artist_name,
                album=album_name,
                album_id=req.album_id,  # Salva o ID do álbum se fornecido
                genre=genre,
                duration=meta.get('duration', 0),
                format=meta.get('format'),
                bitrate=meta.get('bitrate')
            )
            db.add(track)
            db.commit()
            db.refresh(track)
        except Exception as e:
            print(f"⚠️ Erro ao criar track no histórico: {e}")
            return {"status": "error", "message": "Track não encontrada"}
    else:
        # Se track existe mas não tem album_id ou genre, atualiza
        updated = False
        if req.album_id and not track.album_id:
            track.album_id = req.album_id
            updated = True
        if not track.genre or track.genre == "" or track.genre == "Desconhecido":
            # Busca gênero se ainda não tem
            if req.genre and req.genre != "Desconhecido":
                track.genre = req.genre
                updated = True
            else:
                # Tenta buscar online
                genre = fetch_and_assign_genre(track.artist, track.album, track.title)
                if genre:
                    track.genre = genre
                    updated = True
        if updated:
            db.commit()
    
    if track:
        history = models.ListenHistory(user_id=current_user.id, track_id=track.id, duration_listened=req.duration_listened)
        db.add(history)
        db.commit()
    return {"status": "logged"}


# --- ATUALIZAÇÃO DA BIBLIOTECA (SYNC DB) ---
# Precisamos atualizar a função de biblioteca para ler do Banco de Dados
# e uma função background para popular o banco com os arquivos do disco.

async def sync_files_to_db(db: Session):
    print("🔄 Sincronizando arquivos do disco para o DB...")
    base_path = "/downloads"
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, base_path)
                
                # Verifica se já existe no banco
                exists = db.query(models.Track).filter(models.Track.filename == rel_path).first()
                if not exists:
                    try:
                        # Lê metadados
                        from app.services.audio_manager import AudioManager
                        tags = AudioManager.get_audio_tags(full_path)
                        meta = AudioManager.get_audio_metadata(full_path)
                        
                        # Se não tem gênero nos metadados, busca online
                        genre = tags.get('genre')
                        if not genre or genre == "" or genre == "Desconhecido":
                            artist = tags.get('artist') or "Desconhecido"
                            album = tags.get('album')
                            title = tags.get('title') or file
                            genre = fetch_and_assign_genre(artist, album, title)
                        
                        track = models.Track(
                            filename=rel_path,
                            title=tags.get('title') or file,
                            artist=tags.get('artist') or "Desconhecido",
                            album=tags.get('album'),
                            genre=genre,
                            duration=meta.get('duration', 0),
                            format=meta.get('format'),
                            bitrate=meta.get('bitrate')
                        )
                        db.add(track)
                    except Exception as e:
                        print(f"Erro ao indexar {file}: {e}")
    db.commit()
    print("✅ Sincronização concluída.")

@app.post("/library/scan")
async def scan_library_db(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """
    Força uma varredura no disco e atualiza o Banco de Dados.
    """
    background_tasks.add_task(sync_files_to_db, db)
    return {"status": "started", "message": "Indexação iniciada."}

# --- NOVA ROTA DE BIBLIOTECA (VIA DB) ---
@app.get("/library")
def get_library_db(db: Session = Depends(get_db)):
    """
    Retorna a biblioteca consultando o SQL (Muito mais rápido que os.walk).
    """
    tracks = db.query(models.Track).all()
    # Converte para o formato que o frontend espera
    return [
        {
            "filename": t.filename, # O frontend usa isso para stream
            "display_name": t.title,
            "artist": t.artist,
            "album": t.album,
            "genre": t.genre,  # Adicionado gênero
            "format": t.format,
            "duration": t.duration,
            "id": t.id # Novo: ID do banco para favoritos/playlists
        }
        for t in tracks
    ]


# --- Página de instalação ---

@app.get("/install", response_class=HTMLResponse)
async def install_page():
    """
    Página simples para listar e baixar os arquivos de atualização.
    Útil para debug e para o usuário baixar manualmente.
    """
    files = os.listdir("/downloads_public")
    files.sort()
    
    html_content = """
    <html>
        <head>
            <title>Instalar Orfeu</title>
            <style>
                body { font-family: sans-serif; background: #121212; color: white; padding: 20px; }
                h1 { color: #D4AF37; }
                a { display: block; padding: 10px; background: #222; margin: 5px 0; color: #D4AF37; text-decoration: none; border-radius: 5px; }
                a:hover { background: #333; }
            </style>
        </head>
        <body>
            <h1>Downloads Disponíveis</h1>
    """
    
    if not files:
        html_content += "<p>Nenhum arquivo encontrado no servidor.</p>"
    else:
        for f in files:
            html_content += f'<a href="/downloads/{f}">⬇️ {f}</a>'
            
    html_content += "</body></html>"
    return html_content


@app.get("/latest")
async def download_latest(request: Request):
    """
    Detecta o sistema operacional pelo User-Agent e redireciona para o download
    da última versão disponível para aquela plataforma.
    """
    user_agent = request.headers.get("user-agent", "").lower()
    
    # Detecta a plataforma pelo User-Agent
    if "android" in user_agent:
        platform = "android"
    elif "windows" in user_agent:
        platform = "windows"
    elif "macintosh" in user_agent or "mac os" in user_agent:
        platform = "macos"
    elif "linux" in user_agent:
        # Linux desktop - oferece a versão Windows (AppImage/tar.gz seria melhor, mas não temos)
        # Por enquanto redireciona para a página de instalação
        platform = "linux"
    elif "iphone" in user_agent or "ipad" in user_agent:
        platform = "ios"
    else:
        platform = "unknown"
    
    # Busca a URL do updates.json
    try:
        config = get_update_config()
        latest_version = config.get("latest_version", "0.0.0")
        platforms = config.get("platforms", {})
        
        if platform in platforms and "url" in platforms[platform]:
            download_url = platforms[platform]["url"]
            return RedirectResponse(url=download_url, status_code=302)
        
        # Se não tem URL específica para a plataforma, mostra página informativa
        html_content = f"""
        <html>
            <head>
                <title>Download Orfeu</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {{ 
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                        background: #121212; 
                        color: white; 
                        padding: 20px; 
                        text-align: center;
                        min-height: 100vh;
                        display: flex;
                        flex-direction: column;
                        justify-content: center;
                        align-items: center;
                    }}
                    h1 {{ color: #D4AF37; font-size: 2em; margin-bottom: 10px; }}
                    .version {{ color: #888; margin-bottom: 30px; }}
                    .message {{ 
                        background: #222; 
                        padding: 20px 30px; 
                        border-radius: 10px; 
                        margin: 20px 0;
                        max-width: 400px;
                    }}
                    a {{ 
                        display: inline-block;
                        padding: 15px 30px; 
                        background: #D4AF37; 
                        color: #121212; 
                        text-decoration: none; 
                        border-radius: 8px; 
                        font-weight: bold;
                        margin: 10px;
                    }}
                    a:hover {{ background: #E5C048; }}
                    .platforms {{ margin-top: 20px; }}
                    .platform-link {{ 
                        display: block; 
                        padding: 12px 20px; 
                        background: #333; 
                        color: #D4AF37; 
                        margin: 8px auto;
                        border-radius: 5px;
                        max-width: 300px;
                    }}
                </style>
            </head>
            <body>
                <h1>🎵 Orfeu</h1>
                <p class="version">Versão {latest_version}</p>
        """
        
        if platform == "ios":
            html_content += """
                <div class="message">
                    <p>📱 O Orfeu ainda não está disponível para iOS.</p>
                    <p>Por enquanto, está disponível para Android, Windows e macOS.</p>
                </div>
            """
        elif platform == "linux":
            html_content += """
                <div class="message">
                    <p>🐧 Versão Linux em breve!</p>
                    <p>Por enquanto, você pode usar o app no Windows, macOS ou Android.</p>
                </div>
            """
        else:
            html_content += """
                <div class="message">
                    <p>Não conseguimos detectar seu sistema operacional.</p>
                    <p>Escolha uma das opções abaixo:</p>
                </div>
            """
        
        html_content += '<div class="platforms">'
        for plat, data in platforms.items():
            icon = {"android": "📱", "windows": "🪟", "macos": "🍎"}.get(plat, "📦")
            name = {"android": "Android (APK)", "windows": "Windows", "macos": "macOS"}.get(plat, plat)
            html_content += f'<a href="{data["url"]}" class="platform-link">{icon} {name}</a>'
        html_content += '</div>'
        
        html_content += """
            </body>
        </html>
        """
        return HTMLResponse(content=html_content)
        
    except Exception as e:
        print(f"❌ Erro no /latest: {e}")
        # Fallback para a página de instalação
        return RedirectResponse(url="/install", status_code=302)

# --- UPDATE OTA ---
@app.get("/app/latest_version")
def latest_version_check():
    try:
        return get_update_config()
    except Exception as e:
        print(f"❌ Erro config update: {e}")
        raise HTTPException(500, detail="Erro de configuração.")

# --- PROXY IMAGEM DISCORD ---
@app.get("/cover/short/{hash_id}")
async def proxy_cover_art(hash_id: str):
    item = SHORT_URL_MAP.get(hash_id)
    if not item: raise HTTPException(404, "Cover hash inválido.")
    if time.time() > item["expires"]:
        del SHORT_URL_MAP[hash_id]
        raise HTTPException(404, "Cover hash expirado.")
    filename = item["filename"]
    return RedirectResponse(f"/cover?filename={quote(filename)}", status_code=302)

# --- BUSCA ---
@app.get("/search/catalog")
async def search_catalog(
    query: str, 
    limit: int = 20, 
    offset: int = 0, 
    type: str = Query("song", enum=["song", "album", "artist"]) 
):
    """
    Busca no catálogo de músicas.
    Prioridade: YouTube Music (mais resultados) com enriquecimento do Tidal.
    Remove duplicatas automaticamente.
    """
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}, Limit: {limit}, Offset: {offset}]")
    
    fetch_limit = limit + offset + 20  # Pega mais para compensar duplicatas removidas
    
    yt_results = []
    tidal_results = []
    
    # 1. YouTube Music PRIMEIRO (mais resultados, melhor cobertura)
    try:
        yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type, fetch_limit)
        print(f"   ✅ YTMusic retornou {len(yt_results)} resultados.")
    except Exception as e:
        print(f"   ❌ Erro no YTMusic: {e}")
    
    # 2. Tidal em PARALELO (para enriquecimento e fallback)
    try:
        tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, fetch_limit, type)
        print(f"   ✅ Tidal retornou {len(tidal_results)} resultados.")
    except Exception as e:
        print(f"   ❌ Erro no Tidal: {e}")
    
    # 3. Mescla resultados com deduplicação inteligente
    results = merge_and_deduplicate_results(yt_results, tidal_results, type)
    print(f"   🔀 Após merge/dedup: {len(results)} resultados únicos")
    
    # 4. Paginação
    total_items = len(results)
    final_page = []
    
    if total_items > offset:
        end = offset + limit
        final_page = results[offset:end]
    
    print(f"   📤 Retornando {len(final_page)} itens (Offset: {offset}, Total: {total_items})")

    # 5. Verifica downloads locais
    for item in final_page:
        if item.get('type') == 'song':
            tidal_id = item.get('tidalId')
            album = item.get('collectionName')
            
            local_file = find_local_match(
                artist=item.get('artistName', ''), 
                track=item.get('trackName', ''),
                album=album,
                tidal_id=tidal_id
            )
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file
            
            if local_file:
                try:
                    tags = AudioManager.get_audio_tags(local_file)
                    item['genre'] = tags.get('genre')
                except:
                    pass
        else:
            item['isDownloaded'] = False
            item['filename'] = None

    return final_page


def merge_and_deduplicate_results(yt_results: list, tidal_results: list, result_type: str) -> list:
    """
    Mescla resultados do YTMusic e Tidal, removendo duplicatas.
    Prioriza YTMusic mas enriquece com tidalId quando disponível.
    """
    seen = {}  # Chave normalizada -> item
    final_results = []
    
    def make_key(item: dict) -> str:
        """Cria chave única normalizada para detectar duplicatas."""
        if result_type == "artist":
            name = normalize_text(item.get('artistName', ''))
            # Remove sufixos comuns que criam duplicatas
            name = name.replace(' official', '').replace(' music', '').replace(' vevo', '')
            return f"artist:{name}"
        
        elif result_type == "album":
            artist = normalize_text(item.get('artistName', ''))
            album = normalize_text(item.get('collectionName', ''))
            # Remove anos e edições do nome do álbum para agrupar versões
            album = re.sub(r'\s*\(?(deluxe|remaster|edition|version|expanded|anniversary)\)?.*$', '', album, flags=re.IGNORECASE)
            return f"album:{artist}:{album}"
        
        else:  # song
            artist = normalize_text(item.get('artistName', ''))
            track = normalize_text(item.get('trackName', ''))
            # Remove indicadores de versão da música
            track = re.sub(r'\s*\(?(remix|remaster|live|acoustic|radio edit|explicit|clean)\)?.*$', '', track, flags=re.IGNORECASE)
            return f"song:{artist}:{track}"
    
    def enrich_with_tidal(yt_item: dict, tidal_item: dict) -> dict:
        """Enriquece item do YTMusic com dados do Tidal."""
        if tidal_item.get('tidalId'):
            yt_item['tidalId'] = tidal_item['tidalId']
        if result_type == "album" and tidal_item.get('collectionId'):
            yt_item['tidalCollectionId'] = tidal_item['collectionId']
        if result_type == "artist" and tidal_item.get('artistId'):
            yt_item['tidalArtistId'] = tidal_item['artistId']
        return yt_item
    
    # Indexa resultados do Tidal para lookup rápido
    tidal_index = {}
    for item in tidal_results:
        key = make_key(item)
        if key not in tidal_index:
            tidal_index[key] = item
    
    # Processa YTMusic primeiro (prioridade)
    for item in yt_results:
        key = make_key(item)
        if key not in seen:
            # Tenta enriquecer com Tidal
            if key in tidal_index:
                item = enrich_with_tidal(item, tidal_index[key])
            seen[key] = item
            final_results.append(item)
    
    # Adiciona itens do Tidal que não existem no YTMusic
    for item in tidal_results:
        key = make_key(item)
        if key not in seen:
            seen[key] = item
            final_results.append(item)
    
    return final_results

@app.get("/catalog/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Retorna detalhes completos do artista (Bio, Álbuns, Singles, Top Tracks).
    Suporta TIDAL (IDs numéricos) e YTMusic (IDs alfanuméricos/UC...).
    """
    try:
        # Lógica de roteamento baseada no formato do ID
        if artist_id.isdigit():
             # TIDAL
             print(f"🎤 Buscando artista no TIDAL: {artist_id}")
             return await run_in_threadpool(TidalProvider.get_artist_details, artist_id)
        else:
             # YTMUSIC (IDs geralmente começam com 'UC' ou 'U' ou hash longo)
             print(f"🎤 Buscando artista no YTMusic: {artist_id}")
             return await run_in_threadpool(CatalogProvider.get_artist_details, artist_id)

    except Exception as e:
        print(f"❌ Erro detalhes artista: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    """
    Busca detalhes do álbum. Tenta Tidal primeiro, depois YTMusic.
    Agora enriquece com GÊNERO via iTunes.
    """
    try:
        # Identifica provider pelo formato do ID
        if collection_id.isdigit():
             # TIDAL
             return await run_in_threadpool(TidalProvider.get_album_details, collection_id)
        else:
             # YTMUSIC
             details = await run_in_threadpool(CatalogProvider.get_album_details, collection_id)
             # Enriquece YTMusic com gênero
             if details and not details.get('genre'):
                  genre = await run_in_threadpool(MetadataProvider.get_genre, details['artistName'], details['collectionName'])
                  details['genre'] = genre
             return details

    except Exception as e:
        print(f"❌ Erro rota album: {e}")
        raise HTTPException(status_code=404, detail="Album not found")

class UpdateAlbumGenreRequest(BaseModel):
    album_id: str
    genre: str

@app.post("/catalog/album/update-genre")
def update_album_tracks_genre(req: UpdateAlbumGenreRequest, db: Session = Depends(get_db)):
    """
    Atualiza o gênero de todas as tracks que pertencem a um álbum específico.
    Chamado quando o app abre um álbum e descobre o gênero.
    """
    if not req.genre or req.genre == "Desconhecido":
        return {"status": "skipped", "message": "Gênero inválido"}
    
    # Atualiza tracks pelo album_id
    updated = db.query(models.Track).filter(
        models.Track.album_id == req.album_id,
        (models.Track.genre == None) | (models.Track.genre == "") | (models.Track.genre == "Desconhecido")
    ).update({"genre": req.genre}, synchronize_session=False)
    
    db.commit()
    print(f"🎸 Atualizado gênero '{req.genre}' em {updated} tracks do álbum {req.album_id}")
    
    return {"status": "updated", "tracks_updated": updated, "genre": req.genre}

# --- SMART DOWNLOAD (CORE LOGIC) ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    print(f"🤖 Smart Download: {request.artist} - {request.track}")
    
    # Primeiro verifica pelo tidal_id (mais preciso) se disponível
    local_match = find_local_match(
        artist=request.artist, 
        track=request.track,
        album=request.album,
        tidal_id=request.tidalId
    )
    if local_match:
        print(f"✅ Cache Local: {local_match}")
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    # 1. Tidal Direct
    target_tidal_id = request.tidalId
    
    # Se veio sem ID (YTMusic ou outra fonte), tenta achar no Tidal agora
    if not target_tidal_id:
        print(f"🔍 Sem Tidal ID, buscando no Tidal: '{request.artist} {request.track}'")
        try:
            search_query = f"{request.artist} {request.track}"
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, search_query, 5, "song")
            
            if tidal_results:
                print(f"   📋 Tidal retornou {len(tidal_results)} resultados")
                
                # Encontra o melhor match
                target_clean = normalize_text(f"{request.artist} {request.track}")
                best_match = None
                best_score = 0
                
                for result in tidal_results:
                    result_clean = normalize_text(f"{result['artistName']} {result['trackName']}")
                    score = fuzz.token_set_ratio(target_clean, result_clean)
                    print(f"      -> '{result['artistName']} - {result['trackName']}' = {score}%")
                    
                    if score > best_score:
                        best_score = score
                        best_match = result
                
                # Threshold de 75% para aceitar o match
                if best_match and best_score >= 75:
                    target_tidal_id = best_match.get('tidalId')
                    if not request.artworkUrl:
                        request.artworkUrl = best_match.get('artworkUrl')
                    if not request.album:
                        request.album = best_match.get('collectionName')
                    print(f"   ✅ Tidal ID recuperado: {target_tidal_id} (score: {best_score}%)")
                else:
                    print(f"   ⚠️ Nenhum match bom o suficiente (melhor: {best_score}%)")
            else:
                print(f"   ⚠️ Tidal não retornou resultados")
                
        except Exception as e:
            print(f"   ❌ Erro buscando no Tidal: {e}")

    if target_tidal_id:
        print(f"🌊 Tentando download Tidal (ID: {target_tidal_id})...")
        download_info = await run_in_threadpool(TidalProvider.get_download_url, target_tidal_id)
        if download_info and download_info.get('url'):
            safe_artist = normalize_text(request.artist).replace(" ", "_")
            safe_track = normalize_text(request.track).replace(" ", "_")
            safe_album = normalize_text(request.album or "single").replace(" ", "_")
            ext = "flac" if "flac" in download_info['mime'] else "m4a"
            
            # CORREÇÃO: Filename único incluindo álbum para evitar conflitos
            # Formato: Tidal/artista/album/track.flac OU Tidal/artista/track_tidalId.flac
            if request.album:
                relative_path = os.path.join("Tidal", safe_artist, safe_album, f"{safe_track}.{ext}")
            else:
                # Sem álbum, usa tidal_id para garantir unicidade
                relative_path = os.path.join("Tidal", safe_artist, f"{safe_track}_{target_tidal_id}.{ext}")
            
            full_path = os.path.join("/downloads", relative_path)
            
            meta = {"title": request.track, "artist": request.artist, "album": request.album or "Single"}
            
            # Registra o download ANTES de iniciar (para evitar downloads duplicados)
            register_download(
                tidal_id=target_tidal_id,
                title=request.track,
                artist=request.artist,
                album=request.album,
                local_path=relative_path,
                source="Tidal"
            )
            
            background_tasks.add_task(download_file_background, download_info['url'], full_path, meta, request.artworkUrl)
            return {"status": "Download started", "file": relative_path, "source": "Tidal", "tidalId": target_tidal_id}

    # 2. Soulseek
    search_term = unidecode(f"{request.artist} {request.track}")
    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    print("⏳ Buscando no Soulseek...")
    best_candidate = None
    highest_score = float('-inf')
    target_clean = normalize_text(f"{request.artist} {request.track}")
    
    last_peer_count = -1
    stable_checks = 0

    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        peer_count = len(raw_results)
        
        if peer_count > 0 and peer_count == last_peer_count: stable_checks += 1
        else: stable_checks = 0
        last_peer_count = peer_count

        if i % 3 == 0: print(f"   Check {i+1}/22: {peer_count} peers.")

        # Saída Antecipada
        if best_candidate and best_candidate['score'] > 50000:
             if peer_count > 15: break # Perfect match (Free Slot)

        if stable_checks >= 4 and peer_count > 0 and best_candidate:
             break # Estabilizou

        for response in raw_results:
            if response.get('locked', False): continue
            slots = response.get('slotsFree', False)
            queue = response.get('queueLength', 0)
            speed = response.get('uploadSpeed', 0)

            if 'files' in response:
                for file in response['files']:
                    fname = file['filename']
                    fclean = normalize_text(os.path.basename(fname.replace("\\", "/")))
                    sim = fuzz.partial_token_sort_ratio(target_clean, fclean)
                    if sim < 75: continue
                    if '.' not in fname: continue
                    ext = fname.split('.')[-1].lower()
                    if ext not in ['flac', 'mp3', 'm4a']: continue

                    score = 0
                    if slots: score += 100_000 
                    else: score -= (queue * 1000)
                    if ext == 'flac': score += 5000
                    elif ext == 'm4a': score += 2000
                    elif ext == 'mp3': score += 1000
                    score += (speed / 1_000_000)

                    if request.album:
                         if fuzz.partial_ratio(normalize_text(request.album), normalize_text(fname)) > 85:
                             score += 5000

                    if score > highest_score:
                        highest_score = score
                        best_candidate = {'username': response.get('username'), 'filename': fname, 'size': file['size'], 'score': score}
    
    if not best_candidate: raise HTTPException(404, "Nenhum ficheiro encontrado.")
    
    try:
        if AudioManager.find_local_file(best_candidate['filename']):
             return {"status": "Already downloaded", "file": best_candidate['filename']}
    except: pass

    return await download_slskd(best_candidate['username'], best_candidate['filename'], best_candidate['size'])

# --- Demais Rotas ---
@app.post("/search/{query}")
async def start_search_legacy(query: str): return await search_slskd(query)

@app.get("/results/{search_id}")
async def view_results(search_id: str): return await get_search_results(search_id) 

@app.post("/download")
async def queue_download(request: DownloadRequest):
    try:
        path = AudioManager.find_local_file(request.filename)
        if os.path.getsize(path) > 0: return {"status": "Already downloaded", "file": request.filename}
        else: os.remove(path)
    except HTTPException: pass
    return await download_slskd(request.username, request.filename, request.size)

@app.get("/download/status")
async def check_download_status(filename: str):
    try:
        path = AudioManager.find_local_file(filename)
        size = os.path.getsize(path)
        if "Tidal" in path and size > 1000000:
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Tidal Download"}
        if size > 0 and "Tidal" not in path: 
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
    except HTTPException: pass
    status = await get_transfer_status(filename)
    if status: return status
    return {"state": "Unknown", "progress": 0.0, "message": "Iniciando"}

@app.post("/download/auto")
async def auto_download_best(request: AutoDownloadRequest):
    return await smart_download(SmartDownloadRequest(artist="", track="")) 

@app.get("/metadata")
async def get_track_details(filename: str):
    full_path = AudioManager.find_local_file(filename)
    meta = AudioManager.get_audio_metadata(full_path)
    meta['coverProxyUrl'] = get_short_cover_url(filename) # PROXY PÚBLICO
    return meta

@app.get("/lyrics")
async def get_lyrics(filename: str):
    full_path = AudioManager.find_local_file(filename)
    lyrics = await LyricsProvider.get_lyrics(full_path)
    if not lyrics: raise HTTPException(404, "Letra não encontrada")
    return lyrics

@app.get("/cover")
async def get_cover_art(filename: str):
    full_path = AudioManager.find_local_file(filename)
    try:
        if AudioManager.extract_cover_stream(full_path): 
             return StreamingResponse(AudioManager.extract_cover_stream(full_path), media_type="image/jpeg")
    except: pass
    url = await LyricsProvider.get_online_cover(full_path)
    if url: return RedirectResponse(url)
    raise HTTPException(404, "Capa não encontrada")


# --- LETRAS SINCRONIZADAS ---
from app.services.synced_lyrics_provider import (
    synced_lyrics_provider, 
    SyncedLyrics,
    get_available_providers,
    get_musixmatch_token_status,
    reset_musixmatch_token,
    test_musixmatch_connection,
)

@app.get("/lyrics/synced")
async def get_synced_lyrics(
    track: str,
    artist: str,
    album: Optional[str] = None,
    duration: Optional[int] = None,
    isrc: Optional[str] = None,
    apple_music_id: Optional[str] = None,
):
    """
    Busca letras sincronizadas para uma música.
    
    Retorna letras com timing por sílaba (Apple Music) ou por linha (LRCLIB).
    """
    lyrics = await synced_lyrics_provider.get_synced_lyrics(
        track_name=track,
        artist_name=artist,
        album_name=album,
        duration=duration,
        isrc=isrc,
        apple_music_id=apple_music_id,
    )
    
    if not lyrics:
        raise HTTPException(404, "Letras não encontradas")
    
    # Converte para dict serializável
    return {
        "source": lyrics.source,
        "syncType": lyrics.sync_type,
        "plainText": lyrics.plain_text,
        "language": lyrics.language,
        "lines": [
            {
                "text": line.text,
                "startTime": line.start_time,
                "endTime": line.end_time,
                "segments": [
                    {
                        "text": seg.text,
                        "startTime": seg.start_time,
                        "endTime": seg.end_time,
                    }
                    for seg in line.segments
                ]
            }
            for line in lyrics.lines
        ]
    }


@app.get("/lyrics/providers")
async def list_lyrics_providers():
    """Lista os providers de letras disponíveis e seus status."""
    return {
        "providers": get_available_providers(),
        "musixmatch": get_musixmatch_token_status(),
    }


@app.get("/lyrics/providers/test")
async def test_lyrics_providers():
    """Testa se os providers de letras estão funcionando."""
    musixmatch_status = await test_musixmatch_connection()
    
    return {
        "musixmatch": musixmatch_status,
        "token_status": get_musixmatch_token_status(),
    }


@app.post("/lyrics/providers/musixmatch/reset")
async def reset_musixmatch():
    """
    Reseta o token do Musixmatch.
    
    Use quando o Musixmatch estiver retornando erro 401.
    """
    was_reset = reset_musixmatch_token()
    
    return {
        "reset": was_reset,
        "message": "Token removido. Próxima busca vai gerar um novo." if was_reset else "Token não existia.",
        "token_status": get_musixmatch_token_status(),
    }


@app.get("/lyrics/plain")
async def get_plain_lyrics(filename: str):
    """Busca letras (pode ser sincronizadas ou não) para um arquivo local."""
    full_path = AudioManager.find_local_file(filename)
    lyrics = await LyricsProvider.get_lyrics(full_path)
    
    if not lyrics:
        raise HTTPException(404, "Letras não encontradas")
    
    return lyrics


@app.get("/stream")
async def stream_music(request: Request, filename: str, quality: str = Query("lossless")):
    full_path = AudioManager.find_local_file(filename)
    if quality != "lossless":
        return StreamingResponse(AudioManager.transcode_stream(full_path, quality), media_type="audio/mpeg")
    
    file_size = os.path.getsize(full_path)
    range_header = request.headers.get("range")
    if range_header:
        byte_range = range_header.replace("bytes=", "").split("-")
        start = int(byte_range[0])
        end = int(byte_range[1]) if byte_range[1] else file_size - 1
        if start >= file_size: return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
        chunk_size = (end - start) + 1
        with open(full_path, "rb") as f:
            f.seek(start)
            data = f.read(chunk_size)
        headers = {"Content-Range": f"bytes {start}-{end}/{file_size}", "Accept-Ranges": "bytes", "Content-Length": str(chunk_size), "Content-Type": "audio/flac"}
        return Response(data, status_code=206, headers=headers)

    headers = {"Content-Length": str(file_size), "Accept-Ranges": "bytes", "Content-Type": "audio/flac"}
    def iterfile():
        with open(full_path, "rb") as f: yield from f
    return StreamingResponse(iterfile(), headers=headers)

@app.post("/library/organize")
async def organize_library(background_tasks: BackgroundTasks):
    background_tasks.add_task(process_library_auto_tagging)
    return {"status": "started", "message": "O processo de organização iniciou em segundo plano."}

async def process_library_auto_tagging():
    base_path = "/downloads"
    count = 0
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                try:
                    current_tags = AudioManager.get_audio_tags(full_path)
                    if not current_tags.get('artist') or not current_tags.get('title') or current_tags.get('artist') == 'Desconhecido':
                        clean_name = normalize_text(os.path.splitext(file)[0].replace("_", " "))
                        results = await run_in_threadpool(TidalProvider.search_catalog, clean_name, 1)
                        if not results: results = await run_in_threadpool(CatalogProvider.search_catalog, clean_name, "song", 1)
                        
                        if results:
                            best_match = results[0]
                            match_str = normalize_text(f"{best_match['artistName']} {best_match['trackName']}")
                            similarity = fuzz.token_set_ratio(clean_name, match_str)
                            if similarity > 80:
                                cover_bytes = None
                                if best_match.get('artworkUrl'):
                                    try:
                                        async with httpx.AsyncClient() as client:
                                            resp = await client.get(best_match['artworkUrl'])
                                            if resp.status_code == 200: cover_bytes = resp.content
                                    except: pass
                                meta = {"title": best_match['trackName'], "artist": best_match['artistName'], "album": best_match['collectionName']}
                                await run_in_threadpool(AudioManager.embed_metadata, full_path, meta, cover_bytes)
                                count += 1
                except: pass
    print(f"✨ Auto-Tagging concluído. {count} arquivos atualizados.")

@app.get("/library/legacy")
async def get_library_legacy():
    """
    Rota legada - varre o disco diretamente (mais lento).
    Use /library para a versão via banco de dados.
    """
    base_path = "/downloads"
    library = []
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                try:
                    tags = AudioManager.get_audio_tags(full_path)
                    title = tags.get('title') or os.path.splitext(file)[0]
                    artist = tags.get('artist') or "Desconhecido"
                    album = tags.get('album')
                    genre = tags.get('genre')
                    if artist == "Desconhecido":
                        parts = full_path.replace("\\", "/").split("/")
                        if len(parts) >= 3: artist = parts[-3]
                    library.append({
                        "filename": file, 
                        "display_name": title,
                        "artist": artist,
                        "album": album,
                        "genre": genre,
                        "format": file.split('.')[-1].lower(),
                        "coverProxyUrl": get_short_cover_url(file) 
                    })
                except: pass

    return library
