import httpx
import base64
import json
from app.services.metadata_provider import MetadataProvider

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
            
            # 1. Definição de Parâmetros e Chave de Resposta
            params = {"limit": limit, "offset": 0}
            target_key = "tracks" # Default
            
            if type == "song":
                params["s"] = query
                target_key = "tracks"
            elif type == "album":
                params["al"] = query
                target_key = "albums"
            elif type == "artist":
                params["a"] = query
                target_key = "artists"
            elif type == "playlist":
                params["p"] = query
                target_key = "playlists"
            
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

            # 2. Navegação no JSON
            # A API agora retorna diretamente em data.items (não mais em data.tracks.items)
            inner_data = data.get('data', {})
            
            # Tenta primeiro o formato novo (data.items)
            items = inner_data.get('items', [])
            
            # Fallback para formato antigo (data.[tracks/albums/artists].items)
            if not items:
                section = inner_data.get(target_key, {})
                items = section.get('items', [])
            
            normalized_results = []
            
            for item in items:
                if type == "artist":
                    picture_uuid = item.get('picture')
                    artwork_url = ""
                    if picture_uuid:
                        path = picture_uuid.replace('-', '/')
                        artwork_url = f"{TidalProvider.CDN_URL}/{path}/750x750.jpg"
                    
                    normalized_results.append({
                        "type": "artist",
                        "artistName": item.get('name'),
                        "artistId": str(item.get('id')),
                        "artworkUrl": artwork_url, 
                        "popularity": item.get('popularity'),
                        "source": "Tidal"
                    })

                elif type == "album":
                    cover_uuid = item.get('cover')
                    artwork_url = ""
                    if cover_uuid:
                        path = cover_uuid.replace('-', '/')
                        artwork_url = f"{TidalProvider.CDN_URL}/{path}/640x640.jpg"

                    artist_name = "Vários"
                    if item.get('artist'): artist_name = item['artist'].get('name')
                    elif item.get('artists'): artist_name = item['artists'][0].get('name')

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

                elif type == "song":
                    album_obj = item.get('album', {})
                    cover_uuid = album_obj.get('cover')
                    artwork_url = ""
                    if cover_uuid:
                        path = cover_uuid.replace('-', '/')
                        artwork_url = f"{TidalProvider.CDN_URL}/{path}/640x640.jpg"

                    artist_name = "Desconhecido"
                    if item.get('artist'): artist_name = item['artist'].get('name')
                    elif item.get('artists'): artist_name = item['artists'][0].get('name')

                    normalized_results.append({
                        "type": "song",
                        "trackName": item.get('title'),
                        "artistName": artist_name,
                        "collectionName": album_obj.get('title', 'Single'),
                        "artworkUrl": artwork_url,
                        "previewUrl": None,
                        "year": str(item.get('streamStartDate', ''))[:4], 
                        "releaseDate": item.get('streamStartDate'),
                        "isLossless": item.get('audioQuality') == 'LOSSLESS',
                        "source": "Tidal",
                        "tidalId": item.get('id') 
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
                    try:
                        resp = client.get(url, params=params, timeout=10.0)
                        if resp.status_code != 200: continue
                        data = resp.json()
                        if 'error' in data: continue
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
                    except: continue
            return None
        except Exception as e:
            return None

    @staticmethod
    def get_album_details(collection_id: str):
        """
        Busca detalhes do álbum e suas faixas pelo ID do Tidal.
        A API retorna as tracks diretamente em data.items[].item
        """
        try:
            album_genre = "Desconhecido"
            album_year = ""
            album_title = ""
            album_artist = ""
            album_artwork = ""
            tracks = []
            
            with httpx.Client() as client:
                headers = {"User-Agent": "Mozilla/5.0"}
                
                # A API /album/ retorna as tracks diretamente
                album_url = f"{TidalProvider.BASE_API}/album/"
                resp = client.get(album_url, params={"id": collection_id}, headers=headers, timeout=15.0)
                
                if resp.status_code == 200:
                    response_data = resp.json()
                    items_data = response_data.get('data', {})
                    items = items_data.get('items', [])
                    
                    for idx, item_wrapper in enumerate(items):
                        # A estrutura é items[].item para cada track
                        track_data = item_wrapper.get('item', item_wrapper)
                        
                        track_id = track_data.get('id')
                        track_title = track_data.get('title', '')
                        track_num = track_data.get('trackNumber', idx + 1)
                        duration = track_data.get('duration', 0) * 1000
                        
                        # Artista da track
                        artist_obj = track_data.get('artist', {})
                        track_artist = artist_obj.get('name', 'Vários')
                        
                        # Dados do álbum (vem em cada track)
                        album_obj = track_data.get('album', {})
                        
                        # Extrai metadados do álbum da primeira track
                        if idx == 0:
                            album_title = album_obj.get('title', '')
                            # Usa streamStartDate da track como fonte principal de data
                            stream_date = track_data.get('streamStartDate', '')
                            release_date = album_obj.get('releaseDate', '')
                            date_str = str(stream_date or release_date or '')
                            album_year = date_str[:4] if date_str else ""
                            album_artist = track_artist
                            
                            cover_id = album_obj.get('cover', '')
                            if cover_id:
                                album_artwork = f"{TidalProvider.CDN_URL}/{cover_id.replace('-', '/')}/640x640.jpg"
                        
                        # Artwork da track (usa o do álbum)
                        track_cover = album_obj.get('cover', '')
                        track_artwork = f"{TidalProvider.CDN_URL}/{track_cover.replace('-', '/')}/640x640.jpg" if track_cover else album_artwork
                        
                        tracks.append({
                            "trackNumber": track_num,
                            "trackName": track_title,
                            "artistName": track_artist,
                            "collectionName": album_title,
                            "durationMs": duration,
                            "previewUrl": None,
                            "artworkUrl": track_artwork,
                            "tidalId": track_id,
                            "isLossless": track_data.get('audioQuality') in ['LOSSLESS', 'HI_RES', 'HI_RES_LOSSLESS']
                        })
            
            # Busca gênero externo se temos artista e título
            if album_artist and album_title:
                print(f"🌍 Buscando gênero externo para: {album_artist} - {album_title}")
                album_genre = MetadataProvider.get_genre(album_artist, album_title)
            
            print(f"✅ Álbum {album_title}: {len(tracks)} faixas")
            
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
        Usa a nova API com parâmetro 'f' para discografia completa.
        """
        try:
            with httpx.Client() as client:
                headers = {"User-Agent": "Mozilla/5.0"}
                
                # 1. Busca info básica do artista (parâmetro 'id')
                artist_info = {}
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/", 
                                     params={"id": artist_id}, headers=headers, timeout=10.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        # A API retorna 'artist' diretamente, não dentro de 'data'
                        artist_data = data.get('artist', {})
                        picture = artist_data.get('picture', '')
                        artist_info = {
                            "artistId": str(artist_data.get('id', artist_id)),
                            "artistName": artist_data.get('name', 'Artista'),
                            "artworkUrl": f"{TidalProvider.CDN_URL}/{picture.replace('-', '/')}/750x750.jpg" if picture else "",
                            "bio": artist_data.get('bio', ''),
                            "popularity": artist_data.get('popularity', 0),
                        }
                except Exception as e:
                    print(f"⚠️ Erro artist info: {e}")
                
                # 2. Busca discografia completa (parâmetro 'f')
                albums = []
                tracks_from_albums = []
                try:
                    resp = client.get(f"{TidalProvider.BASE_API}/artist/", 
                                     params={"f": artist_id}, headers=headers, timeout=15.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        
                        # Extrai álbuns da estrutura: albums.rows[].modules[].pagedList.items[]
                        albums_data = data.get('albums', {})
                        for row in albums_data.get('rows', []):
                            for module in row.get('modules', []):
                                items = module.get('pagedList', {}).get('items', [])
                                for item in items:
                                    cover = item.get('cover', '')
                                    release_date = str(item.get('streamStartDate') or item.get('releaseDate') or '')
                                    
                                    # Pega o artista principal
                                    artists_list = item.get('artists', [])
                                    artist_name = artists_list[0].get('name', 'Vários') if artists_list else 'Vários'
                                    
                                    albums.append({
                                        "type": "album",
                                        "collectionId": str(item.get('id')),
                                        "collectionName": item.get('title'),
                                        "artistName": artist_name,
                                        "artistId": str(artists_list[0].get('id', '')) if artists_list else artist_id,
                                        "artworkUrl": f"{TidalProvider.CDN_URL}/{cover.replace('-', '/')}/640x640.jpg" if cover else "",
                                        "year": release_date[:4] if release_date else "",
                                        "releaseDate": release_date[:10] if release_date else "",
                                        "trackCount": item.get('numberOfTracks', 0),
                                        "source": "Tidal"
                                    })
                        
                        # Extrai tracks
                        for track in data.get('tracks', []):
                            track_data = track.get('item', track)
                            album_obj = track_data.get('album', {})
                            album_cover = album_obj.get('cover', '')
                            
                            tracks_from_albums.append({
                                "type": "song",
                                "trackName": track_data.get('title'),
                                "artistName": track_data.get('artist', {}).get('name', 'Vários'),
                                "collectionName": album_obj.get('title', 'Single'),
                                "artworkUrl": f"{TidalProvider.CDN_URL}/{album_cover.replace('-', '/')}/640x640.jpg" if album_cover else "",
                                "tidalId": track_data.get('id'),
                                "isLossless": track_data.get('audioQuality') in ['LOSSLESS', 'HI_RES', 'HI_RES_LOSSLESS'],
                                "durationMs": track_data.get('duration', 0) * 1000,
                                "source": "Tidal"
                            })
                except Exception as e:
                    print(f"⚠️ Erro buscando discografia: {e}")
                
                # 3. Separa Singles/EPs (álbuns com menos de 4 faixas ou tipo explícito)
                singles = []
                full_albums = []
                for album in albums:
                    track_count = album.get('trackCount', 0)
                    if track_count <= 3:
                        album['type'] = 'single'
                        singles.append(album)
                    else:
                        full_albums.append(album)
                
                # Usa tracks como top tracks se não tiver muitos álbuns
                top_tracks = tracks_from_albums[:10] if tracks_from_albums else []
                
                # Ordenação por data
                full_albums.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                singles.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                
                # Busca artistas similares
                similar_artists = TidalProvider.get_similar_artists(artist_info.get('artistName', ''))
                
                print(f"✅ Artista {artist_info.get('artistName', artist_id)}: {len(full_albums)} álbuns, {len(singles)} singles, {len(top_tracks)} tracks, {len(similar_artists)} similares")
                
                return {
                    "artist": artist_info,
                    "albums": full_albums,
                    "singles": singles,
                    "topTracks": top_tracks,
                    "similarArtists": similar_artists
                }
                
        except Exception as e:
            print(f"❌ Erro Tidal Artist Details: {e}")
            raise e

    @staticmethod
    def get_similar_artists(artist_name: str, limit: int = 6):
        """
        Busca artistas similares baseado no gênero do artista.
        Usa o iTunes para descobrir o gênero e depois busca artistas do mesmo gênero no Tidal.
        """
        if not artist_name:
            return []
        
        try:
            # 1. Descobre o gênero do artista via iTunes
            genre = MetadataProvider.get_genre(artist_name)
            if not genre or genre == "Desconhecido":
                # Tenta usar o nome do artista para buscar artistas relacionados
                genre = "pop"  # Fallback para pop
            
            # 2. Busca artistas do mesmo gênero
            search_query = f"{genre} artists"
            artists_result = TidalProvider.search_catalog(search_query, limit=20, type="artist")
            
            similar = []
            for artist in artists_result:
                # Exclui o próprio artista
                if artist.get('artistName', '').lower() == artist_name.lower():
                    continue
                    
                similar.append({
                    "artistId": artist.get('artistId'),
                    "name": artist.get('artistName'),
                    "image": artist.get('artworkUrl', ''),
                })
                
                if len(similar) >= limit:
                    break
            
            return similar
            
        except Exception as e:
            print(f"⚠️ Erro ao buscar artistas similares: {e}")
            return []