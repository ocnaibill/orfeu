import os

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from app.core import config
from app.deps import get_current_user
from app.database import get_db
from app import models
from app.services.audio_manager import AudioManager
from app.services.cover_proxy import get_short_cover_url
from app.services.local_library import sync_files_to_db, process_library_auto_tagging

router = APIRouter(tags=["library"])

@router.post("/library/scan", dependencies=[Depends(get_current_user)])
async def scan_library_db(background_tasks: BackgroundTasks):
    """
    Força uma varredura no disco e atualiza o Banco de Dados.
    """
    background_tasks.add_task(sync_files_to_db)
    return {"status": "started", "message": "Indexação iniciada."}

@router.get("/library", dependencies=[Depends(get_current_user)])
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

@router.post("/library/organize", dependencies=[Depends(get_current_user)])
async def organize_library(background_tasks: BackgroundTasks):
    background_tasks.add_task(process_library_auto_tagging)
    return {"status": "started", "message": "O processo de organização iniciou em segundo plano."}

@router.get("/library/legacy", dependencies=[Depends(get_current_user)])
def get_library_legacy():
    """
    Rota legada - varre o disco diretamente (mais lento).
    Use /library para a versão via banco de dados.
    """
    base_path = config.MUSIC_DIR
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
