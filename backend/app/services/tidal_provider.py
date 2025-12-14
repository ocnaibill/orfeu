import httpx
import base64
import json

class TidalProvider:
    # APIs descobertas
    SEARCH_API = "https://katze.qqdl.site/search"
    TRACK_API = "https://triton.squid.wtf/track"
    CDN_URL = "https://resources.tidal.com/images"

    @staticmethod
    def search_catalog(query: str, limit: int = 25):
        """
        Busca faixas no catálogo do Tidal.
        """
        try:
            params = {"s": query, "limit": limit, "offset": 0}
            
            with httpx.Client() as client:
                resp = client.get(f"{TidalProvider.SEARCH_API}/", params=params, timeout=10.0)
                if resp.status_code != 200: return []
                data = resp.json()
            
            items = data.get('data', {}).get('items', [])
            normalized_results = []
            
            for item in items:
                album_cover_id = item.get('album', {}).get('cover')
                artwork_url = ""
                if album_cover_id:
                    path = album_cover_id.replace('-', '/')
                    artwork_url = f"{TidalProvider.CDN_URL}/{path}/640x640.jpg"

                artist_name = item.get('artist', {}).get('name', 'Desconhecido')
                album_name = item.get('album', {}).get('title', 'Single')
                
                normalized_results.append({
                    "type": "song",
                    "trackName": item.get('title'),
                    "artistName": artist_name,
                    "collectionName": album_name,
                    "artworkUrl": artwork_url,
                    "previewUrl": None,
                    "year": "",
                    "isLossless": item.get('audioQuality') == 'LOSSLESS',
                    "source": "Tidal",
                    # O ID É CRUCIAL PARA O DOWNLOAD
                    "tidalId": item.get('id') 
                })
            
            return normalized_results

        except Exception as e:
            print(f"❌ Erro Tidal Search: {e}")
            return []

    @staticmethod
    def get_download_url(track_id: int):
        """
        Obtém a URL direta do ficheiro FLAC decodificando o manifesto.
        """
        try:
            # Tenta HI_RES primeiro, depois LOSSLESS
            qualities = ["HI_RES_LOSSLESS", "LOSSLESS", "HIGH"]
            
            with httpx.Client() as client:
                for q in qualities:
                    params = {"id": track_id, "quality": q}
                    print(f"🌊 Tentando Tidal Direct ({q})...")
                    
                    resp = client.get(f"{TidalProvider.TRACK_API}/", params=params, timeout=10.0)
                    if resp.status_code != 200: continue
                    
                    data = resp.json()
                    manifest_b64 = data.get('data', {}).get('manifest')
                    
                    if manifest_b64:
                        # Decodifica Base64 -> JSON String -> Dict
                        decoded_json = base64.b64decode(manifest_b64).decode('utf-8')
                        manifest = json.loads(decoded_json)
                        
                        # Pega a primeira URL da lista
                        urls = manifest.get('urls', [])
                        if urls:
                            return {
                                "url": urls[0],
                                "mime": manifest.get('mimeType', 'audio/flac'),
                                "codec": manifest.get('codecs', 'flac')
                            }
            
            return None
        except Exception as e:
            print(f"❌ Erro Tidal Download: {e}")
            return None