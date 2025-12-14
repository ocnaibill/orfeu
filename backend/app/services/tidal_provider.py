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
                headers = {"User-Agent": "Mozilla/5.0"}
                resp = client.get(url, params=params, headers=headers, timeout=10.0)
                
                if resp.status_code != 200:
                    print(f"⚠️ Tidal API Error: {resp.status_code}")
                    return []
                
                try:
                    data = resp.json()
                except json.JSONDecodeError:
                    print("⚠️ Tidal Search retornou JSON inválido.")
                    return []
            
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
                if item.get('artist'):
                    artist_name = item['artist'].get('name')
                elif item.get('artists'):
                    artist_name = item['artists'][0].get('name')

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
                        "collectionId": str(item.get('id')),
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
                    
                    try:
                        resp = client.get(url, params=params, timeout=10.0)
                        
                        if resp.status_code != 200: 
                            print(f"   ⚠️ Tidal HTTP {resp.status_code} para {q}")
                            continue

                        if not resp.content:
                            print(f"   ⚠️ Tidal retornou corpo vazio para {q}")
                            continue

                        data = resp.json()
                        
                        if 'error' in data:
                            print(f"   ⚠️ Tidal API Error ({q}): {data.get('error')}")
                            continue

                        manifest_b64 = data.get('data', {}).get('manifest')
                        
                        if manifest_b64:
                            decoded_json = base64.b64decode(manifest_b64).decode('utf-8')
                            manifest = json.loads(decoded_json)
                            
                            urls = manifest.get('urls', [])
                            if urls:
                                print(f"   ✅ URL Tidal encontrada para {q}")
                                return {
                                    "url": urls[0],
                                    "mime": manifest.get('mimeType', 'audio/flac'),
                                    "codec": manifest.get('codecs', 'flac')
                                }
                                
                    except json.JSONDecodeError:
                        print(f"   ❌ Resposta inválida (Não-JSON) do Tidal para {q}. Body: {resp.text[:50]}...")
                        continue
                    except Exception as loop_e:
                        print(f"   ❌ Erro no loop Tidal ({q}): {loop_e}")
                        continue
                        
            return None
        except Exception as e:
            print(f"❌ Erro Tidal Download Geral: {e}")
            return None

    @staticmethod
    def get_album_details(collection_id: str):
        """
        Busca faixas de um álbum no Tidal.
        """
        try:
            url = f"{TidalProvider.BASE_API}/album/items" 
            params = {"id": collection_id, "limit": 100, "offset": 0}
            
            with httpx.Client() as client:
                resp = client.get(url, params=params, timeout=10.0)
                
                if resp.status_code != 200:
                     print(f"⚠️ Tidal Album Items falhou ({resp.status_code}), tentando rota alternativa...")
                     url_alt = f"{TidalProvider.BASE_API}/album/"
                     resp = client.get(url_alt, params={"id": collection_id}, timeout=10.0)
                
                if resp.status_code != 200:
                    raise Exception(f"Album not found (HTTP {resp.status_code})")

                try:
                    data = resp.json()
                except json.JSONDecodeError:
                    raise Exception("Tidal returned invalid JSON for album details")
                
            items = data.get('data', {}).get('items', [])
            if not items and 'items' in data: items = data['items']

            tracks = []
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
                track_title = item.get('title')
                track_id = item.get('id')
                track_num = item.get('trackNumber', 0)
                duration = item.get('duration', 0) * 1000 
                
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
                    "tidalId": track_id 
                })

            return {
                "collectionId": collection_id,
                "collectionName": album_meta_cache.get('title', 'Álbum Tidal'),
                "artistName": items[0].get('artist', {}).get('name') if items else "Artista",
                "artworkUrl": album_meta_cache.get('artwork', ''),
                "year": "", 
                "tracks": tracks
            }

        except Exception as e:
            print(f"❌ Erro Tidal Album Details: {e}")
            raise e