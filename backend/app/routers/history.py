import os

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import HistoryRequest
from app.services.audio_manager import AudioManager
from app.services.local_library import fetch_and_assign_genre

router = APIRouter(tags=["history"])


@router.post("/users/me/history")
def log_history(req: HistoryRequest, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    track = db.query(models.Track).filter(models.Track.filename == req.filename).first()
    
    # Se track não existir, cria uma entrada básica
    if not track:
        try:
            fp = AudioManager.find_local_file(req.filename)
            meta = AudioManager.get_audio_metadata(fp)
            tags = AudioManager.get_audio_tags(fp)
            
            # PRIORIDADE: Metadados do catálogo > Tags do arquivo
            # Isso evita problemas com arquivos que têm metadados incorretos
            artist_name = req.catalog_artist or tags.get('artist') or "Desconhecido"
            album_name = req.catalog_album or tags.get('album')
            title_name = req.catalog_title or tags.get('title') or os.path.splitext(req.filename)[0]
            
            # Busca gênero: primeiro do request, depois dos metadados, depois online
            genre = req.genre or tags.get('genre')
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
            db.rollback()
            return {"status": "error", "message": "Track não encontrada"}
    else:
        # Se track existe, atualiza com metadados do catálogo se disponíveis
        updated = False
        
        # Atualiza album_id se não tiver
        if req.album_id and not track.album_id:
            track.album_id = req.album_id
            updated = True
        
        # Se temos metadados do catálogo E eles são diferentes dos atuais, atualiza
        # (metadados do catálogo são mais confiáveis que tags de arquivo)
        if req.catalog_artist and track.artist != req.catalog_artist:
            print(f"📝 Corrigindo artista: '{track.artist}' -> '{req.catalog_artist}'")
            track.artist = req.catalog_artist
            updated = True
        if req.catalog_album and track.album != req.catalog_album:
            print(f"📝 Corrigindo álbum: '{track.album}' -> '{req.catalog_album}'")
            track.album = req.catalog_album
            updated = True
        if req.catalog_title and track.title != req.catalog_title:
            print(f"📝 Corrigindo título: '{track.title}' -> '{req.catalog_title}'")
            track.title = req.catalog_title
            updated = True
            
        # Atualiza gênero se não tiver
        if not track.genre or track.genre == "" or track.genre == "Desconhecido":
            if req.genre and req.genre != "Desconhecido":
                track.genre = req.genre
                updated = True
            else:
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
