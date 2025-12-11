from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.services.slskd_client import search_slskd, get_search_results, download_slskd

app = FastAPI(title="Orfeu API", version="0.1.0")

# --- Modelos de Dados ---
class DownloadRequest(BaseModel):
    username: str
    filename: str
    size: Optional[int] = None 

@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend"}

# --- Busca ---
@app.post("/search/{query}")
async def start_search(query: str):
    """
    Inicia uma busca no Soulseek.
    """
    return await search_slskd(query)

# --- Resultados ---
@app.get("/results/{search_id}")
async def view_results(search_id: str):
    """
    Vê os resultados da busca.
    """
    raw_results = await get_search_results(search_id)
    
    files = []
    for response in raw_results:
        if 'files' in response:
            for file in response['files']:
                if file['filename'].lower().endswith(('.flac', '.mp3')):
                    files.append({
                        'filename': file['filename'],
                        'size': file['size'], # O frontend receberá este valor aqui
                        'bitrate': file.get('bitRate'),
                        'speed': response.get('uploadSpeed', 0),
                        'username': response.get('username'),
                        'is_locked': response.get('locked', False)
                    })
    
    # Ordena: Mais rápidos primeiro
    files.sort(key=lambda x: x['speed'], reverse=True)
    
    return files

# --- Download ---
@app.post("/download")
async def queue_download(request: DownloadRequest):
    """
    Envia pedido de download.
    Espera JSON: {"username": "...", "filename": "...", "size": 123456}
    """
    return await download_slskd(request.username, request.filename, request.size)