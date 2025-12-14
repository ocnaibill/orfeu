from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse, RedirectResponse
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from typing import Optional, Dict
import os
import asyncio
import subprocess
import mutagen
from urllib.parse import quote
from unidecode import unidecode
from thefuzz import fuzz

# Importação dos Serviços
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider # NOVO

app = FastAPI(title="Orfeu API", version="1.7.0")

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
    text = text.lower()
    text = text.replace("$", "s").replace("&", "and")
    text = unidecode(text)
    for char in ['_', '-', '.', '[', ']', '(', ')', '+', '\\', '/']:
        text = text.replace(char, ' ')
    return text.strip()

def find_local_match(artist: str, track: str) -> Optional[str]:
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                if os.path.getsize(full_path) == 0: continue
                clean_file = normalize_text(file)
                ratio = fuzz.partial_token_sort_ratio(target_str, clean_file)
                if ratio > 90:
                    return full_path
    return None

# --- Rotas ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.7.0"}

# --- BUSCA HÍBRIDA (TIDAL -> YOUTUBE MUSIC) ---
@app.get("/search/catalog")
async def search_catalog(
    query: str, 
    limit: int = 20, 
    offset: int = 0,
    type: str = Query("song", enum=["song", "album"])
):
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}]")
    
    results = []

    # 1. Tenta TIDAL Primeiro (Melhor qualidade de metadados)
    # Apenas se for busca de música, pois a API do Tidal que temos é focada em tracks
    if type == "song":
        try:
            print("   Tentando Tidal...")
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, limit)
            if tidal_results:
                results = tidal_results
                print(f"   ✅ Tidal retornou {len(results)} resultados.")
        except Exception as e:
            print(f"   ⚠️ Tidal falhou: {e}")

    # 2. Fallback para YouTube Music (Se Tidal vazio ou se for busca de Álbum)
    if not results:
        print("   Tentando YouTube Music (Fallback)...")
        yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type)
        results = yt_results

    # Paginação (apenas se vier do YTMusic, pois Tidal já paginamos na request)
    # Se a fonte foi Tidal, results já está limitado, mas o offset do frontend 
    # pode precisar de ajuste se implementarmos paginação real no TidalProvider depois.
    # Por enquanto, assumimos que o Tidal retorna a "melhor página".
    
    # Se for YTMusic, aplicamos a paginação em memória
    if not results and type == "song": # Se ambos falharam
         return []

    # Se veio do YTMusic (que retorna 100 itens), paginamos
    # Se veio do Tidal (limitado a 25), retornamos tudo o que veio
    final_page = results
    if len(results) > limit:
         start = offset
         end = offset + limit
         if start < len(results):
             final_page = results[start:end]
         else:
             final_page = []

    # Check local para todos
    for item in final_page:
        if item['type'] == 'song':
            local_file = find_local_match(item['artistName'], item['trackName'])
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file
        else:
            item['isDownloaded'] = False
            item['filename'] = None

    return final_page

# --- ÁLBUM (MANTIDO NO YOUTUBE MUSIC) ---
# Como não temos a rota de álbum do Tidal ainda, mantemos YTMusic
@app.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    print(f"💿 Buscando álbum ID: {collection_id}")
    try:
        # Usa YTMusic provider
        album_data = await run_in_threadpool(CatalogProvider.get_album_details, collection_id)
        
        for track in album_data['tracks']:
            local_file = find_local_match(track['artistName'], track['trackName'])
            track['isDownloaded'] = local_file is not None
            track['filename'] = local_file
            
        return album_data
    except Exception as e:
        print(f"❌ Erro ao buscar álbum: {e}")
        raise HTTPException(500, str(e))

# --- DOWNLOAD INTELIGENTE ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest):
    search_term = unidecode(f"{request.artist} {request.track}")
    print(f"🤖 Smart Download (Fuzzy V2): {search_term}")
    
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        print(f"✅ Smart Match Local: {local_match}")
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    print("⏳ Aguardando resultados da rede P2P...")
    best_candidate = None
    highest_score = float('-inf')
    target_clean = normalize_text(f"{request.artist} {request.track}")
    
    last_peer_count = -1
    stable_checks = 0
    
    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        peer_count = len(raw_results)
        
        if peer_count > 0 and peer_count == last_peer_count:
            stable_checks += 1
        else:
            stable_checks = 0
        last_peer_count = peer_count
        
        if i % 3 == 0: print(f"   Check {i+1}/22: {peer_count} peers (Stable: {stable_checks}).")
        
        candidates_debug = []
        best_flac_debug = None 

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
                    
                    # Bônus de Álbum
                    if request.album:
                        clean_album = normalize_text(request.album)
                        clean_path = normalize_text(filename)
                        if fuzz.partial_ratio(clean_album, clean_path) > 85:
                            score += 5000

                    score += similarity * 10 
                    score += (upload_speed / 1_000_000)

                    candidate_obj = {
                        'username': response.get('username'),
                        'filename': filename,
                        'size': file['size'],
                        'score': score,
                        'ext': ext,
                        'slots': slots_free,
                        'queue': queue_length,
                        'sim': similarity
                    }
                    candidates_debug.append(candidate_obj)

                    if score > highest_score:
                        highest_score = score
                        best_candidate = candidate_obj
                    
                    if ext == 'flac':
                        if best_flac_debug is None or score > best_flac_debug['score']:
                            best_flac_debug = candidate_obj

        if candidates_debug and i % 5 == 0:
            candidates_debug.sort(key=lambda x: x['score'], reverse=True)
            print("   --- Top Candidatos ---")
            for c in candidates_debug[:3]:
                print(f"   [{int(c['score'])}] {c['ext']} | Free: {c['slots']} | Sim: {c['sim']}% | File: {c['filename'][:30]}...")

        if stable_checks >= 4 and peer_count > 0 and best_candidate:
             print("⚡ Resultados estabilizados. Encerrando busca.")
             break

        has_perfect = best_candidate and best_candidate['score'] > 50000
        if peer_count > 15 and has_perfect: 
            print("⚡ Candidato perfeito encontrado. Encerrando.")
            break
    
    if not best_candidate:
        raise HTTPException(404, "Nenhum ficheiro compatível encontrado.")

    print(f"🏆 Vencedor: {best_candidate['filename']} (Score: {int(best_candidate['score'])})")

    try:
        local_path = AudioManager.find_local_file(best_candidate['filename'])
        if os.path.getsize(local_path) > 0:
            return {"status": "Already downloaded", "file": best_candidate['filename']}
        else:
            os.remove(local_path) 
    except: pass

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