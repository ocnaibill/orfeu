from fastapi import FastAPI, HTTPException, Query, Request, Response, BackgroundTasks
from fastapi.responses import StreamingResponse, RedirectResponse
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from typing import Optional, Dict
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
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider

app = FastAPI(title="Orfeu API", version="1.13.0")

# --- Constantes ---
TIERS = {"low": "128k", "medium": "192k", "high": "320k", "lossless": "original"}

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
                
                parent_folder = os.path.basename(root)
                candidate_str = normalize_text(f"{parent_folder} {file}")
                
                if fuzz.partial_token_sort_ratio(target_str, candidate_str) > 90: 
                    return full_path
    return None

# --- Lógica de Auto-Tagging (Background) ---
async def process_library_auto_tagging():
    print("🧹 Iniciando Auto-Tagging da Biblioteca...")
    base_path = "/downloads"
    count = 0
    
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                try:
                    # Lê tags atuais
                    current_tags = AudioManager.get_audio_tags(full_path)
                    
                    # Se faltar Artista ou Título, é candidato a correção
                    if not current_tags.get('artist') or not current_tags.get('title') or current_tags.get('artist') == 'Desconhecido':
                        print(f"📝 Identificando: {file}...")
                        
                        # Tenta limpar o nome do arquivo para busca
                        clean_name = os.path.splitext(file)[0].replace("_", " ").replace("-", " ")
                        clean_name = normalize_text(clean_name)
                        
                        # 1. Busca no Tidal (Prioridade)
                        results = await run_in_threadpool(TidalProvider.search_catalog, clean_name, 1)
                        
                        # 2. Fallback YouTube Music
                        if not results:
                            results = await run_in_threadpool(CatalogProvider.search_catalog, clean_name, 1)
                        
                        if results:
                            best_match = results[0]
                            # Verifica similaridade para não etiquetar errado
                            match_str = normalize_text(f"{best_match['artistName']} {best_match['trackName']}")
                            similarity = fuzz.token_set_ratio(clean_name, match_str)
                            
                            if similarity > 80:
                                print(f"   ✅ Match encontrado: {best_match['artistName']} - {best_match['trackName']} ({similarity}%)")
                                
                                # Baixa capa se houver
                                cover_bytes = None
                                if best_match.get('artworkUrl'):
                                    try:
                                        async with httpx.AsyncClient() as client:
                                            resp = await client.get(best_match['artworkUrl'])
                                            if resp.status_code == 200: cover_bytes = resp.content
                                    except: pass
                                
                                # Aplica Tags no Arquivo Físico
                                meta = {
                                    "title": best_match['trackName'],
                                    "artist": best_match['artistName'],
                                    "album": best_match['collectionName']
                                }
                                await run_in_threadpool(AudioManager.embed_metadata, full_path, meta, cover_bytes)
                                count += 1
                            else:
                                print(f"   ⚠️ Match fraco ({similarity}%). Ignorando.")
                except Exception as e:
                    print(f"❌ Erro ao processar {file}: {e}")
                    
    print(f"✨ Auto-Tagging concluído. {count} arquivos atualizados.")

# --- Rotas ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.13.0"}

# --- NOVA ROTA: ORGANIZAR BIBLIOTECA ---
@app.post("/library/organize")
async def organize_library(background_tasks: BackgroundTasks):
    """
    Dispara um processo em segundo plano para identificar músicas sem tags
    na biblioteca e preencher metadados usando Tidal/YouTube.
    """
    background_tasks.add_task(process_library_auto_tagging)
    return {"status": "started", "message": "O processo de organização iniciou em segundo plano."}

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

@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    print(f"🤖 Smart Download: {request.artist} - {request.track}")
    
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        print(f"✅ Cache Local: {local_match}")
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    if request.tidalId:
        print(f"🌊 Tentando download direto do Tidal (ID: {request.tidalId})...")
        download_info = await run_in_threadpool(TidalProvider.get_download_url, request.tidalId)
        if download_info and download_info.get('url'):
            safe_artist = normalize_text(request.artist).replace(" ", "_")
            safe_track = normalize_text(request.track).replace(" ", "_")
            ext = "flac" if "flac" in download_info['mime'] else "m4a"
            relative_path = os.path.join("Tidal", safe_artist, f"{safe_track}.{ext}")
            full_path = os.path.join("/downloads", relative_path)
            
            meta = {"title": request.track, "artist": request.artist, "album": request.album or "Single"}
            background_tasks.add_task(download_file_background, download_info['url'], full_path, meta, request.artworkUrl)
            return {"status": "Download started", "file": relative_path, "source": "Tidal"}

    search_term = unidecode(f"{request.artist} {request.track}")
    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    print("⏳ Buscando no Soulseek...")
    best_candidate = None
    highest_score = float('-inf')
    target_clean = normalize_text(f"{request.artist} {request.track}")
    
    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        peer_count = len(raw_results)
        if i % 3 == 0: print(f"   Check {i+1}/22: {peer_count} peers.")

        has_perfect = best_candidate and best_candidate['score'] > 50000
        if peer_count > 15 and has_perfect: break

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

                    if score > highest_score:
                        highest_score = score
                        best_candidate = {'username': response.get('username'), 'filename': fname, 'size': file['size'], 'score': score}
    
    if not best_candidate: raise HTTPException(404, "Nenhum ficheiro encontrado.")
    
    try:
        if AudioManager.find_local_file(best_candidate['filename']):
             return {"status": "Already downloaded", "file": best_candidate['filename']}
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
                    
                    # Se tiver tags, usa. Se não, tenta inferir ou deixa 'Desconhecido'.
                    title = tags.get('title') or os.path.splitext(file)[0]
                    artist = tags.get('artist') or "Desconhecido"
                    album = tags.get('album')
                    
                    # Tenta inferência simples de pasta se não tiver tags
                    if artist == "Desconhecido":
                        parts = full_path.replace("\\", "/").split("/")
                        if len(parts) >= 3:
                            artist = parts[-3] # Assume pasta avó (Artist/Album/File)
                            
                    library.append({
                        "filename": file, 
                        "display_name": title,
                        "artist": artist,
                        "album": album,
                        "format": file.split('.')[-1].lower()
                    })
                except: pass
    return library