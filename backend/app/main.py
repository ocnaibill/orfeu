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
# Libs de Inteligência de Texto
from unidecode import unidecode
from thefuzz import fuzz

# Importação dos Serviços Organizados
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider

app = FastAPI(title="Orfeu API", version="1.3.1")

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
def normalize_text(text: str) -> str:
    """
    Remove acentos, coloca em minúsculas e remove caracteres especiais.
    Ex: "Rádio - Coração" -> "radio coracao"
    """
    if not text: return ""
    return unidecode(text).lower().strip()

def find_local_match(artist: str, track: str) -> Optional[str]:
    """
    Busca local usando Fuzzy Matching.
    Verifica se o arquivo existe E tem conteúdo (>0 bytes).
    """
    base_path = "/downloads"
    target_str = normalize_text(f"{artist} {track}")
    
    # Varre diretório
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                
                # Check de integridade básico (0 bytes = falha anterior)
                if os.path.getsize(full_path) == 0:
                    continue

                clean_file = normalize_text(file)
                # Se a similaridade for muito alta (>90), consideramos que é a mesma música
                ratio = fuzz.partial_token_sort_ratio(target_str, clean_file)
                if ratio > 90:
                    return full_path
    return None

# --- Rotas de Sistema ---
@app.get("/")
def read_root():
    return {"status": "Orfeu is alive", "service": "Backend", "version": "1.3.1"}

# --- NOVA FUNCIONALIDADE: BUSCA CURADA (ITUNES) COM PAGINAÇÃO ---
@app.get("/search/catalog")
async def search_catalog(
    query: str, 
    limit: int = 20, 
    offset: int = 0
):
    """
    Busca no catálogo global (iTunes).
    Suporta paginação (limit/offset) e busca por trechos de letra (implícito).
    """
    print(f"🔎 Buscando no catálogo: '{query}' (Offset: {offset}, Limit: {limit})")
    try:
        async with httpx.AsyncClient() as client:
            url = "https://itunes.apple.com/search"
            
            params = {
                "term": query,
                "media": "music",
                "limit": limit,
                "offset": offset,
            }
            
            resp = await client.get(url, params=params, timeout=10.0)
            data = resp.json()
            
            results = []
            
            for item in data.get('results', []):
                if item.get('kind') != 'song':
                    continue

                artwork = item.get('artworkUrl100', '').replace("100x100bb", "600x600bb")
                artist = item.get('artistName', '')
                track = item.get('trackName', '')
                
                local_file = find_local_match(artist, track)
                
                results.append({
                    "trackName": track,
                    "artistName": artist,
                    "collectionName": item.get('collectionName'),
                    "artworkUrl": artwork,
                    "previewUrl": item.get('previewUrl'),
                    "year": item.get('releaseDate', '')[:4],
                    "isDownloaded": local_file is not None,
                    "filename": local_file
                })
            
            return results
    except Exception as e:
        print(f"❌ Erro no catálogo: {e}")
        return []

# --- SMART DOWNLOAD COM FUZZY MATCHING ---
@app.post("/download/smart")
async def smart_download(request: SmartDownloadRequest):
    """
    Fluxo otimizado com unidecode e FuzzyWuzzy para tolerar erros de digitação e acentos.
    Inclui verificação robusta de arquivo local.
    """
    # Normaliza a busca para o Soulseek
    search_term = unidecode(f"{request.artist} {request.track}")
    print(f"🤖 Smart Download (Fuzzy): {search_term}")
    
    # 0. Check LOCAL antes de tudo (Com Fuzzy e Validação de Tamanho)
    local_match = find_local_match(request.artist, request.track)
    if local_match:
        print(f"✅ Smart Match Local: {local_match}")
        return {
            "status": "Already downloaded", 
            "file": local_match,
            "display_name": request.track,
            "message": "Música já disponível no cache."
        }

    # 1. Inicia busca P2P
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
        
        if i % 3 == 0 or peer_count > 0:
            print(f"   Check {i+1}/22: {peer_count} peers.")

        # Saída Antecipada
        has_perfect_candidate = best_candidate and best_candidate['score'] > 50000
        if peer_count > 15 and has_perfect_candidate:
             print(f"⚡ Candidato perfeito encontrado. Encerrando.")
             break

        for response in raw_results:
            if response.get('locked', False): continue
            
            slots_free = response.get('slotsFree', False)
            queue_length = response.get('queueLength', 0)
            upload_speed = response.get('uploadSpeed', 0)

            if 'files' in response:
                for file in response['files']:
                    filename = file['filename']
                    
                    # --- FILTRO INTELIGENTE (FUZZY MATCHING) ---
                    file_basename = os.path.basename(filename.replace("\\", "/"))
                    remote_clean = normalize_text(file_basename)
                    
                    similarity = fuzz.partial_token_sort_ratio(target_clean, remote_clean)
                    
                    if similarity < 85:
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

    print(f"🏆 Vencedor Fuzzy: {best_candidate['filename']} (Score: {int(best_candidate['score'])})")

    # 3. Verifica se o VENCEDOR P2P já existe no disco (Proteção contra re-download)
    # Aqui verificamos o arquivo EXATO que vamos pedir, para garantir.
    try:
        local_path = AudioManager.find_local_file(best_candidate['filename'])
        
        # Verifica integridade (0 bytes = falha)
        if os.path.getsize(local_path) > 0:
            print(f"✅ Vencedor já existe em disco (Skip): {local_path}")
            return {
                "status": "Already downloaded", 
                "file": best_candidate['filename'],
                "display_name": request.track,
                "message": "Ficheiro já disponível."
            }
        else:
            print(f"⚠️ Arquivo existe mas tem 0 bytes (Lixo). Baixando novamente: {local_path}")
            os.remove(local_path) 
    except HTTPException:
        # Não existe, pode baixar
        pass
    except Exception as e:
        print(f"⚠️ Erro ao verificar arquivo local: {e}")

    # 4. Inicia Download
    return await download_slskd(
        best_candidate['username'], 
        best_candidate['filename'], 
        best_candidate['size']
    )

# --- Rotas Legadas ---
@app.post("/search/{query}")
async def start_search_legacy(query: str):
    return await search_slskd(query)

@app.get("/results/{search_id}")
async def view_results(search_id: str):
    return await get_search_results(search_id) 

@app.post("/download")
async def queue_download(request: DownloadRequest):
    try:
        path = AudioManager.find_local_file(request.filename)
        # Check de 0 bytes também no download manual
        if os.path.getsize(path) > 0:
             return {"status": "Already downloaded", "file": request.filename}
        else:
             os.remove(path)
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
    # Mantém compatibilidade
    return await smart_download(SmartDownloadRequest(artist="", track="")) 

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
        if AudioManager.extract_cover_stream(full_path): 
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