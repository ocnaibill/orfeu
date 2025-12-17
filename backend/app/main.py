from fastapi import FastAPI, HTTPException, Query, Request, Response, BackgroundTasks, Depends, status
from fastapi.responses import StreamingResponse, RedirectResponse, HTMLResponse
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

# Importação dos Serviços
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider
from app.services.analytics_service import AnalyticsService
from app.services.release_date_provider import ReleaseDateProvider
from app.services.recommendation_service import MusicRecommender




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
    2. artist + track + album (fallback com contexto de álbum)
    3. artist + track apenas (último recurso, mais fuzzy)
    """
    # 1. Primeiro tenta pelo tidal_id (mais confiável)
    if tidal_id:
        result = find_local_match_by_tidal_id(tidal_id)
        if result:
            return result
    
    # 2. Busca no banco downloaded_tracks por metadados exatos
    db = get_db_session()
    try:
        query = db.query(models.DownloadedTrack).filter(
            models.DownloadedTrack.artist.ilike(f"%{artist}%"),
            models.DownloadedTrack.title.ilike(f"%{track}%")
        )
        
        # Se temos álbum, filtra também por ele (mais preciso)
        if album:
            query = query.filter(models.DownloadedTrack.album.ilike(f"%{album}%"))
        
        downloaded = query.first()
        if downloaded and downloaded.local_path:
            full_path = os.path.join("/downloads", downloaded.local_path)
            if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
                return full_path
    except Exception as e:
        print(f"⚠️ Erro ao buscar downloaded_tracks: {e}")
    finally:
        db.close()
    
    # 3. Fallback: busca por arquivo no disco (legado, para arquivos antigos)
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    
    # Se temos álbum, inclui na busca para maior precisão
    if album:
        target_str = normalize_text(f"{artist} {album} {track}")
    
    best_match = None
    best_score = 0
    
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                if os.path.getsize(full_path) == 0: 
                    continue
                
                # Compara com "PastaPai NomeArquivo" para contexto
                parent_folder = os.path.basename(root)
                grandparent_folder = os.path.basename(os.path.dirname(root))
                
                # Constrói string candidata com contexto de pastas
                candidate_str = normalize_text(f"{grandparent_folder} {parent_folder} {file}")
                
                # Se só tiver arquivo solto, compara só o nome
                if parent_folder == "downloads": 
                    candidate_str = normalize_text(file)
                
                # Se temos álbum e ele está no path, dá mais peso
                score = fuzz.partial_token_sort_ratio(target_str, candidate_str)
                
                if album and normalize_text(album) in candidate_str.lower():
                    score += 10  # Bonus por match de álbum
                
                if score > best_score and score > 85:
                    best_score = score
                    best_match = full_path
    
    return best_match

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

# --- Rotas ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "2.2.0"}


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
    profile_image_url: Optional[str] = None  # base64 ou URL externa

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
    
    db.commit()
    db.refresh(current_user)
    
    return {"status": "updated", "username": current_user.username}

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
        
        track = models.Track(filename=req.filename, title=req.title, artist=req.artist, album=req.album, duration=duration)
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
        "isFavorite": True
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
    albums = db.query(models.SavedAlbum).filter(models.SavedAlbum.user_id == current_user.id).order_by(models.SavedAlbum.saved_at.desc()).all()
    return [{
        "id": a.album_id,
        "title": a.title,
        "artist": a.artist,
        "artworkUrl": a.artwork_url,
        "year": a.year,
        "isPinned": a.is_pinned,
        "savedAt": a.saved_at.isoformat() if a.saved_at else None
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
    artists = db.query(models.SavedArtist).filter(models.SavedArtist.user_id == current_user.id).order_by(models.SavedArtist.saved_at.desc()).all()
    return [{
        "id": a.artist_id,
        "name": a.name,
        "imageUrl": a.image_url,
        "isPinned": a.is_pinned,
        "savedAt": a.saved_at.isoformat() if a.saved_at else None
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
        
        track = models.Track(
            filename=item.filename, 
            title=item.title or "Desconhecido", 
            artist=item.artist or "Desconhecido", 
            album=item.album, 
            duration=duration
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
        "tracks": tracks_data
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
    Recomendações personalizadas baseadas em:
    1. Gêneros mais ouvidos do usuário
    2. Artistas similares aos favoritos
    3. Descobertas baseadas em padrões de audição
    """
    try:
        # 1. Busca gêneros mais ouvidos do usuário
        top_genres = db.query(models.Track.genre, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(
                models.ListenHistory.user_id == current_user.id,
                models.Track.genre.isnot(None),
                models.Track.genre != "",
                models.Track.genre != "Desconhecido"
            )\
            .group_by(models.Track.genre)\
            .order_by(desc('count'))\
            .limit(3)\
            .all()
        
        # 2. Busca artistas mais ouvidos (para evitar recomendar os mesmos)
        top_artists = db.query(models.Track.artist)\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == current_user.id)\
            .group_by(models.Track.artist)\
            .order_by(desc(func.count(models.ListenHistory.id)))\
            .limit(10)\
            .all()
        top_artists_names = {a[0].lower() for a in top_artists if a[0]}
        
        recommendations = []
        seen_ids = set()
        
        # 3. Para cada gênero, busca álbuns relacionados
        genre_names = [g[0] for g in top_genres] if top_genres else ["Pop", "Rock", "Hip-Hop"]
        
        for genre in genre_names:
            try:
                # Busca por gênero no Tidal
                search_query = f"{genre} new music 2024"
                results = await run_in_threadpool(TidalProvider.search_catalog, search_query, limit * 2, "album")
                
                for item in results:
                    item_id = item.get('collectionId')
                    artist_name = item.get('artistName', '').lower()
                    
                    # Evita duplicatas e artistas já conhecidos
                    if item_id in seen_ids:
                        continue
                    if artist_name in top_artists_names:
                        continue
                    
                    seen_ids.add(item_id)
                    recommendations.append({
                        "title": item['collectionName'],
                        "artist": item['artistName'],
                        "imageUrl": item['artworkUrl'],
                        "type": "album",
                        "id": item_id,
                        "reason": f"Baseado no seu gosto por {genre}"
                    })
                    
                    if len(recommendations) >= limit:
                        break
                        
            except Exception as genre_e:
                print(f"⚠️ Erro buscando gênero {genre}: {genre_e}")
                continue
            
            if len(recommendations) >= limit:
                break
        
        # 4. Fallback: Se não tiver recomendações suficientes, busca trending
        if len(recommendations) < limit:
            try:
                trending = await run_in_threadpool(TidalProvider.search_catalog, "trending albums 2024", limit, "album")
                for item in trending:
                    item_id = item.get('collectionId')
                    if item_id not in seen_ids:
                        seen_ids.add(item_id)
                        recommendations.append({
                            "title": item['collectionName'],
                            "artist": item['artistName'],
                            "imageUrl": item['artworkUrl'],
                            "type": "album",
                            "id": item_id,
                            "reason": "Em alta"
                        })
                    if len(recommendations) >= limit:
                        break
            except:
                pass
        
        # 5. Embaralha levemente para variedade
        import random
        if len(recommendations) > 3:
            random.shuffle(recommendations)
        
        return recommendations[:limit]
        
    except Exception as e:
        print(f"❌ Erro em recommendations: {e}")
        # Fallback de emergência
        try:
            results = await run_in_threadpool(TidalProvider.search_catalog, "Top Hits", limit, "album")
            return [{
                "title": item['collectionName'],
                "artist": item['artistName'],
                "imageUrl": item['artworkUrl'],
                "type": "album",
                "id": item['collectionId']
            } for item in results]
        except:
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
def get_my_analytics(days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_user_stats(db, current_user.id, days)

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
            
            track = models.Track(
                filename=req.filename,
                title=tags.get('title') or os.path.splitext(req.filename)[0],
                artist=tags.get('artist') or "Desconhecido",
                album=tags.get('album'),
                genre=tags.get('genre'),
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
                        
                        track = models.Track(
                            filename=rel_path,
                            title=tags.get('title') or file,
                            artist=tags.get('artist') or "Desconhecido",
                            album=tags.get('album'),
                            genre=tags.get('genre'),  # Adicionado gênero
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
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}, Limit: {limit}, Offset: {offset}]")
    results = []
    
    # Precisamos pedir (limit + offset) aos providers porque eles não suportam paginação real (stateful)
    # e podem sempre retornar do início. Assim garantimos que temos itens suficientes para o slice final.
    fetch_limit = limit + offset

    # 1. Tenta TIDAL primeiro
    try:
        tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, fetch_limit, type)
        if tidal_results: 
            print(f"   ✅ Tidal retornou {len(tidal_results)} resultados.")
            results = tidal_results
        else:
            print("   ⚠️ Tidal retornou lista vazia.")
    except Exception as e: 
        print(f"   ❌ Erro no Tidal: {e}")

    # 2. Fallback para YTMusic/CatalogProvider se Tidal falhar
    if not results:
        print("   -> Fallback para CatalogProvider (YTMusic)...")
        try:
            yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type)
            if yt_results:
                print(f"   ✅ YTMusic retornou {len(yt_results)} resultados.")
                results = yt_results
            else:
                print("   ⚠️ YTMusic retornou lista vazia.")
        except Exception as e:
            print(f"   ❌ Erro no YTMusic: {e}")

    # 3. Paginação Manual Robusta
    # Garante que o slice respeite os limites da lista retornada
    total_items = len(results)
    final_page = []
    
    if total_items > offset:
        end = offset + limit
        final_page = results[offset : end]
    
    print(f"   📤 Retornando {len(final_page)} itens (Offset: {offset}, Total Bruto: {total_items})")

    # 4. Verifica downloads locais usando tidal_id para precisão
    for item in final_page:
        if item.get('type') == 'song':
            tidal_id = item.get('tidalId')
            album = item.get('collectionName')
            
            # Busca precisa usando tidal_id + metadados
            local_file = find_local_match(
                artist=item.get('artistName', ''), 
                track=item.get('trackName', ''),
                album=album,
                tidal_id=tidal_id
            )
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file
            
            # Se arquivo existe localmente, extrai gênero dos metadados
            if local_file:
                try:
                    tags = AudioManager.get_audio_tags(local_file)
                    item['genre'] = tags.get('genre')
                except:
                    pass
        else:
            # Artistas e álbuns não têm arquivo único associado dessa forma
            item['isDownloaded'] = False
            item['filename'] = None

    return final_page

