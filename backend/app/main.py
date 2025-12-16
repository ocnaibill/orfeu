from fastapi import FastAPI, HTTPException, Query, Request, Response, BackgroundTasks, Depends, status
from fastapi.responses import StreamingResponse, RedirectResponse, HTMLResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
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



# Importação de Banco de Dados e Auth
from .database import engine, get_db, Base
from . import models, auth_utils


# Cria tabelas se não existirem
models.Base.metadata.create_all(bind=engine)


app = FastAPI(title="Orfeu API", version="2.2.0")

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

def find_local_match(artist: str, track: str) -> Optional[str]:
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                if os.path.getsize(full_path) == 0: continue
                
                # Compara com "PastaPai NomeArquivo" para contexto
                parent_folder = os.path.basename(root)
                candidate_str = normalize_text(f"{parent_folder} {file}")
                
                # Se só tiver arquivo solto, compara só o nome
                if parent_folder == "downloads": candidate_str = normalize_text(file)

                if fuzz.partial_token_sort_ratio(target_str, candidate_str) > 90: 
                    return full_path
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
def read_users_me(current_user: models.User = Depends(get_current_user)):
    return {
        "username": current_user.username, 
        "full_name": current_user.full_name,
        "email": current_user.email
    }

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
        "format": t.filename.split('.')[-1] if t.filename else "",
        "coverProxyUrl": get_short_cover_url(t.filename) if t.filename else None,
        "isFavorite": True
    } for t in favorites]

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


# --- ROTAS DA HOME (FEED & ANALYTICS) - RESTAURADAS ---
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

@app.get("/home/recommendations")
async def get_recommendations(limit: int = 10):
    try:
        results = await run_in_threadpool(TidalProvider.search_catalog, "Top Hits", limit, "album")
        recommendations = []
        for item in results:
            recommendations.append({
                "title": item['collectionName'],
                "artist": item['artistName'],
                "imageUrl": item['artworkUrl'],
                "type": "album",
                "id": item['collectionId']
            })
        return recommendations
    except: return []

@app.get("/home/new-releases")
async def get_new_releases(limit: int = 10):
    try:
        results = await run_in_threadpool(TidalProvider.search_catalog, "New Music", limit, "album")
        news = []
        for item in results:
            news.append({
                "title": item['collectionName'],
                "artist": item['artistName'],
                "imageUrl": item['artworkUrl'],
                "type": "album",
                "id": item['collectionId'],
                "vibrantColorHex": "#4A00E0" 
            })
        return news
    except: return []

# --- ANALYTICS (PERFIL) ---
@app.get("/users/me/analytics/summary")
def get_my_analytics(days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_user_stats(db, current_user.id, days)

@app.get("/users/me/analytics/top-tracks")
def get_my_top_tracks(limit: int = 10, days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_top_tracks(db, current_user.id, limit, days)


# --- ANALYTICS ---

@app.get("/users/me/analytics/summary")
def get_my_analytics(days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Retorna resumo: Total minutos, Top Artista, Total Plays.
    Padrão: Últimos 30 dias.
    """
    return AnalyticsService.get_user_stats(db, current_user.id, days)

@app.get("/users/me/analytics/top-tracks")
def get_my_top_tracks(limit: int = 10, days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Retorna as músicas mais ouvidas.
    """
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
            "format": t.format,
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
    query: str, limit: int = 20, offset: int = 0, type: str = Query("song", enum=["song", "album"])
):
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}]")
    results = []
    if type == "song":
        try:
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, limit, type)
            if tidal_results: results = tidal_results
        except Exception as e: print(f"⚠️ Tidal falhou: {e}")

    if not results:
        yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type)
        results = yt_results

    final_page = results
    if len(results) > limit:
         start = offset
         end = offset + limit
         if start < len(results): final_page = results[start:end]
         else: final_page = []

    for item in final_page:
        if item.get('type') == 'song':
            local_file = find_local_match(item['artistName'], item['trackName'])
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file
        else:
            item['isDownloaded'] = False
            item['filename'] = None

    return final_page

@app.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    try:
        album_data = await run_in_threadpool(CatalogProvider.get_album_details, collection_id)
        for track in album_data['tracks']:
            local_file = find_local_match(track['artistName'], track['trackName'])
            track['isDownloaded'] = local_file is not None
            track['filename'] = local_file
        return album_data
    except Exception as e:
        print(f"❌ Erro álbum: {e}")
        raise HTTPException(500, str(e))

# --- SMART DOWNLOAD (CORE LOGIC) ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    print(f"🤖 Smart Download: {request.artist} - {request.track}")
    
    local_match = find_local_match(request.artist, request.track)
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
            ext = "flac" if "flac" in download_info['mime'] else "m4a"
            relative_path = os.path.join("Tidal", safe_artist, f"{safe_track}.{ext}")
            full_path = os.path.join("/downloads", relative_path)
            
            meta = {"title": request.track, "artist": request.artist, "album": request.album or "Single"}
            background_tasks.add_task(download_file_background, download_info['url'], full_path, meta, request.artworkUrl)
            return {"status": "Download started", "file": relative_path, "source": "Tidal"}

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

@app.get("/library")
async def get_library():
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
                    if artist == "Desconhecido":
                        parts = full_path.replace("\\", "/").split("/")
                        if len(parts) >= 3: artist = parts[-3]
                    library.append({
                        "filename": file, 
                        "display_name": title,
                        "artist": artist,
                        "album": album,
                        "format": file.split('.')[-1].lower(),
                        "coverProxyUrl": get_short_cover_url(file) 
                    })
                except: pass
    return library