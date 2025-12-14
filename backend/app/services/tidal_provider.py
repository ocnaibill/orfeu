import httpx

class TidalProvider:
    # API descoberta por engenharia reversa do frontend
    BASE_API = "https://katze.qqdl.site"
    CDN_URL = "https://resources.tidal.com/images"

    @staticmethod
    def search_catalog(query: str, limit: int = 25):
        """
        Busca faixas usando o proxy do Tidal.
        Retorna lista normalizada para o Orfeu.
        """
        try:
            url = f"{TidalProvider.BASE_API}/search/"
            params = {
                "s": query,
                "limit": limit,
                # offset parece funcionar nesta API se precisarmos no futuro
                "offset": 0 
            }
            
            # Usamos cliente síncrono para ser compatível com run_in_threadpool do main.py
            with httpx.Client() as client:
                resp = client.get(url, params=params, timeout=10.0)
                if resp.status_code != 200:
                    return []
                
                data = resp.json()
            
            # Navega no JSON: { version: "2.0", data: { items: [...] } }
            items = data.get('data', {}).get('items', [])
            normalized_results = []
            
            for item in items:
                # O Tidal retorna a capa como um UUID (ex: f56a738d-d61e...)
                # A URL real substitui '-' por '/'
                album_cover_id = item.get('album', {}).get('cover')
                artwork_url = ""
                
                if album_cover_id:
                    path = album_cover_id.replace('-', '/')
                    # Resoluções disponíveis: 80x80, 160x160, 320x320, 640x640, 1280x1280
                    artwork_url = f"{TidalProvider.CDN_URL}/{path}/640x640.jpg"

                artist_name = item.get('artist', {}).get('name', 'Desconhecido')
                album_name = item.get('album', {}).get('title', 'Single')
                
                normalized_results.append({
                    "type": "song",
                    "trackName": item.get('title'),
                    "artistName": artist_name,
                    "collectionName": album_name,
                    "artworkUrl": artwork_url,
                    "previewUrl": None, # Tidal não expõe preview mp3 público facilmente
                    "year": "", # A busca simples não retorna ano, mas não é crítico
                    "isLossless": item.get('audioQuality') == 'LOSSLESS',
                    "source": "Tidal"
                })
            
            return normalized_results

        except Exception as e:
            print(f"❌ Erro Tidal Provider: {e}")
            return []