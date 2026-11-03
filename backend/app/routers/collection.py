from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import FavoriteRequest, SaveAlbumRequest, SaveArtistRequest
from app.services.audio_manager import AudioManager
from app.services.cover_proxy import get_short_cover_url
from app.services.local_library import fetch_and_assign_genre

router = APIRouter(tags=["collection"])

# Favoritos
@router.post("/users/me/favorites")
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

@router.get("/users/me/favorites")
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


@router.get("/users/me/albums")
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

@router.post("/users/me/albums")
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

@router.delete("/users/me/albums/{album_id}")
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

@router.patch("/users/me/albums/{album_id}/pin")
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

@router.get("/users/me/artists")
def get_saved_artists(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    artists = db.query(models.SavedArtist).filter(models.SavedArtist.user_id == current_user.id).order_by(models.SavedArtist.added_at.desc()).all()
    return [{
        "id": a.artist_id,
        "name": a.name,
        "imageUrl": a.image_url,
        "isPinned": a.is_pinned,
        "savedAt": a.added_at.isoformat() if a.added_at else None
    } for a in artists]

@router.post("/users/me/artists")
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

@router.delete("/users/me/artists/{artist_id}")
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
