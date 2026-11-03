from fastapi import APIRouter, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse, RedirectResponse, FileResponse
import os
import time
from urllib.parse import quote

from app.core import config
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.cover_proxy import SHORT_URL_MAP, get_short_cover_url

router = APIRouter(tags=["media"])

@router.get("/downloads/{filename:path}")
async def download_file_with_headers(filename: str):
    """
    Serve arquivos de download com headers corretos.
    APK files need explicit Content-Type and Content-Disposition to prevent
    browsers from adding .zip extension.
    """
    file_path = AudioManager._safe_join(config.PUBLIC_DIR, filename)

    if not file_path or not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    
    # Detecta content-type pelo nome do arquivo
    content_type = "application/octet-stream"
    if filename.endswith(".apk"):
        content_type = "application/vnd.android.package-archive"
    elif filename.endswith(".exe"):
        content_type = "application/x-msdownload"
    elif filename.endswith(".zip"):
        content_type = "application/zip"
    elif filename.endswith(".dmg"):
        content_type = "application/x-apple-diskimage"
    
    # Extrai apenas o nome do arquivo para o Content-Disposition
    base_filename = os.path.basename(filename)
    
    return FileResponse(
        file_path,
        media_type=content_type,
        filename=base_filename,
        headers={
            "Content-Disposition": f'attachment; filename="{base_filename}"',
            "Cache-Control": "no-cache"
        }
    )

@router.get("/cover/short/{hash_id}")
async def proxy_cover_art(hash_id: str):
    item = SHORT_URL_MAP.get(hash_id)
    if not item: raise HTTPException(404, "Cover hash inválido.")
    if time.time() > item["expires"]:
        del SHORT_URL_MAP[hash_id]
        raise HTTPException(404, "Cover hash expirado.")
    filename = item["filename"]
    return RedirectResponse(f"/cover?filename={quote(filename)}", status_code=302)

@router.get("/metadata")
async def get_track_details(filename: str):
    full_path = AudioManager.find_local_file(filename)
    meta = AudioManager.get_audio_metadata(full_path)
    meta['coverProxyUrl'] = get_short_cover_url(filename) # PROXY PÚBLICO
    return meta

@router.get("/cover")
async def get_cover_art(filename: str):
    full_path = AudioManager.find_local_file(filename)
    try:
        if AudioManager.extract_cover_stream(full_path): 
             return StreamingResponse(AudioManager.extract_cover_stream(full_path), media_type="image/jpeg")
    except: pass
    url = await LyricsProvider.get_online_cover(full_path)
    if url: return RedirectResponse(url)
    raise HTTPException(404, "Capa não encontrada")

_AUDIO_CONTENT_TYPES = {
    ".flac": "audio/flac", ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac",
    ".ogg": "audio/ogg", ".opus": "audio/ogg", ".wav": "audio/wav",
}

def _audio_content_type(path: str) -> str:
    return _AUDIO_CONTENT_TYPES.get(os.path.splitext(path)[1].lower(), "application/octet-stream")

def _parse_byte_range(header: str, file_size: int):
    """Interpreta 'bytes=a-b', 'bytes=a-' ou 'bytes=-n'. Devolve (start, end) inclusivos.

    Levanta ValueError se o header for malformado ou pedir vários ranges.
    Se start >= file_size o chamador responde 416.
    """
    unit, sep, spec = header.partition("=")
    if not sep or unit.strip().lower() != "bytes" or "," in spec:
        raise ValueError("range inválido")
    start_s, dash, end_s = spec.strip().partition("-")
    if not dash:
        raise ValueError("range inválido")
    if start_s == "":  # sufixo: últimos N bytes
        n = int(end_s)
        if n <= 0:
            raise ValueError("range inválido")
        return max(file_size - n, 0), file_size - 1
    start = int(start_s)
    end = int(end_s) if end_s else file_size - 1
    if start < 0 or (end_s and end < start):
        raise ValueError("range inválido")
    return start, min(end, file_size - 1)

def _iter_file_range(path: str, start: int, length: int, chunk: int = 64 * 1024):
    """Lê o trecho em pedaços, sem carregar o range inteiro na memória."""
    with open(path, "rb") as f:
        f.seek(start)
        remaining = length
        while remaining > 0:
            data = f.read(min(chunk, remaining))
            if not data:
                break
            remaining -= len(data)
            yield data

@router.get("/stream")
async def stream_music(request: Request, filename: str, quality: str = Query("lossless")):
    full_path = AudioManager.find_local_file(filename)
    print(f"🎵 Stream: '{filename}' -> '{full_path}'")  # Debug log
    if quality != "lossless":
        return StreamingResponse(AudioManager.transcode_stream(full_path, quality), media_type="audio/mpeg")
    
    file_size = os.path.getsize(full_path)
    content_type = _audio_content_type(full_path)
    range_header = request.headers.get("range")
    if range_header:
        try:
            start, end = _parse_byte_range(range_header, file_size)
        except ValueError:
            start = None  # Range malformado ou multi-range: ignora e serve o arquivo todo (RFC 9110)
        if start is not None:
            if start >= file_size:
                return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
            chunk_size = (end - start) + 1
            headers = {"Content-Range": f"bytes {start}-{end}/{file_size}", "Accept-Ranges": "bytes", "Content-Length": str(chunk_size), "Content-Type": content_type}
            return StreamingResponse(_iter_file_range(full_path, start, chunk_size), status_code=206, headers=headers)

    headers = {"Content-Length": str(file_size), "Accept-Ranges": "bytes", "Content-Type": content_type}
    def iterfile():
        with open(full_path, "rb") as f: yield from f
    return StreamingResponse(iterfile(), headers=headers)
