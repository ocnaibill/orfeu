from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse, RedirectResponse
from pydantic import BaseModel
from typing import Optional, Dict, List, Tuple
import os
import asyncio
import httpx
from urllib.parse import quote

# Importação dos Serviços Organizados
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider

app = FastAPI(title="Orfeu API", version="1.2.0")

# --- Constantes de Qualidade ---
TIERS = {
    "low": "128k",
    "medium": "192k",
    "high": "320k",
    "lossless": "original"
}

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

# --- Helpers ---
def get_local_library_index() -> List[Tuple[str, str]]:
    """
    Retorna uma lista de tuplas (filename_real, filename_limpo) de todos os arquivos locais.
    Usado para matching rápido sem varrer o disco múltiplas vezes.
    """
    base_path = "/downloads"
    index = []
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                # Limpeza para matching (sem _, -, pontos)
                clean_name = file.lower().replace("_", " ").replace("-", " ").replace(".", " ")
                index.append((file, clean_name))
    return index

def find_local_match(artist: str, track: str, library_index: List[Tuple[str, str]] = None) -> Optional[str]:
    """
    Verifica se uma música (Tokens de Artista + Título) existe na lista local.
    Retorna o filename se encontrar.
    """
    if library_index is None:
        library_index = get_local_library_index()
        
    search_tokens = set(f"{artist} {track}".lower().split())
    
    for filename, clean_name in library_index:
        # Se todos os tokens da busca (ex: "daft", "punk", "lucky") existirem no nome do arquivo
        if all(token in clean_name for token in search_tokens):
            return filename
            
    return None

def find_local_file(filename: str) -> str:
    """
    Localiza o ficheiro no sistema de arquivos (Busca Profunda).
    """
    base_path = "/downloads"
    sanitized_filename = filename.replace("\\", "/").lstrip("/")
    target_file_name = os.path.basename(sanitized_filename)
    
    # 1. Tenta caminho direto
    for root, dirs, files in os.walk(base_path):
        if target_file_name in files:
            return os.path.join(root, target_file_name)
            
    raise HTTPException(status_code=404, detail=f"Ficheiro '{target_file_name}' não encontrado.")

def get_audio_tags(file_path: str) -> dict:
    """
    Usa Mutagen para ler tags artísticas.
    """
    tags = {
        "title": None,
        "artist": None,
        "album": None,
        "genre": None,
        "date": None
    }
    try:
        audio = mutagen.File(file_path, easy=True)
        if audio:
            tags["title"] = audio.get("title", [None])[0]
            tags["artist"] = audio.get("artist", [None])[0]
            tags["album"] = audio.get("album", [None])[0]
            tags["genre"] = audio.get("genre", [None])[0]
            tags["date"] = audio.get("date", [None])[0] or audio.get("year", [None])[0]
    except Exception as e:
        print(f"⚠️ Erro ao ler tags: {e}")
    return tags

def get_audio_metadata(file_path: str) -> dict:
    """
    Combina FFmpeg (Dados Técnicos) + Mutagen (Dados Artísticos).
    """
    tech_data = {}
    try:
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", file_path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        data = json.loads(result.stdout)
        
        audio_stream = next((s for s in data.get('streams', []) if s['codec_type'] == 'audio'), None)
        format_info = data.get('format', {})
        
        if audio_stream:
            codec = audio_stream.get('codec_name', 'unknown')
            sample_rate = int(audio_stream.get('sample_rate', 0))
            bits = audio_stream.get('bits_per_raw_sample') or audio_stream.get('bits_per_sample')
            
            tech_label = f"{sample_rate}Hz"
            if bits: tech_label = f"{bits}bit/{tech_label}"
            
            tech_data = {
                "format": codec,
                "bitrate": int(format_info.get('bit_rate', 0)),
                "sample_rate": sample_rate,
                "channels": audio_stream.get('channels'),
                "duration": float(format_info.get('duration', 0)),
                "tech_label": tech_label,
                "is_lossless": codec in ['flac', 'wav', 'alac']
            }
    except Exception:
        pass

    artistic_data = get_audio_tags(file_path)
    if not artistic_data["title"]:
        artistic_data["title"] = os.path.splitext(os.path.basename(file_path))[0]

    return {
        "filename": os.path.basename(file_path),
        **tech_data,
        **artistic_data
    }

