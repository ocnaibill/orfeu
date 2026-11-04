"""Tidal (via proxy triton.squid.wtf): catálogo e download direto."""
import os

from fastapi import BackgroundTasks
from fastapi.concurrency import run_in_threadpool
from thefuzz import fuzz

from app.core import config
from app.schemas import SmartDownloadRequest
from app.services.local_library import normalize_text, register_download, download_file_background
from app.services.tidal_provider import TidalProvider


class TidalCatalog:
    name = "tidal"

    def owns_id(self, item_id) -> bool:
        return str(item_id).isdigit()

    async def search(self, query: str, type: str = "song", limit: int = 25) -> list:
        return await run_in_threadpool(TidalProvider.search_catalog, query, limit, type)

    async def artist_details(self, artist_id):
        return await run_in_threadpool(TidalProvider.get_artist_details, artist_id)

    async def album_details(self, album_id):
        return await run_in_threadpool(TidalProvider.get_album_details, album_id)


class TidalDownloader:
    name = "tidal"

    async def try_download(self, request: SmartDownloadRequest, background_tasks: BackgroundTasks):
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

        if not target_tidal_id:
            return None

        print(f"🌊 Tentando download Tidal (ID: {target_tidal_id})...")
        download_info = await run_in_threadpool(TidalProvider.get_download_url, target_tidal_id)
        if not (download_info and download_info.get('url')):
            return None

        safe_artist = normalize_text(request.artist).replace(" ", "_")
        safe_track = normalize_text(request.track).replace(" ", "_")
        safe_album = normalize_text(request.album or "single").replace(" ", "_")
        ext = "flac" if "flac" in download_info['mime'] else "m4a"

        # Filename único incluindo álbum para evitar conflitos
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
