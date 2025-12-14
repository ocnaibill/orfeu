import httpx
import base64
import json

class TidalProvider:
    # Nova API descoberta
    BASE_API = "https://triton.squid.wtf"
    CDN_URL = "https://resources.tidal.com/images"

    @staticmethod
    def search_catalog(query: str, limit: int = 25, type: str = "song"):
        try:
            url = f"{TidalProvider.BASE_API}/search/"
            param_key = "al" if type == "album" else "s"
            
            params = {
                param_key: query,
                "limit": limit,
                "offset": 0 
            }
            
            with httpx.Client() as client:
                headers = {"User-Agent": "Mozilla/5.0"}
                resp = client.get(url, params=params, headers=headers, timeout=10.0)
                if resp.status_code != 200: return []
                data = resp.json()
            
            items = data.get('data', {}).get('items', [])
            normalized_results = []
            
            for item in items:
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
                if item.get('artist'): artist_name = item['artist'].get('name')
                elif item.get('artists'): artist_name = item['artists'][0].get('name')

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
                        "collectionId": str(item.get('id')), # Converte para string para uniformizar
                        "collectionName": item.get('title'),
                        "artistName": artist_name,
                        "artworkUrl": artwork_url,
                        "year": str(item.get('releaseDate', ''))[:4],
                        "trackCount": item.get('numberOfTracks'),
                        "source": "Tidal"
                    })
            
            return normalized_results
        except Exception as e:
            print(f"❌ Erro Tidal Search: {e}")
            return []

    @staticmethod
    def get_download_url(track_id: int):
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

    @staticmethod
    def get_album_details(collection_id: str):
        """
        Busca faixas de um álbum no Tidal.
        Tenta endpoint /album/items (padrão comum nessas APIs).
        """
        try:
            # 1. Busca metadados do álbum (opcional se já tivermos, mas bom para garantir)
            # 2. Busca Tracks
            # Nota: Estamos "chutando" o endpoint /album/items baseado no padrão /search
            url = f"{TidalProvider.BASE_API}/album/items" 
            params = {"id": collection_id, "limit": 100, "offset": 0}
            
            # Se falhar, tentamos só /album/
            
            with httpx.Client() as client:
                # Tenta pegar as tracks
                resp = client.get(url, params=params, timeout=10.0)
                
                # Fallback: se /items não existir, tenta rota raiz ou info
                if resp.status_code != 200:
                     print(f"⚠️ Tidal Album Items falhou ({resp.status_code}), tentando rota alternativa...")
                     # Tenta rota alternativa (sem /items)
                     url_alt = f"{TidalProvider.BASE_API}/album/"
                     resp = client.get(url_alt, params={"id": collection_id}, timeout=10.0)
                
                if resp.status_code != 200:
                    raise Exception(f"Album not found (HTTP {resp.status_code})")

                data = resp.json()
                
            # Parse dos itens (faixas)
            # A estrutura deve ser data.items ou data.data.items
            items = data.get('data', {}).get('items', [])
            if not items and 'items' in data: items = data['items'] # Tenta raiz

            tracks = []
            
            # Precisamos de dados do álbum para preencher (Capa, Artista, Nome)
            # Pegamos do primeiro item ou passamos vazio se a API não retornar no header
            album_meta_cache = {}
            if items:
                first = items[0]
                album_obj = first.get('album', {})
                album_meta_cache['title'] = album_obj.get('title', 'Álbum')
                
                cover_id = album_obj.get('cover')
                if cover_id:
                     album_meta_cache['artwork'] = f"{TidalProvider.CDN_URL}/{cover_id.replace('-', '/')}/640x640.jpg"
                else:
                     album_meta_cache['artwork'] = ""

            for item in items:
                # Dados da faixa
                track_title = item.get('title')
                track_id = item.get('id')
                track_num = item.get('trackNumber', 0)
                duration = item.get('duration', 0) * 1000 # seg -> ms
                
                artist_name = "Vários"
                if item.get('artist'): artist_name = item['artist'].get('name')

                tracks.append({
                    "trackNumber": track_num,
                    "trackName": track_title,
                    "artistName": artist_name,
                    "collectionName": album_meta_cache.get('title'),
                    "durationMs": duration,
                    "previewUrl": None,
                    "artworkUrl": album_meta_cache.get('artwork'),
                    "tidalId": track_id # OURO: ID para download direto
                })

            return {
                "collectionId": collection_id,
                "collectionName": album_meta_cache.get('title', 'Álbum Tidal'),
                "artistName": items[0].get('artist', {}).get('name') if items else "Artista",
                "artworkUrl": album_meta_cache.get('artwork', ''),
                "year": "", # Tidal track list nem sempre traz ano
                "tracks": tracks
            }

        except Exception as e:
            print(f"❌ Erro Tidal Album Details: {e}")
            raise e