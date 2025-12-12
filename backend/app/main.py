from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import os
import subprocess
import json
import mutagen
from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC
from app.services.slskd_client import search_slskd, get_search_results, download_slskd

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
    Localiza o arquivo no sistema de arquivos (Busca Profunda).
    """
    base_path = "/downloads"
    sanitized_filename = filename.replace("\\", "/").lstrip("/")
    target_file_name = os.path.basename(sanitized_filename)
    
    for root, dirs, files in os.walk(base_path):
        if target_file_name in files:
            return os.path.join(root, target_file_name)
            
    raise HTTPException(status_code=404, detail=f"Arquivo '{target_file_name}' não encontrado.")

def get_audio_tags(file_path: str) -> dict:
    """
    Usa Mutagen para ler tags artísticas (Título, Artista, Álbum).
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
        if not audio:
            return tags
            
        # O EasyID3/Mutagen retorna listas para os campos (ex: ['Pink Floyd'])
        # Nós pegamos o primeiro item.
        tags["title"] = audio.get("title", [None])[0]
        tags["artist"] = audio.get("artist", [None])[0]
        tags["album"] = audio.get("album", [None])[0]
        tags["genre"] = audio.get("genre", [None])[0]
        tags["date"] = audio.get("date", [None])[0] or audio.get("year", [None])[0]
        
    except Exception as e:
        print(f"⚠️ Erro ao ler tags com Mutagen: {e}")
    
    return tags

def get_audio_metadata(file_path: str) -> dict:
    """
    Combina FFmpeg (Dados Técnicos) + Mutagen (Dados Artísticos).
    """
    # 1. Dados Técnicos (FFprobe)
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
    except Exception as e:
        print(f"Erro FFprobe: {e}")

    # 2. Dados Artísticos (Mutagen)
    artistic_data = get_audio_tags(file_path)

    # 3. Fallback: Se não tiver Título na tag, usa o nome do arquivo
    if not artistic_data["title"]:
        filename_clean = os.path.splitext(os.path.basename(file_path))[0]
        artistic_data["title"] = filename_clean

    # Retorna a fusão dos dois
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
    chunk_size = 64 * 1024
    try:
        while True:
            chunk = process.stdout.read(chunk_size)
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
        raise HTTPException(status_code=404, detail="Nenhum arquivo válido encontrado para download automático.")
    
    return await download_slskd(
        best_candidate['username'], 
        best_candidate['filename'], 
        best_candidate['size']
    )

# --- Metadados e Tags (ATUALIZADO) ---
@app.get("/metadata")
async def get_track_details(filename: str):
    """
    Retorna metadados completos:
    - Artísticos (Mutagen): Título, Artista, Álbum
    - Técnicos (FFprobe): Bitrate, Frequência, Formato
    """
    full_path = find_local_file(filename)
    # Aqui, futuramente, chamaremos a função para salvar no BD:
    # update_database_with_metadata(full_path, data)
    return get_audio_metadata(full_path)

@app.get("/cover")
async def get_cover_art(filename: str):
    full_path = find_local_file(filename)
    cmd = [
        "ffmpeg", "-i", full_path, "-an", "-c:v", "mjpeg",
        "-f", "mjpeg", "-v", "error", "-"
    ]
    def iterfile():
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
    return StreamingResponse(iterfile(), media_type="image/jpeg")

@app.get("/stream")
async def stream_music(
    filename: str, 
    quality: str = Query("lossless", enum=["low", "medium", "high", "lossless"])
):
    full_path = find_local_file(filename)
    if quality == "lossless":
        print(f"🎧 Streaming Original (Lossless/Direct): {full_path}")
        def iterfile():
            with open(full_path, mode="rb") as file_like:
                yield from file_like
        media_type = "audio/flac" if full_path.lower().endswith(".flac") else "audio/mpeg"
        return StreamingResponse(iterfile(), media_type=media_type)
    
    target_bitrate = TIERS.get(quality, "128k")
    metadata = get_audio_metadata(full_path)
    original_bitrate = metadata.get('bitrate', 999999)
    target_bitrate_int = int(target_bitrate.replace('k', '')) * 1000
    
    if metadata.get('format') == 'mp3' and original_bitrate < target_bitrate_int:
         print(f"⚠️ Original < Alvo. Enviando original.")
         def iterfile():
            with open(full_path, mode="rb") as file_like:
                yield from file_like
         return StreamingResponse(iterfile(), media_type="audio/mpeg")

    print(f"🎧 Transcoding para {quality}: {full_path}")
    return StreamingResponse(transcode_audio(full_path, target_bitrate), media_type="audio/mpeg")