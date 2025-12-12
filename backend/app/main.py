from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import os
import subprocess
import json
import mutagen
import httpx 
# Importamos a nova função get_transfer_status
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status

app = FastAPI(title="Orfeu API", version="0.1.0")

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

# --- Helpers ---
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

# --- Rotas ---

@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend"}

@app.post("/search/{query}")
async def start_search(query: str):
    return await search_slskd(query)

@app.get("/results/{search_id}")
async def view_results(search_id: str):
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
    final_list.sort(key=lambda x: x['score'], reverse=True)
    return final_list

@app.post("/download")
async def queue_download(request: DownloadRequest):
    """
    Inicia download manual.
    Verifica se o ficheiro já existe localmente antes de pedir ao Soulseek.
    """
    try:
        find_local_file(request.filename)
        # Se encontrou, retorna sucesso imediato sem baixar de novo
        print(f"✅ Arquivo já existe em disco: {request.filename}")
        return {
            "status": "Already downloaded", 
            "file": request.filename, 
            "message": "Ficheiro já disponível no servidor"
        }
    except HTTPException:
        # Se não encontrou (404), prossegue com o download normal
        pass

    return await download_slskd(request.username, request.filename, request.size)

@app.post("/download/auto")
async def auto_download_best(request: AutoDownloadRequest):
    raw_results = await get_search_results(request.search_id)
    best_candidate = None
    highest_score = -1

    for response in raw_results:
        if response.get('locked', False): continue
        if 'files' in response:
            for file in response['files']:
                filename = file['filename']
                if '.' not in filename: continue
                ext = filename.split('.')[-1].lower()
                if ext not in ['flac', 'mp3']: continue

                score = 0
                if ext == 'flac': score += 10000
                elif ext == 'mp3': score += 1000
                bitrate = file.get('bitRate') or 0
                score += bitrate
                speed = response.get('uploadSpeed', 0)
                score += (speed / 1_000_000)

                if score > highest_score:
                    highest_score = score
                    best_candidate = {
                        'username': response.get('username'),
                        'filename': filename,
                        'size': file['size']
                    }

    if not best_candidate:
        raise HTTPException(status_code=404, detail="Nenhum ficheiro válido encontrado para download automático.")
    
    # Verifica se o Vencedor já existe no disco
    try:
        find_local_file(best_candidate['filename'])
        print(f"✅ Vencedor já existe em disco: {best_candidate['filename']}")
        return {
            "status": "Already downloaded", 
            "file": best_candidate['filename'], 
            "message": "Ficheiro já disponível no servidor"
        }
    except HTTPException:
        pass

    return await download_slskd(
        best_candidate['username'], 
        best_candidate['filename'], 
        best_candidate['size']
    )

# --- NOVA ROTA: Status do Download (Simplificada) ---
@app.get("/download/status")
async def check_download_status(filename: str):
    """
    Verifica se o download está em andamento ou concluído.
    Nota: Removemos o 'username', pois a busca agora é global no Slskd.
    """
    # 1. Verifica se já está no disco (Completo)
    try:
        find_local_file(filename)
        return {
            "state": "Completed",
            "progress": 100.0,
            "speed": 0,
            "message": "Pronto para tocar"
        }
    except HTTPException:
        pass # Não achou localmente, continua para checar no Slskd

    # 2. Se não está no disco, pergunta ao Soulseek (Busca Global)
    status = await get_transfer_status(filename)
    
    if status:
        return status
    
    # 3. Se não está no disco nem na lista ativa do Slskd
    return {
        "state": "Unknown",
        "progress": 0.0,
        "message": "Não encontrado (Iniciando ou Falhou)"
    }

@app.get("/metadata")
async def get_track_details(filename: str):
    full_path = find_local_file(filename)
    return get_audio_metadata(full_path)

@app.get("/cover")
async def get_cover_art(filename: str):
    """
    Busca capa do álbum (Local ou iTunes).
    """
    full_path = find_local_file(filename)
    
    # 1. Capa Embutida
    has_embedded_art = False
    try:
        check_cmd = ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=index", "-of", "csv=p=0", full_path]
        res = subprocess.run(check_cmd, capture_output=True, text=True)
        has_embedded_art = bool(res.stdout.strip())
    except Exception:
        pass

    if has_embedded_art:
        cmd = ["ffmpeg", "-i", full_path, "-an", "-c:v", "mjpeg", "-f", "mjpeg", "-v", "error", "-"]
        def iterfile():
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=10**6)
            try:
                while True:
                    chunk = process.stdout.read(64 * 1024)
                    if not chunk: break
                    yield chunk
            finally:
                process.kill()
        return StreamingResponse(iterfile(), media_type="image/jpeg")
    
    # 2. Busca Online (iTunes)
    print(f"🖼️ Sem capa embutida para '{filename}'. Buscando no iTunes...")
    tags = get_audio_tags(full_path)
    if tags['artist'] and tags['title']:
        term = f"{tags['artist']} {tags['title']}"
    else:
        # CORREÇÃO: Usamos o nome limpo do arquivo real no disco, 
        # ignorando a bagunça de pastas do filename original.
        clean_name = os.path.splitext(os.path.basename(full_path))[0]
        term = clean_name.replace("_", " ").replace("-", " ").strip()

    try:
        async with httpx.AsyncClient() as client:
            url = "https://itunes.apple.com/search"
            params = {"term": term, "media": "music", "entity": "song", "limit": 1}
            resp = await client.get(url, params=params, timeout=5.0)
            data = resp.json()
            if data['resultCount'] > 0:
                artwork_url = data['results'][0].get('artworkUrl100')
                if artwork_url:
                    high_res_url = artwork_url.replace("100x100bb", "600x600bb")
                    return RedirectResponse(high_res_url)
    except Exception:
        pass

    raise HTTPException(status_code=404, detail="Capa não encontrada")

# --- STREAMING COM SUPORTE A RANGE (CRÍTICO PARA iOS) ---
@app.get("/stream")
async def stream_music(
    request: Request,
    filename: str, 
    quality: str = Query("lossless", enum=["low", "medium", "high", "lossless"])
):
    """
    Endpoint de Streaming inteligente:
    1. Se qualidade != lossless: Transcodifica para MP3 on-the-fly.
    2. Se qualidade == lossless:
       - Suporta HTTP Range Requests (206 Partial Content).
       - Permite que o iOS/AVPlayer faça seek e buffer corretamente.
    """
    full_path = find_local_file(filename)
    
    if quality != "lossless":
        target_bitrate = TIERS.get(quality, "128k")
        print(f"🎧 Transcoding para {quality} ({target_bitrate}): {full_path}")
        return StreamingResponse(
            transcode_audio(full_path, target_bitrate),
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
        with open(full_path, "rb") as f:
            yield from f

    return StreamingResponse(iterfile(), headers=headers)