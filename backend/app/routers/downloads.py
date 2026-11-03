from fastapi import APIRouter, HTTPException, BackgroundTasks, Depends
import os
import asyncio
from fastapi.concurrency import run_in_threadpool
from unidecode import unidecode
from thefuzz import fuzz

from app.core import config
from app.deps import get_current_user
from app.schemas import DownloadRequest, AutoDownloadRequest, SmartDownloadRequest
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status
from app.services.audio_manager import AudioManager
from app.services.tidal_provider import TidalProvider
from app.services.local_library import normalize_text, find_local_match, register_download, download_file_background

router = APIRouter(tags=["downloads"])

@router.post("/download/smart", dependencies=[Depends(get_current_user)])
async def smart_download(request: SmartDownloadRequest, background_tasks: BackgroundTasks):
    print(f"🤖 Smart Download: {request.artist} - {request.track}")
    
    # Primeiro verifica pelo tidal_id (mais preciso) se disponível
    local_match = find_local_match(
        artist=request.artist, 
        track=request.track,
        album=request.album,
        tidal_id=request.tidalId
    )
    if local_match:
        print(f"✅ Cache Local: {local_match}")
        return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

    # 1. Tidal Direct
    target_tidal_id = request.tidalId
    
    # Se veio sem ID (YTMusic ou outra fonte), tenta achar no Tidal agora
    if not target_tidal_id:
        print(f"🔍 Sem Tidal ID, buscando no Tidal: '{request.artist} {request.track}'")
        try:
            search_query = f"{request.artist} {request.track}"
            tidal_results = await run_in_threadpool(TidalProvider.search_catalog, search_query, 5, "song")
            
            if tidal_results:
                print(f"   📋 Tidal retornou {len(tidal_results)} resultados")
                
                # Encontra o melhor match
                target_clean = normalize_text(f"{request.artist} {request.track}")
                best_match = None
                best_score = 0
                
                for result in tidal_results:
                    result_clean = normalize_text(f"{result['artistName']} {result['trackName']}")
                    score = fuzz.token_set_ratio(target_clean, result_clean)
                    print(f"      -> '{result['artistName']} - {result['trackName']}' = {score}%")
                    
                    if score > best_score:
                        best_score = score
                        best_match = result
                
                # Threshold de 75% para aceitar o match
                if best_match and best_score >= 75:
                    target_tidal_id = best_match.get('tidalId')
                    if not request.artworkUrl:
                        request.artworkUrl = best_match.get('artworkUrl')
                    if not request.album:
                        request.album = best_match.get('collectionName')
                    print(f"   ✅ Tidal ID recuperado: {target_tidal_id} (score: {best_score}%)")
                else:
                    print(f"   ⚠️ Nenhum match bom o suficiente (melhor: {best_score}%)")
            else:
                print(f"   ⚠️ Tidal não retornou resultados")
                
        except Exception as e:
            print(f"   ❌ Erro buscando no Tidal: {e}")

    if target_tidal_id:
        print(f"🌊 Tentando download Tidal (ID: {target_tidal_id})...")
        download_info = await run_in_threadpool(TidalProvider.get_download_url, target_tidal_id)
        if download_info and download_info.get('url'):
            safe_artist = normalize_text(request.artist).replace(" ", "_")
            safe_track = normalize_text(request.track).replace(" ", "_")
            safe_album = normalize_text(request.album or "single").replace(" ", "_")
            ext = "flac" if "flac" in download_info['mime'] else "m4a"
            
            # CORREÇÃO: Filename único incluindo álbum para evitar conflitos
            # Formato: Tidal/artista/album/track.flac OU Tidal/artista/track_tidalId.flac
            if request.album:
                relative_path = os.path.join("Tidal", safe_artist, safe_album, f"{safe_track}.{ext}")
            else:
                # Sem álbum, usa tidal_id para garantir unicidade
                relative_path = os.path.join("Tidal", safe_artist, f"{safe_track}_{target_tidal_id}.{ext}")
            
            full_path = os.path.join(config.MUSIC_DIR, relative_path)
            
            meta = {"title": request.track, "artist": request.artist, "album": request.album or "Single"}
            
            # Registra o download ANTES de iniciar (para evitar downloads duplicados)
            register_download(
                tidal_id=target_tidal_id,
                title=request.track,
                artist=request.artist,
                album=request.album,
                local_path=relative_path,
                source="Tidal"
            )
            
            background_tasks.add_task(download_file_background, download_info['url'], full_path, meta, request.artworkUrl)
            return {"status": "Download started", "file": relative_path, "source": "Tidal", "tidalId": target_tidal_id}

    # 2. Soulseek
    search_term = unidecode(f"{request.artist} {request.track}")
    init_resp = await search_slskd(search_term)
    search_id = init_resp['search_id']
    
    print("⏳ Buscando no Soulseek...")
    best_candidate = None
    highest_score = float('-inf')
    target_clean = normalize_text(f"{request.artist} {request.track}")
    
    last_peer_count = -1
    stable_checks = 0

    for i in range(22):
        await asyncio.sleep(2.0) 
        raw_results = await get_search_results(search_id)
        peer_count = len(raw_results)
        
        if peer_count > 0 and peer_count == last_peer_count: stable_checks += 1
        else: stable_checks = 0
        last_peer_count = peer_count

        if i % 3 == 0: print(f"   Check {i+1}/22: {peer_count} peers.")

        # Saída Antecipada
        if best_candidate and best_candidate['score'] > 50000:
             if peer_count > 15: break # Perfect match (Free Slot)

        if stable_checks >= 4 and peer_count > 0 and best_candidate:
             break # Estabilizou

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

                    if request.album:
                         if fuzz.partial_ratio(normalize_text(request.album), normalize_text(fname)) > 85:
                             score += 5000

                    if score > highest_score:
                        highest_score = score
                        best_candidate = {'username': response.get('username'), 'filename': fname, 'size': file['size'], 'score': score}
    
    if not best_candidate: raise HTTPException(404, "Nenhum ficheiro encontrado.")
    
    try:
        if AudioManager.find_local_file(best_candidate['filename']):
             return {"status": "Already downloaded", "file": best_candidate['filename']}
    except: pass

    return await download_slskd(best_candidate['username'], best_candidate['filename'], best_candidate['size'])

