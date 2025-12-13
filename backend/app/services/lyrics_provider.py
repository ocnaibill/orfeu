import httpx
import os
from .audio_manager import AudioManager

class LyricsProvider:
    
    @staticmethod
    async def get_lyrics(file_path: str):
        meta = AudioManager.get_audio_metadata(file_path)
        artist = meta.get('artist')
        title = meta.get('title')
        duration = meta.get('duration')

        if not artist or not title:
            return None # Impossível buscar

        print(f"🎤 Buscando letras para: {artist} - {title}")

        async with httpx.AsyncClient() as client:
            try:
                # 1. Busca exata
                params = {"artist_name": artist, "track_name": title}
                if duration: params["duration"] = int(duration)

                resp = await client.get("https://lrclib.net/api/get", params=params, timeout=5.0)
                
                # 2. Busca aproximada (Fallback)
                if resp.status_code == 404:
                    search_params = {"q": f"{artist} {title}"}
                    search_resp = await client.get("https://lrclib.net/api/search", params=search_params, timeout=5.0)
                    if search_resp.status_code == 200 and search_resp.json():
                        return search_resp.json()[0]
                elif resp.status_code == 200:
                    return resp.json()
            except Exception as e:
                print(f"Erro Lyrics: {e}")
        
        return None

    @staticmethod
    async def get_online_cover(file_path: str):
        tags = AudioManager.get_audio_tags(file_path)
        
        if tags['artist'] and tags['title']:
            term = f"{tags['artist']} {tags['title']}"
        else:
            clean_name = os.path.splitext(os.path.basename(file_path))[0]
            term = clean_name.replace("_", " ").replace("-", " ").strip()

        print(f"🖼️ Buscando capa no iTunes para: {term}")
        
        try:
            async with httpx.AsyncClient() as client:
                url = "https://itunes.apple.com/search"
                params = {"term": term, "media": "music", "entity": "song", "limit": 1}
                resp = await client.get(url, params=params, timeout=5.0)
                data = resp.json()
                if data['resultCount'] > 0:
                    artwork_url = data['results'][0].get('artworkUrl100')
                    if artwork_url:
                        return artwork_url.replace("100x100bb", "600x600bb")
        except Exception:
            pass
        
        return None