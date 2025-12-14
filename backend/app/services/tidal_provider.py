import httpx
import base64
import json

class TidalProvider:
    # Nova API descoberta (mais completa)
    BASE_API = "https://triton.squid.wtf"
    CDN_URL = "https://resources.tidal.com/images"

    @staticmethod
    def search_catalog(query: str, limit: int = 25, type: str = "song"):
        """
        Busca no catálogo do Tidal usando filtros específicos.
        type: 'song' (s), 'album' (al), 'artist' (a), 'playlist' (p)
        """
        try:
            url = f"{TidalProvider.BASE_API}/search/"
            
            # Mapeia o nosso tipo interno para o parâmetro da API
            # song -> s, album -> al
            param_key = "s"
            if type == "album":
                param_key = "al"
            elif type == "artist":
                param_key = "a"
                
            params = {
                param_key: query,
                "limit": limit,
                "offset": 0 
            }
            
            with httpx.Client() as client:
                # Headers básicos para simular navegador podem ajudar
                headers = {"User-Agent": "Mozilla/5.0"}
                resp = client.get(url, params=params, headers=headers, timeout=10.0)
                
                if resp.status_code != 200:
                    print(f"⚠️ Tidal API Error: {resp.status_code}")
                    return []
                
                data = resp.json()
            
            # A estrutura de resposta varia levemente? Geralmente data.items
            items = data.get('data', {}).get('items', [])
            normalized_results = []
            
            for item in items:
                # Capa (Album Cover)
                # Se for busca de álbum, a capa está na raiz do item, não dentro de 'album'
                album_cover_id = None
                if type == "album":
                    album_cover_id = item.get('cover')
                else:
                    album_cover_id = item.get('album', {}).get('cover')

                artwork_url = ""
                if album_cover_id:
                    path = album_cover_id.replace('-', '/')
                    artwork_url = f"{TidalProvider.CDN_URL}/{path}/640x640.jpg"

                artist_name = "Desconhecido"
                # Artista pode vir como objeto ou lista
                if item.get('artist'):
                    artist_name = item['artist'].get('name')
                elif item.get('artists'):
                    artist_name = item['artists'][0].get('name')

                # Normalização baseada no tipo
                if type == "song":
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
                        "tidalId": item.get('id') 
                    })
                
                elif type == "album":
                    normalized_results.append({
                        "type": "album",
                        "collectionId": item.get('id'), # ID do Álbum
                        "collectionName": item.get('title'),
                        "artistName": artist_name,
                        "artworkUrl": artwork_url,
                        "year": str(item.get('releaseDate', ''))[:4], # Tidal costuma ter releaseDate
                        "trackCount": item.get('numberOfTracks'),
                        "source": "Tidal"
                    })
            
            return normalized_results

        except Exception as e:
            print(f"❌ Erro Tidal Search: {e}")
            return []

    @staticmethod
    def get_download_url(track_id: int):
        """
        Obtém a URL direta do ficheiro FLAC decodificando o manifesto.
        Endpoint: /track/?id=...&quality=...
        """
        try:
            qualities = ["HI_RES_LOSSLESS", "LOSSLESS", "HIGH"]
            
            with httpx.Client() as client:
                for q in qualities:
                    params = {"id": track_id, "quality": q}
                    url = f"{TidalProvider.BASE_API}/track/"
                    
                    resp = client.get(url, params=params, timeout=10.0)
                    if resp.status_code != 200: continue
                    
                    data = resp.json()
                    manifest_b64 = data.get('data', {}).get('manifest')
                    
                    if manifest_b64:
                        decoded_json = base64.b64decode(manifest_b64).decode('utf-8')
                        manifest = json.loads(decoded_json)
                        
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

    # NOVO: Método para detalhes do álbum (se descobrirmos a rota certa)
    # Baseado na sua descoberta, talvez seja /album/?id=... ou /info/?id=...
    # Por enquanto, deixamos em aberto ou usamos YTMusic para o conteúdo do álbum