@router.post("/search/{query}", dependencies=[Depends(get_current_user)])
async def start_search_legacy(query: str): return await search_slskd(query)

@router.get("/results/{search_id}", dependencies=[Depends(get_current_user)])
async def view_results(search_id: str): return await get_search_results(search_id) 

@router.post("/download", dependencies=[Depends(get_current_user)])
async def queue_download(request: DownloadRequest):
    try:
        path = AudioManager.find_local_file(request.filename)
        if os.path.getsize(path) > 0: return {"status": "Already downloaded", "file": request.filename}
        else: os.remove(path)
    except HTTPException: pass
    return await download_slskd(request.username, request.filename, request.size)

@router.get("/download/status", dependencies=[Depends(get_current_user)])
async def check_download_status(filename: str):
    try:
        path = AudioManager.find_local_file(filename)
        size = os.path.getsize(path)
        if "Tidal" in path and size > 1000000:
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Tidal Download"}
        if size > 0 and "Tidal" not in path: 
             return {"state": "Completed", "progress": 100.0, "speed": 0, "message": "Pronto"}
    except HTTPException: pass
    status = await get_transfer_status(filename)
    if status: return status
    return {"state": "Unknown", "progress": 0.0, "message": "Iniciando"}

@router.post("/download/auto", dependencies=[Depends(get_current_user)])
async def auto_download_best(request: AutoDownloadRequest):
    return await smart_download(SmartDownloadRequest(artist="", track="")) 