def transcode_audio(file_path: str, bitrate: str):
    """
    Gera um stream de áudio transcodificado para MP3 usando FFmpeg.
    """
    cmd = [
        "ffmpeg", "-i", file_path, "-f", "mp3", "-ab", bitrate,
        "-vn", "-map", "0:a:0", "-"
    ]
    process = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=10**6
    )
    try:
        while True:
            chunk = process.stdout.read(64 * 1024)
            if not chunk: break
            yield chunk
    finally:
        process.kill()

# --- Rotas de Sistema ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.2"}

# --- NOVA FUNCIONALIDADE: BUSCA CURADA (ITUNES) ---
@app.get("/search/catalog")
async def search_catalog(query: str):
    """
    Busca metadados organizados no iTunes API e cruza com a biblioteca local
    para indicar se já possuímos o arquivo.
    """
    print(f"🔎 Buscando no catálogo global: {query}")
    try:
        # 1. Carrega índice local uma vez para performance
        local_index = get_local_library_index()

        # 2. Busca no iTunes
        async with httpx.AsyncClient() as client:
            url = "https://itunes.apple.com/search"
            params = {
                "term": query,
                "media": "music",
                "entity": "song",
                "limit": 15
            }
            resp = await client.get(url, params=params, timeout=8.0)
            data = resp.json()
            
            results = []
            for item in data.get('results', []):
                artwork = item.get('artworkUrl100', '').replace("100x100bb", "600x600bb")
                artist = item.get('artistName', '')
                track = item.get('trackName', '')
                
                # 3. Verifica existência local
                local_file = find_local_match(artist, track, local_index)
                
                results.append({
                    "trackName": track,
                    "artistName": artist,
                    "collectionName": item.get('collectionName'),
                    "artworkUrl": artwork,
                    "previewUrl": item.get('previewUrl'),
                    "year": item.get('releaseDate', '')[:4],
                    "isDownloaded": local_file is not None, # Flag para a UI
                    "filename": local_file # Nome do arquivo para play imediato
                })
            
            return results
    except Exception as e:
        print(f"❌ Erro no catálogo: {e}")
        return []

# --- NOVA FUNCIONALIDADE: SMART DOWNLOAD ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest):
    """
    Fluxo completo: Checagem Local -> Busca P2P -> Polling -> Algoritmo de Score -> Download.
    """
    print(f"🤖 Smart Download iniciado para: {request.artist} - {request.track}")

    # 0. Check LOCAL antes de tudo (Economiza banda e tempo)
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        print(f"✅ Smart Match: Encontrado localmente ({local_match}). Pulando busca P2P.")
        return {
            "status": "Already downloaded", 
            "file": local_match,
            "display_name": request.track,
            "message": "Música já disponível no cache."
        }

    # 1. Inicia busca P2P
    search_term = f"{request.artist} {request.track}"
    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    # 2. Polling de resultados
    print("⏳ Aguardando resultados da rede P2P (Max 45s)...")
    best_candidate = None
    highest_score = float('-inf')
    
    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        
        peer_count = len(raw_results)
        
        if i % 3 == 0 or peer_count > 0:
            print(f"   Check {i+1}/22: {peer_count} peers responderam.")

        # Saída Antecipada Inteligente
        has_great_candidate = best_candidate and best_candidate['score'] > 5000
        has_perfect_candidate = best_candidate and best_candidate['score'] > 50000
        
        if (peer_count > 15 and has_perfect_candidate) or (peer_count > 50 and has_great_candidate):
             print(f"⚡ Candidato suficiente encontrado (Score: {best_candidate['score']}). Encerrando busca.")
             break

        for response in raw_results:
            if response.get('locked', False): continue
            
            slots_free = response.get('slotsFree', False)
            queue_length = response.get('queueLength', 0)
            upload_speed = response.get('uploadSpeed', 0)

            if 'files' in response:
                for file in response['files']:
                    filename = file['filename']
                    
                    # Filtro de segurança (Token Matching)
                    normalized_name = filename.lower().replace("\\", "/")
                    file_basename = normalized_name.split("/")[-1]
                    clean_name = file_basename.replace("_", " ").replace("-", " ").replace(".", " ")
                    
                    track_tokens = set(request.track.lower().split())
                    
                    if not all(token in clean_name for token in track_tokens):
                        continue

                    if '.' not in filename: continue
                    ext = filename.split('.')[-1].lower()
                    if ext not in ['flac', 'mp3', 'm4a']: continue

                    # Algoritmo de Score
                    score = 0
                    if slots_free: score += 100_000 
                    else: score -= (queue_length * 1000)

                    if ext == 'flac': score += 5000
                    elif ext == 'm4a': score += 2000
                    elif ext == 'mp3': score += 1000
                    
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
        print("❌ Nenhum candidato passou nos filtros após o timeout.")
        raise HTTPException(404, "Nenhum ficheiro compatível encontrado na rede P2P no momento. Tente novamente em instantes.")

    print(f"🏆 Vencedor P2P: {best_candidate['filename']} (Score: {int(best_candidate['score'])})")

    # 4. Inicia Download
    return await download_slskd(
        best_candidate['username'], 
        best_candidate['filename'], 
        best_candidate['size']
    )

