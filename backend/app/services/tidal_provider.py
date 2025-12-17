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
            elif type == "playlist":
                param_key = "p"
                
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
                image_uuid = None
                
                # Lógica de Imagem/Capa
                if type == "album":
                    image_uuid = item.get('cover')
                elif type == "artist":
                    image_uuid = item.get('picture') # Artistas usam 'picture'
                else: # song
                    image_uuid = item.get('album', {}).get('cover')

                artwork_url = ""
                if image_uuid:
                    path = image_uuid.replace('-', '/')
                    # Artistas costumam ter resoluções 320x320 ou 750x750. 
                    # Usamos 750x750 para artistas para melhor qualidade, 640x640 para o resto.
                    res = "750x750" if type == "artist" else "640x640"
                    artwork_url = f"{TidalProvider.CDN_URL}/{path}/{res}.jpg"

                # Lógica de Nome do Artista
                artist_name = "Desconhecido"
                if type == "artist":
                    artist_name = item.get('name')
                elif item.get('artist'):
                    artist_name = item['artist'].get('name')
                elif item.get('artists'):
                    artist_name = item['artists'][0].get('name')

                # FORMATAÇÃO DO RESULTADO
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
                        "tidalId": item.get('id'),
                        "genre": None  # Tidal não retorna gênero em search, preenchido depois se baixado
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
                elif type == "artist":
                    normalized_results.append({
                        "type": "artist",
                        "artistName": item.get('name'),
                        "artistId": str(item.get('id')),
                        "artworkUrl": artwork_url,
                        "source": "Tidal",
                        "popularity": item.get('popularity')
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
                            continue

                        if not resp.content:
                            continue

                        data = resp.json()
                        
                        if 'error' in data:
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
                        continue
                    except Exception as loop_e:
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
            # Primeiro tenta buscar metadados do álbum diretamente
            album_genre = None
            album_year = ""
            album_title = ""
            album_artist = ""
            album_artwork = ""
            
            # Tenta buscar info do álbum
            with httpx.Client() as client:
                album_url = f"{TidalProvider.BASE_API}/album/"
                resp_album = client.get(album_url, params={"id": collection_id}, timeout=10.0)
                if resp_album.status_code == 200:
                    try:
                        album_info = resp_album.json()
                        album_data = album_info.get('data', {})
                        album_title = album_data.get('title', '')
                        album_year = str(album_data.get('releaseDate', ''))[:4]
                        # Tenta buscar gênero de diferentes campos
                        if album_data.get('genre'):
                            album_genre = album_data.get('genre')
                        elif album_data.get('genres'):
                            genres = album_data.get('genres', [])
                            if genres:
                                album_genre = ', '.join(genres) if isinstance(genres, list) else str(genres)
                        cover_id = album_data.get('cover')
                        if cover_id:
                            album_artwork = f"{TidalProvider.CDN_URL}/{cover_id.replace('-', '/')}/640x640.jpg"
                        if album_data.get('artist'):
                            album_artist = album_data['artist'].get('name', '')
                        elif album_data.get('artists'):
                            album_artist = album_data['artists'][0].get('name', '')
                    except:
                        pass
            
            # Agora busca as tracks
            url = f"{TidalProvider.BASE_API}/album/items" 
            params = {"id": collection_id, "limit": 100, "offset": 0}
            
            with httpx.Client() as client:
                resp = client.get(url, params=params, timeout=10.0)
                
                if resp.status_code != 200:
                     print(f"⚠️ Tidal Album Items falhou ({resp.status_code})")
                     raise Exception(f"Album not found (HTTP {resp.status_code})")

                try:
                    data = resp.json()
                except json.JSONDecodeError:
                    raise Exception("Tidal returned invalid JSON for album details")
                
            items = data.get('data', {}).get('items', [])
            if not items and 'items' in data: items = data['items']

            tracks = []
            
            # Fallback para metadados da primeira track se não pegou antes
            if items and not album_title:
                first = items[0]
                album_obj = first.get('album', {})
                album_title = album_obj.get('title', 'Álbum')
                cover_id = album_obj.get('cover')
                if cover_id:
                     album_artwork = f"{TidalProvider.CDN_URL}/{cover_id.replace('-', '/')}/640x640.jpg"

            for item in items:
                track_title = item.get('title')
                track_id = item.get('id')
                track_num = item.get('trackNumber', 0)
                duration = item.get('duration', 0) * 1000 
                
                artist_name = "Vários"
                if item.get('artist'): artist_name = item['artist'].get('name')
                if not album_artist:
                    album_artist = artist_name

                tracks.append({
                    "trackNumber": track_num,
                    "trackName": track_title,
                    "artistName": artist_name,
                    "collectionName": album_title,
                    "durationMs": duration,
                    "previewUrl": None,
                    "artworkUrl": album_artwork,
                    "tidalId": track_id 
                })

            return {
                "collectionId": collection_id,
                "collectionName": album_title or 'Álbum Tidal',
                "artistName": album_artist or "Artista",
                "artworkUrl": album_artwork,
                "year": album_year,
                "genre": album_genre,
                "tracks": tracks
            }

        except Exception as e:
            print(f"❌ Erro Tidal Album Details: {e}")
            raise e

    @staticmethod
    def get_artist_details(artist_id: str):
        """
        Busca detalhes do artista e sua discografia pelo ID do Tidal.
        Retorna álbuns filtrados por ID do artista (não apenas nome).
        """
        try:
            with httpx.Client() as client:
                headers = {"User-Agent": "Mozilla/5.0"}
                
                # 1. Busca info básica do artista
                artist_info = {}
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/", 
                                     params={"id": artist_id}, headers=headers, timeout=10.0)
                    if resp.status_code == 200:
                        data = resp.json().get('data', {})
                        picture = data.get('picture', '')
                        artist_info = {
                            "artistId": artist_id,
                            "artistName": data.get('name', 'Artista'),
                            "artworkUrl": f"{TidalProvider.CDN_URL}/{picture.replace('-', '/')}/750x750.jpg" if picture else "",
                            "bio": data.get('bio', ''),
                        }
                except Exception as e:
                    print(f"⚠️ Erro ao buscar info do artista: {e}")
                
                # 2. Busca álbuns do artista (endpoint dedicado)
                albums = []
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/albums", 
                                     params={"id": artist_id, "limit": 50, "offset": 0}, 
                                     headers=headers, timeout=10.0)
                    if resp.status_code == 200:
                        items = resp.json().get('data', {}).get('items', [])
                        for item in items:
                            cover = item.get('cover', '')
                            release_date = str(item.get('releaseDate', ''))
                            
                            # Filtra por ID do artista principal (não apenas nome)
                            item_artist_id = str(item.get('artist', {}).get('id', ''))
                            if item_artist_id != artist_id:
                                # Verifica se é colaboração (aparece em 'artists')
                                artists_list = item.get('artists', [])
                                is_collaboration = any(str(a.get('id')) == artist_id for a in artists_list)
                                if not is_collaboration:
                                    continue  # Pula itens que não são do artista
                            
                            albums.append({
                                "type": "album",
                                "collectionId": str(item.get('id')),
                                "collectionName": item.get('title'),
                                "artistName": item.get('artist', {}).get('name', 'Vários'),
                                "artistId": item_artist_id,
                                "artworkUrl": f"{TidalProvider.CDN_URL}/{cover.replace('-', '/')}/640x640.jpg" if cover else "",
                                "year": release_date[:4] if release_date else "",
                                "releaseDate": release_date,
                                "trackCount": item.get('numberOfTracks', 0),
                                "source": "Tidal"
                            })
                except Exception as e:
                    print(f"⚠️ Erro ao buscar álbuns do artista: {e}")
                
                # 3. Busca singles/EPs
                singles = []
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/albums", 
                                     params={"id": artist_id, "limit": 50, "offset": 0, "filter": "EPSANDSINGLES"}, 
                                     headers=headers, timeout=10.0)
                    if resp.status_code == 200:
                        items = resp.json().get('data', {}).get('items', [])
                        for item in items:
                            cover = item.get('cover', '')
                            release_date = str(item.get('releaseDate', ''))
                            
                            singles.append({
                                "type": "single",
                                "collectionId": str(item.get('id')),
                                "collectionName": item.get('title'),
                                "artistName": item.get('artist', {}).get('name', 'Vários'),
                                "artworkUrl": f"{TidalProvider.CDN_URL}/{cover.replace('-', '/')}/640x640.jpg" if cover else "",
                                "year": release_date[:4] if release_date else "",
                                "releaseDate": release_date,
                                "trackCount": item.get('numberOfTracks', 0),
                                "source": "Tidal"
                            })
                except Exception as e:
                    print(f"⚠️ Erro ao buscar singles: {e}")
                
                # 4. Busca top tracks do artista
                top_tracks = []
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/toptracks", 
                                     params={"id": artist_id, "limit": 10}, 
                                     headers=headers, timeout=10.0)
                    if resp.status_code == 200:
                        items = resp.json().get('data', {}).get('items', [])
                        for item in items:
                            album_cover = item.get('album', {}).get('cover', '')
                            top_tracks.append({
                                "type": "song",
                                "trackName": item.get('title'),
                                "artistName": item.get('artist', {}).get('name', 'Vários'),
                                "collectionName": item.get('album', {}).get('title', 'Single'),
                                "artworkUrl": f"{TidalProvider.CDN_URL}/{album_cover.replace('-', '/')}/640x640.jpg" if album_cover else "",
                                "tidalId": item.get('id'),
                                "isLossless": item.get('audioQuality') == 'LOSSLESS',
                                "source": "Tidal"
                            })
                except Exception as e:
                    print(f"⚠️ Erro ao buscar top tracks: {e}")
                
                # 5. Ordena por data de lançamento (mais recente primeiro)
                albums.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                singles.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                
                return {
                    "artist": artist_info,
                    "albums": albums,
                    "singles": singles,
                    "topTracks": top_tracks
                }
                
        except Exception as e:
            print(f"❌ Erro Tidal Artist Details: {e}")
            raise e