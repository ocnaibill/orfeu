from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import os
from app.services.slskd_client import search_slskd, get_search_results, download_slskd

app = FastAPI(title="Orfeu API", version="0.1.0")

# --- Modelos de Dados ---
class DownloadRequest(BaseModel):
    username: str
    filename: str
    size: Optional[int] = None

class AutoDownloadRequest(BaseModel):
    search_id: str

@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend"}

# --- Busca ---
@app.post("/search/{query}")
async def start_search(query: str):
    return await search_slskd(query)

# --- Resultados (CURADOS) ---
@app.get("/results/{search_id}")
async def view_results(search_id: str):
    """
    Retorna lista agrupada de músicas.
    """
    raw_results = await get_search_results(search_id)
    grouped_songs: Dict[str, dict] = {}

    for response in raw_results:
        if response.get('locked', False): continue
        if 'files' in response:
            for file in response['files']:
                full_filename = file['filename']
                base_filename = full_filename.replace("\\", "/").split("/")[-1]
                
                if '.' not in base_filename: continue
                name_part, ext_part = os.path.splitext(base_filename)
                ext = ext_part.lower().replace(".", "")
                
                if ext not in ['flac', 'mp3']: continue

                # Score Logic
                score = 0
                if ext == 'flac': score += 10000
                elif ext == 'mp3': score += 1000
                bitrate = file.get('bitRate') or 0
                score += bitrate
                speed = response.get('uploadSpeed', 0)
                score += (speed / 1_000_000)

                candidate = {
                    'display_name': name_part,
                    'extension': ext,
                    'filename': full_filename,
                    'size': file['size'],
                    'bitrate': bitrate,
                    'speed': speed,
                    'username': response.get('username'),
                    'score': score
                }

                if name_part in grouped_songs:
                    if candidate['score'] > grouped_songs[name_part]['score']:
                        grouped_songs[name_part] = candidate
                else:
                    grouped_songs[name_part] = candidate
    
    final_list = list(grouped_songs.values())
    final_list.sort(key=lambda x: x['score'], reverse=True) # Ordena pelos melhores scores primeiro
    return final_list

# --- Download Manual ---
@app.post("/download")
async def queue_download(request: DownloadRequest):
    return await download_slskd(request.username, request.filename, request.size)

# --- Download Automático  ---
@app.post("/download/auto")
async def auto_download_best(request: AutoDownloadRequest):
    """
    Varre todos os resultados da busca e baixa o arquivo com o maior Score absoluto.
    """
    raw_results = await get_search_results(request.search_id)
    
    best_candidate = None
    highest_score = -1

    for response in raw_results:
        # Ignora bloqueados
        if response.get('locked', False): continue

        if 'files' in response:
            for file in response['files']:
                filename = file['filename']
                # Pega extensão
                if '.' not in filename: continue
                ext = filename.split('.')[-1].lower()
                
                if ext not in ['flac', 'mp3']: continue

                # --- Lógica de Pontuação ---
                score = 0
                
                # 1. Formato
                if ext == 'flac': score += 10000
                elif ext == 'mp3': score += 1000
                
                # 2. Bitrate
                bitrate = file.get('bitRate') or 0
                score += bitrate
                
                # 3. Velocidade
                speed = response.get('uploadSpeed', 0)
                score += (speed / 1_000_000)

                # Verifica se é o novo rei
                if score > highest_score:
                    highest_score = score
                    best_candidate = {
                        'username': response.get('username'),
                        'filename': filename,
                        'size': file['size']
                    }

    if not best_candidate:
        raise HTTPException(status_code=404, detail="Nenhum arquivo válido encontrado para download automático.")
    
    print(f"🤖 Auto-Download Vencedor: {best_candidate['filename']} (User: {best_candidate['username']})")

    # Chama a função de download com os dados do vencedor
    return await download_slskd(
        best_candidate['username'], 
        best_candidate['filename'], 
        best_candidate['size']
    )

# --- Streaming ---
@app.get("/stream")
async def stream_music(filename: str):
    base_path = "/downloads"
    sanitized_filename = filename.replace("\\", "/").lstrip("/")
    target_file_name = os.path.basename(sanitized_filename)
    
    full_path = None
    
    for root, dirs, files in os.walk(base_path):
        if target_file_name in files:
            full_path = os.path.join(root, target_file_name)
            break
    
    if not full_path or not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail=f"Arquivo '{target_file_name}' não encontrado.")

    def iterfile():
        with open(full_path, mode="rb") as file_like:
            yield from file_like

    media_type = "audio/flac" if full_path.lower().endswith(".flac") else "audio/mpeg"
    return StreamingResponse(iterfile(), media_type=media_type)