@app.get("/catalog/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Busca detalhes do artista por ID (não por nome).
    Retorna discografia filtrada pelo ID real do artista.
    """
    try:
        print(f"🎤 Buscando artista ID: {artist_id}")
        artist_data = await run_in_threadpool(TidalProvider.get_artist_details, artist_id)
        
        # Adiciona status de download para top tracks
        for track in artist_data.get('topTracks', []):
            tidal_id = track.get('tidalId')
            local_file = find_local_match(
                artist=track.get('artistName', ''),
                track=track.get('trackName', ''),
                album=track.get('collectionName'),
                tidal_id=tidal_id
            )
            track['isDownloaded'] = local_file is not None
            track['filename'] = local_file
        
        return artist_data
    except Exception as e:
        print(f"❌ Erro artista: {e}")
        raise HTTPException(500, str(e))

@app.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    try:
        # Detecta se é ID do Tidal (numérico) ou do YTMusic (começa com MPRE ou letras)
        is_tidal_id = collection_id.isdigit()
        
        if is_tidal_id:
            # Busca detalhes do álbum no Tidal
            album_data = await run_in_threadpool(TidalProvider.get_album_details, collection_id)
        else:
            # Busca detalhes do álbum no YTMusic (CatalogProvider)
            album_data = await run_in_threadpool(CatalogProvider.get_album_details, collection_id)
        
        if not album_data:
            raise HTTPException(404, "Álbum não encontrado")
            
        album_name = album_data.get('collectionName')
        
        for track in album_data.get('tracks', []):
            tidal_id = track.get('tidalId')
            # Usa busca precisa com tidal_id e álbum
            local_file = find_local_match(
                artist=track.get('artistName', ''), 
                track=track.get('trackName', ''),
                album=album_name,
                tidal_id=tidal_id
            )
            track['isDownloaded'] = local_file is not None
            track['filename'] = local_file
        return album_data
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Erro álbum: {e}")
        raise HTTPException(500, str(e))

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
    
    # Se veio sem ID (YTMusic), tenta achar no Tidal agora
    if not target_tidal_id:
        try:
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, f"{request.artist} {request.track}", 1, "song")
            if tidal_results:
                 best = tidal_results[0]
                 if fuzz.token_set_ratio(normalize_text(f"{request.artist} {request.track}"), normalize_text(f"{best['artistName']} {best['trackName']}")) > 85:
                     target_tidal_id = best['tidalId']
                     if not request.artworkUrl: request.artworkUrl = best['artworkUrl']
                     print(f"✅ Tidal ID recuperado: {target_tidal_id}")
        except: pass

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
                        if not results: results = await run_in_threadpool(CatalogProvider.search_catalog, clean_name, 1)
                        
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
