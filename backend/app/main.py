from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, Dict, List
import os
import subprocess
import json
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
    
    # 1. Tenta caminho direto (se o usuario enviou o caminho relativo correto)
    # Precisamos varrer porque não sabemos a estrutura exata que o slskd criou
    for root, dirs, files in os.walk(base_path):
        if target_file_name in files:
            return os.path.join(root, target_file_name)
            
    raise HTTPException(status_code=404, detail=f"Arquivo '{target_file_name}' não encontrado.")

def get_audio_metadata(file_path: str) -> dict:
    """
    Usa ffprobe para extrair detalhes técnicos do arquivo (Bitrate, Sample Rate, Bit Depth).
    """
    try:
        cmd = [
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            file_path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        data = json.loads(result.stdout)
        
        audio_stream = next((s for s in data.get('streams', []) if s['codec_type'] == 'audio'), None)
        format_info = data.get('format', {})
        
        if not audio_stream:
            return {"error": "No audio stream found"}

        # Detecta tier original
        codec = audio_stream.get('codec_name', 'unknown')
        bit_rate = int(format_info.get('bit_rate', 0))
        
        # Lógica visual para o Frontend
        tech_label = f"{audio_stream.get('sample_rate', '')}Hz"
        
        # FLAC geralmente tem bits_per_sample ou sample_fmt
        bits = audio_stream.get('bits_per_raw_sample') or audio_stream.get('bits_per_sample')
        if bits:
             tech_label = f"{bits}bit/{tech_label}"
        
        return {
            "filename": os.path.basename(file_path),
            "format": codec,
            "bitrate": bit_rate,
            "sample_rate": int(audio_stream.get('sample_rate', 0)),
            "channels": audio_stream.get('channels'),
            "duration": float(format_info.get('duration', 0)),
            "tech_label": tech_label, # Ex: "24bit/96000Hz" ou "44100Hz"
            "is_lossless": codec in ['flac', 'wav', 'alac']
        }
    except Exception as e:
        print(f"Erro ao ler metadados: {e}")
        return {"error": str(e)}

def transcode_audio(file_path: str, bitrate: str):
    """
    Gera um stream de áudio transcodificado para MP3 usando FFmpeg.
    """
    cmd = [
        "ffmpeg",
        "-i", file_path,
        "-f", "mp3",           # Força saída MP3
        "-ab", bitrate,        # Bitrate (ex: 128k, 320k)
        "-vn",                 # Ignora vídeo (capas de álbum embutidas)
        "-map", "0:a:0",       # Pega apenas o primeiro stream de áudio
        "-"                    # Saída para STDOUT (pipe)
    ]
    
    # Abre o processo
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, # Ignora logs do ffmpeg para não sujar
        bufsize=10**6 # Buffer de 1MB
    )
    
    # Lê chunks do stdout e envia
    chunk_size = 64 * 1024 # 64KB chunks
    try:
        while True:
            chunk = process.stdout.read(chunk_size)
            if not chunk:
                break
            yield chunk
    finally:
        process.kill()

# --- Rotas ---

@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend"}

# --- Busca ---
@app.post("/search/{query}")
async def start_search(query: str):
    return await search_slskd(query)

# --- Resultados ---
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

# --- Download Manual ---
@app.post("/download")
async def queue_download(request: DownloadRequest):
    return await download_slskd(request.username, request.filename, request.size)

# --- Download Automático ---
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

# --- Metadados (Informações Técnicas) ---
@app.get("/metadata")
async def get_track_details(filename: str):
    """
    Retorna detalhes técnicos do arquivo (Bitrate, Sample Rate, se é FLAC real, etc).
    Útil para mostrar na UI "24bit/96kHz".
    """
    full_path = find_local_file(filename)
    return get_audio_metadata(full_path)

# --- Capa do Álbum (Cover Art) ---
@app.get("/cover")
async def get_cover_art(filename: str):
    """
    Extrai a capa do álbum (embedded art) do arquivo de áudio e retorna como JPEG.
    """
    full_path = find_local_file(filename)
    
    # FFmpeg command to extract raw MJPEG stream
    # -c:v mjpeg garante que o output seja JPEG mesmo que a fonte seja PNG
    cmd = [
        "ffmpeg",
        "-i", full_path,
        "-an",           # No audio
        "-c:v", "mjpeg", # Ensure JPEG output
        "-f", "mjpeg",   # Container format
        "-v", "error",   # Quiet
        "-"              # Stdout
    ]
    
    def iterfile():
        # Usamos Popen como context manager para garantir limpeza
        process = subprocess.Popen(
            cmd, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.DEVNULL,
            bufsize=10**6
        )
        try:
            while True:
                chunk = process.stdout.read(64 * 1024)
                if not chunk:
                    break
                yield chunk
        finally:
            process.kill()

    return StreamingResponse(iterfile(), media_type="image/jpeg")

# --- Streaming com Transcoding ---
@app.get("/stream")
async def stream_music(
    filename: str, 
    quality: str = Query("lossless", enum=["low", "medium", "high", "lossless"])
):
    """
    Faz o streaming.
    - quality='lossless': Envia o arquivo original (FLAC/MP3).
    - quality='high': MP3 320k.
    - quality='medium': MP3 192k.
    - quality='low': MP3 128k.
    """
    full_path = find_local_file(filename)
    
    # Se o usuário pedir Lossless, entregamos o arquivo bruto
    if quality == "lossless":
        print(f"🎧 Streaming Original (Lossless/Direct): {full_path}")
        def iterfile():
            with open(full_path, mode="rb") as file_like:
                yield from file_like
        
        media_type = "audio/flac" if full_path.lower().endswith(".flac") else "audio/mpeg"
        return StreamingResponse(iterfile(), media_type=media_type)
    
    # Se pedir Transcoding
    target_bitrate = TIERS.get(quality, "128k")
    
    # Verificação inteligente: Não fazer "Upscale" de MP3 ruim
    # Se o arquivo original já for MP3 e tiver bitrate menor que o alvo, mandamos o original
    metadata = get_audio_metadata(full_path)
    original_bitrate = metadata.get('bitrate', 999999) # Default alto para FLAC
    
    # Converter '128k' string para 128000 int
    target_bitrate_int = int(target_bitrate.replace('k', '')) * 1000
    
    if metadata.get('format') == 'mp3' and original_bitrate < target_bitrate_int:
         print(f"⚠️ O arquivo original é pior que a qualidade pedida ({original_bitrate} < {target_bitrate_int}). Enviando original.")
         def iterfile():
            with open(full_path, mode="rb") as file_like:
                yield from file_like
         return StreamingResponse(iterfile(), media_type="audio/mpeg")

    print(f"🎧 Transcoding para {quality} ({target_bitrate}): {full_path}")
    
    # Inicia o FFmpeg via pipe
    return StreamingResponse(
        transcode_audio(full_path, target_bitrate),
        media_type="audio/mpeg"
    )