# --- Rotas Legadas (Soulseek Direto) ---
@app.post("/search/{query}")
async def start_search_legacy(query: str):
    return await search_slskd(query)

@app.get("/results/{search_id}")
async def view_results(search_id: str):
    raw_results = await get_search_results(search_id)
    # Lógica simplificada para manter compatibilidade
    return raw_results 

@app.post("/download")
async def queue_download(request: DownloadRequest):
    try:
        path = AudioManager.find_local_file(request.filename)
        if os.path.getsize(path) > 0:
             return {"status": "Already downloaded", "file": request.filename}
    except HTTPException:
        pass
    return await download_slskd(request.username, request.filename, request.size)

@app.get("/download/status")
async def check_download_status(filename: str):
    try:
        path = AudioManager.find_local_file(filename)
        if os.path.getsize(path) > 0:
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
    except HTTPException:
        pass
    status = await get_transfer_status(filename)
    if status: return status
    return {"state": "Unknown", "progress": 0.0, "message": "Iniciando"}

@app.post("/download/auto")
async def auto_download_best(request: AutoDownloadRequest):
    # Lógica antiga de auto download (mantida para compatibilidade)
    raw_results = await get_search_results(request.search_id)
    best = None
    high = float('-inf')
    for response in raw_results:
        if response.get('locked', False): continue
        slots_free = response.get('slotsFree', False)
        queue_length = response.get('queueLength', 0)
        if 'files' in response:
            for file in response['files']:
                fname = file['filename']
                if '.' not in fname: continue
                ext = fname.split('.')[-1].lower()
                if ext not in ['flac', 'mp3']: continue
                score = 0
                if slots_free: score += 50000
                else: score -= (queue_length * 1000)
                if ext == 'flac': score += 10000
                elif ext == 'mp3': score += 1000
                score += (file.get('bitRate') or 0)
                if score > high:
                    high = score
                    best = {'username': response.get('username'), 'filename': fname, 'size': file['size']}
    if not best: raise HTTPException(404, "Nada encontrado.")
    return await download_slskd(best['username'], best['filename'], best['size'])

# --- Rotas de Mídia ---
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
        res = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=index", "-of", "csv=p=0", full_path], capture_output=True, text=True)
        if res.stdout.strip():
             return StreamingResponse(AudioManager.extract_cover_stream(full_path), media_type="image/jpeg")
    except: pass
    
    url = await LyricsProvider.get_online_cover(full_path)
    if url: return RedirectResponse(url)
    raise HTTPException(404, "Capa não encontrada")

@app.get("/stream")
async def stream_music(
    request: Request,
    filename: str, 
    quality: str = Query("lossless", enum=["low", "medium", "high", "lossless"])
):
    full_path = AudioManager.find_local_file(filename)
    
    if quality != "lossless":
        return StreamingResponse(
            AudioManager.transcode_stream(full_path, quality), 
            media_type="audio/mpeg"
        )
    
    file_size = os.path.getsize(full_path)
    range_header = request.headers.get("range")

    if range_header:
        byte_range = range_header.replace("bytes=", "").split("-")
        start = int(byte_range[0])
        end = int(byte_range[1]) if byte_range[1] else file_size - 1
        
        if start >= file_size:
             return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
             
        chunk_size = (end - start) + 1
        
        with open(full_path, "rb") as f:
            f.seek(start)
            data = f.read(chunk_size)
            
        headers = {
            "Content-Range": f"bytes {start}-{end}/{file_size}",
            "Accept-Ranges": "bytes",
            "Content-Length": str(chunk_size),
            "Content-Type": "audio/flac" if full_path.lower().endswith(".flac") else "audio/mpeg",
        }
        
        return Response(data, status_code=206, headers=headers)

    headers = {
        "Content-Length": str(file_size),
        "Accept-Ranges": "bytes",
        "Content-Type": "audio/flac" if full_path.lower().endswith(".flac") else "audio/mpeg",
    }
    
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