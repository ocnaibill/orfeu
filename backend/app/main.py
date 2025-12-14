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

app = FastAPI(title="Orfeu API", version="1.8.0")

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
    tidalId: Optional[int] = None # NOVO: ID para download direto

# --- Helpers de Download HTTP ---
async def download_file_background(url: str, dest_path: str):
    """
    Baixa um arquivo HTTP em background e salva no disco.
    """
    try:
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        # Cria um arquivo temporário primeiro
        temp_path = dest_path + ".tmp"
        
        async with httpx.AsyncClient() as client:
            async with client.stream('GET', url) as response:
                response.raise_for_status()
                with open(temp_path, 'wb') as f:
                    async for chunk in response.aiter_bytes():
                        f.write(chunk)
        
        # Renomeia para o final apenas quando acabar (Atomicidade)
        os.rename(temp_path, dest_path)
        print(f"✅ Download HTTP concluído: {dest_path}")
        
        # Opcional: Tentar baixar capa e embutir tags aqui no futuro
    except Exception as e:
        print(f"❌ Erro no download HTTP de fundo: {e}")
        if os.path.exists(temp_path): os.remove(temp_path)


# --- Helpers Genéricos ---
def normalize_text(text: str) -> str:
    if not text: return ""
    text = text.lower().replace("$", "s").replace("&", "and")
    return unidecode(text).strip()

def find_local_match(artist: str, track: str) -> Optional[str]:
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                if os.path.getsize(full_path) == 0: continue
                clean_file = normalize_text(file)
                # Verifica similaridade, dando peso ao nome do arquivo
                if fuzz.partial_token_sort_ratio(target_str, clean_file) > 90:
                    return full_path
    return None

# --- Rotas ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.8.0"}

@app.get("/search/catalog")
async def search_catalog(
    query: str, limit: int = 20, offset: int = 0, type: str = Query("song", enum=["song", "album"])
):
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}]")
    results = []

    # 1. Tidal (Prioridade para músicas)
    if type == "song":
        try:
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, limit)
            if tidal_results: results = tidal_results
        except Exception as e: print(f"⚠️ Tidal falhou: {e}")

    # 2. YouTube Music (Fallback)
    if not results:
        yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type)
        results = yt_results

    # Paginação manual para YTMusic (Tidal já vem paginado pelo provider se suportado)
    # Se a lista for grande (> limit), paginamos aqui
    if len(results) > limit:
         start = offset
         end = offset + limit
         if start < len(results):
             results = results[start:end]
         else:
             results = []

    # Check Local
    for item in results:
        if item.get('type') == 'song':
            local_file = find_local_match(item['artistName'], item['trackName'])
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file

    return results

@app.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    # Por enquanto, mantemos YTMusic para álbuns pois a API Tidal 'track' que temos não lista álbuns
    # Futuramente podemos descobrir a rota /album do Tidal
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

# --- SMART DOWNLOAD (AGORA COM TIDAL DIRECT) ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    print(f"🤖 Smart Download: {request.artist} - {request.track}")
    
    # 0. Check Local
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        print(f"✅ Cache Local: {local_match}")
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    # 1. TENTATIVA TIDAL DIRECT (Prioridade Máxima)
    if request.tidalId:
        print(f"🌊 Tentando download direto do Tidal (ID: {request.tidalId})...")
        download_info = await run_in_threadpool(TidalProvider.get_download_url, request.tidalId)
        
        if download_info and download_info.get('url'):
            # Define caminho: downloads/Tidal/Artista/Album/Musica.flac
            safe_artist = normalize_text(request.artist).replace(" ", "_")
            safe_track = normalize_text(request.track).replace(" ", "_")
            ext = "flac" if "flac" in download_info['mime'] else "m4a"
            
            # Pasta organizada
            relative_path = os.path.join("Tidal", safe_artist, f"{safe_track}.{ext}")
            full_path = os.path.join("/downloads", relative_path)
            
            print(f"🚀 Iniciando download HTTP para: {full_path}")
            
            # Inicia download em background para não travar a resposta
            background_tasks.add_task(download_file_background, download_info['url'], full_path)
            
            # Retorna o nome do arquivo que ESTÁ SENDO baixado
            # O frontend vai fazer polling em /download/status e ver o progresso (bytes no disco)
            return {
                "status": "Download started",
                "file": relative_path, # Caminho relativo que find_local_file vai achar
                "source": "Tidal"
            }
        else:
            print("⚠️ Falha ao obter link Tidal. Caindo para Soulseek...")

    # 2. TENTATIVA SOULSEEK (Fallback)
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
                        best_candidate = {
                            'username': response.get('username'),
                            'filename': fname,
                            'size': file['size'],
                            'score': score
                        }
    
    if not best_candidate:
        raise HTTPException(404, "Nenhum ficheiro encontrado.")

    print(f"🏆 Vencedor Soulseek: {best_candidate['filename']}")
    
    # Check local again just in case
    try:
        if AudioManager.find_local_file(best_candidate['filename']):
             return {"status": "Already downloaded", "file": best_candidate['filename']}
    except: pass

    return await download_slskd(best_candidate['username'], best_candidate['filename'], best_candidate['size'])

# ... (Mantenha todas as outras rotas: status, cover, stream, etc. inalteradas) ...
# ... Copiar o resto do arquivo da versão anterior ...

# --- Rotas Legadas e de Mídia ---
@app.post("/search/{query}")
async def start_search_legacy(query: str): return await search_slskd(query)

@app.get("/results/{search_id}")
async def view_results(search_id: str): return await get_search_results(search_id) 

@app.post("/download")
async def queue_download(request: DownloadRequest):
    return await download_slskd(request.username, request.filename, request.size)

@app.get("/download/status")
async def check_download_status(filename: str):
    # 1. Check Local (Se tiver tamanho completo, pronto)
    # Como não sabemos o tamanho total no download HTTP sem banco, 
    # assumimos que se existe e não está crescendo há X segundos...
    # Mas para o MVP: Se existe localmente E não está na lista do Slskd,
    # pode ser um download HTTP em andamento ou completo.
    
    try:
        path = AudioManager.find_local_file(filename)
        size = os.path.getsize(path)
        
        # Se for um arquivo da pasta Tidal, assumimos Completed se tiver tamanho razoavel (>1MB)
        # Melhoria futura: Guardar status de download HTTP em memória/banco.
        if "Tidal" in path and size > 1000000:
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Tidal Download"}
             
        # Se for Soulseek completo
        if size > 0 and "Tidal" not in path: 
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
    except HTTPException:
        pass

    # 2. Check Slskd
    status = await get_transfer_status(filename)
    if status: return status
    
    # 3. Fallback
    # Se estamos baixando via HTTP (Tidal), o arquivo existe no disco mas está crescendo.
    # O AudioManager.find_local_file pode ter achado o arquivo .tmp ou final incompleto.
    return {"state": "Unknown", "progress": 0.0, "message": "Procurando..."}

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