import os
import uuid

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from sqlalchemy.orm import Session

from app import models
from app.core import config
from app.database import get_db
from app.deps import get_current_user
from app.schemas import PlaylistCreate, PlaylistItemAdd, PlaylistUpdateRequest
from app.services.audio_manager import AudioManager
from app.services.cover_proxy import get_short_cover_url
from app.services.local_library import fetch_and_assign_genre

router = APIRouter(tags=["playlists"])


# --- PLAYLISTS (NOVAS ROTAS) ---
@router.post("/users/me/playlists")
def create_playlist(playlist: PlaylistCreate, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    db_playlist = models.Playlist(name=playlist.name, is_public=playlist.is_public, user_id=current_user.id)
    db.add(db_playlist)
    db.commit()
    db.refresh(db_playlist)
    return db_playlist

@router.get("/users/me/playlists")
def get_playlists(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    playlists = db.query(models.Playlist).filter(models.Playlist.user_id == current_user.id).all()
    result = []
    for p in playlists:
        tracks_count = db.query(models.PlaylistItem).filter(models.PlaylistItem.playlist_id == p.id).count()
        result.append({
            "id": p.id,
            "name": p.name,
            "cover_url": p.cover_url,
            "is_public": p.is_public,
            "created_at": p.created_at.isoformat() if p.created_at else None,
            "tracks_count": tracks_count
        })
    return result

@router.post("/users/me/playlists/{playlist_id}/tracks")
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

@router.get("/users/me/playlists/{playlist_id}")
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


@router.put("/users/me/playlists/{playlist_id}")
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


@router.post("/users/me/playlists/{playlist_id}/cover")
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
    file_path = os.path.join(config.PLAYLIST_COVERS_DIR, unique_filename)
    
    # Remove capa antiga se existir (e for do mesmo sistema)
    if playlist.cover_url and "/playlist_covers/" in playlist.cover_url:
        old_filename = playlist.cover_url.split("/")[-1]
        old_path = os.path.join(config.PLAYLIST_COVERS_DIR, old_filename)
        if os.path.exists(old_path):
            os.remove(old_path)
    
    # Salva o arquivo
    contents = await file.read()
    with open(file_path, "wb") as f:
        f.write(contents)
    
    # Atualiza URL no banco
    cover_url = f"{config.PUBLIC_BASE_URL}/downloads/playlist_covers/{unique_filename}"
    playlist.cover_url = cover_url
    db.commit()
    
    return {
        "status": "uploaded",
        "cover_url": cover_url
    }

