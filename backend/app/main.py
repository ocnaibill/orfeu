from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse, RedirectResponse
from pydantic import BaseModel
from typing import Optional, Dict, List, Tuple
import os
import asyncio
import httpx
import subprocess
import mutagen
from urllib.parse import quote
from unidecode import unidecode
from thefuzz import fuzz

# Importação dos Serviços
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider

app = FastAPI(title="Orfeu API", version="1.4.0")

# --- Constantes ---
TIERS = {"low": "128k", "medium": "192k", "high": "320k", "lossless": "original"}

# --- Modelos ---
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

# --- Helpers ---
def normalize_text(text: str) -> str:
    if not text: return ""
    return unidecode(text).lower().strip()

def find_local_match(artist: str, track: str) -> Optional[str]:
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                if os.path.getsize(full_path) == 0: continue
                clean_file = normalize_text(file)
                if fuzz.partial_token_sort_ratio(target_str, clean_file) > 90:
                    return full_path
    return None

# --- Rotas ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.4.0"}

# --- CORREÇÃO: Paginação Manual para iTunes ---
@app.get("/search/catalog")
async def search_catalog(
    query: str, 
    limit: int = 20, 
    offset: int = 0
):
    """
    Busca no catálogo global (iTunes).
    Como a API do iTunes NÃO suporta 'offset' nativamente, buscamos um lote maior (200)
    e fazemos a paginação em memória no Python.
    """
    print(f"🔎 Buscando no catálogo: '{query}' (Client pede: Offset {offset}, Limit {limit})")
    
    # Cache simples em memória poderia ser adicionado aqui para performance
    
    try:
        async with httpx.AsyncClient() as client:
            url = "https://itunes.apple.com/search"
            
            # Pedimos 200 itens para ter margem de manobra para paginação
            # O iTunes limita a ~200 por padrão em muitas queries.
            fetch_limit = 200 
            
            params = {
                "term": query,
                "media": "music",
                "limit": fetch_limit,
                # 'offset': offset # REMOVIDO: iTunes ignora isso
            }
            
            resp = await client.get(url, params=params, timeout=10.0)
            data = resp.json()
            
            raw_results = data.get('results', [])
            
            # --- PAGINAÇÃO EM MEMÓRIA ---
            # Fatiamos a lista completa baseada no que o frontend pediu
            start_index = offset
            end_index = offset + limit
            
            # Se o offset for maior que o total de resultados, retorna vazio
            if start_index >= len(raw_results):
                return []
                
            paged_results = raw_results[start_index:end_index]
            
            final_results = []
            for item in paged_results:
                if item.get('kind') != 'song': continue

                artwork = item.get('artworkUrl100', '').replace("100x100bb", "600x600bb")
                artist = item.get('artistName', '')
                track = item.get('trackName', '')
                
                local_file = find_local_match(artist, track)
                
                final_results.append({
                    "trackName": track,
                    "artistName": artist,
                    "collectionName": item.get('collectionName'),
                    "artworkUrl": artwork,
                    "previewUrl": item.get('previewUrl'),
                    "year": item.get('releaseDate', '')[:4],
                    "isDownloaded": local_file is not None,
                    "filename": local_file
                })
            
            return final_results

    except Exception as e:
        print(f"❌ Erro no catálogo: {e}")
        return []

@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest):
    search_term = unidecode(f"{request.artist} {request.track}")
    print(f"🤖 Smart Download (Fuzzy): {search_term}")
    
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    print("⏳ Aguardando resultados da rede P2P (Max 45s)...")
    best_candidate = None
    highest_score = float('-inf')
    target_clean = normalize_text(f"{request.artist} {request.track}")
    
    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        peer_count = len(raw_results)
        
        if i % 3 == 0 or peer_count > 0: print(f"   Check {i+1}/22: {peer_count} peers.")

        has_perfect_candidate = best_candidate and best_candidate['score'] > 50000
        if peer_count > 15 and has_perfect_candidate: break

        for response in raw_results:
            if response.get('locked', False): continue
            slots_free = response.get('slotsFree', False)
            queue_length = response.get('queueLength', 0)
            upload_speed = response.get('uploadSpeed', 0)

            if 'files' in response:
                for file in response['files']:
                    filename = file['filename']
                    file_basename = os.path.basename(filename.replace("\\", "/"))
                    remote_clean = normalize_text(file_basename)
                    
                    similarity = fuzz.partial_token_sort_ratio(target_clean, remote_clean)
                    if similarity < 85: continue

                    if '.' not in filename: continue
                    ext = filename.split('.')[-1].lower()
                    if ext not in ['flac', 'mp3', 'm4a']: continue

                    score = 0
                    if slots_free: score += 100_000 
                    else: score -= (queue_length * 1000)

                    if ext == 'flac': score += 5000
                    elif ext == 'm4a': score += 2000
                    elif ext == 'mp3': score += 1000
                    
                    score += similarity * 10 
                    score += (upload_speed / 1_000_000)

                    if score > highest_score:
                        highest_score = score
                        best_candidate = {
                            'username': response.get('username'),
                            'filename': filename,
                            'size': file['size'],
                            'score': score
                        }
    
    if not best_candidate:
        raise HTTPException(404, "Nenhum ficheiro compatível encontrado (Fuzzy Match failed).")

    try:
        local_path = AudioManager.find_local_file(best_candidate['filename'])
        if os.path.getsize(local_path) > 0:
            return {"status": "Already downloaded", "file": best_candidate['filename']}
        else:
            os.remove(local_path) 
    except HTTPException: pass
    except Exception: pass

    return await download_slskd(best_candidate['username'], best_candidate['filename'], best_candidate['size'])

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
        if os.path.getsize(path) > 0: return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
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
    return AudioManager.get_audio_metadata(full_path)

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
                    library.append({
                        "filename": file, 
                        "display_name": tags.get('title') or file,
                        "artist": tags.get('artist') or "Desconhecido",
                        "album": tags.get('album'),
                        "format": file.split('.')[-1].lower()
                    })
                except: pass
    return library