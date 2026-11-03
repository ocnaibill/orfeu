"""Soulseek (via slskd): download P2P e as rotas legadas de busca/fila/status."""
import asyncio
import os

from fastapi import BackgroundTasks
from thefuzz import fuzz
from unidecode import unidecode

from app.schemas import SmartDownloadRequest
from app.services.audio_manager import AudioManager
from app.services.local_library import normalize_text
from app.services.slskd_client import search_slskd, get_search_results, download_slskd, get_transfer_status


class SoulseekDownloader:
    name = "soulseek"

    # --- busca automática: escolhe o melhor arquivo e baixa --------------------
    async def try_download(self, request: SmartDownloadRequest, background_tasks: BackgroundTasks):
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

        if not best_candidate:
            return None

        try:
            if AudioManager.find_local_file(best_candidate['filename']):
                 return {"status": "Already downloaded", "file": best_candidate['filename']}
        except: pass

        return await download_slskd(best_candidate['username'], best_candidate['filename'], best_candidate['size'])

    # --- API bruta do slskd (rotas legadas /search, /results, /download) --------
    async def start_search(self, query: str):
        return await search_slskd(query)

    async def search_results(self, search_id: str):
        return await get_search_results(search_id)

    async def queue_download(self, username: str, filename: str, size=None):
        return await download_slskd(username, filename, size)

    async def transfer_status(self, filename: str):
        return await get_transfer_status(filename)
