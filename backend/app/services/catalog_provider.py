from ytmusicapi import YTMusic
import traceback
import re

def _get_high_res_thumbnail(url: str) -> str:
    """
    Converte URL de thumbnail do YouTube Music para alta resolução.
    YT Music usa parâmetros como w60-h60, w120-h120, etc.
    Modificamos para w800-h800 para máxima qualidade.
    """
    if not url:
        return ""
    
    # Padrão: substitui wXXX-hXXX por w800-h800
    # Exemplos de URLs:
    # https://lh3.googleusercontent.com/...=w60-h60-l90-rj
    # https://lh3.googleusercontent.com/...=w120-h120-l90-rj
    # https://lh3.googleusercontent.com/...=w226-h226-l90-rj
    
    # Substitui padrões de tamanho
    high_res_url = re.sub(r'=w\d+-h\d+', '=w800-h800', url)
    
    # Se não tinha parâmetro, tenta adicionar
    if high_res_url == url and 'lh3.googleusercontent.com' in url:
        if '=' in url:
            # Adiciona no final dos parâmetros existentes
            high_res_url = re.sub(r'(=.*)$', r'\1-w800-h800', url)
        else:
            high_res_url = url + '=w800-h800'
    
    return high_res_url

class CatalogProvider:
    # Inicializa sem autenticação (apenas busca pública)
    yt = YTMusic()

    @staticmethod
    def search_catalog(query: str, type: str = "song", limit: int = 40):
        """
        Busca músicas, álbuns ou artistas no YouTube Music.
        """
        try:
            # Mapeamento correto dos filtros
            filter_map = {
                "song": "songs",
                "album": "albums",
                "artist": "artists"
            }
            search_filter = filter_map.get(type, "songs")
            
            # Pede mais resultados para permitir paginação/filtragem
            raw_results = CatalogProvider.yt.search(query, filter=search_filter, limit=limit)
            
            normalized_results = []
            
            for item in raw_results:
                try:
                    thumbnails = item.get('thumbnails', [])
                    raw_url = thumbnails[-1]['url'] if thumbnails else ""
                    artwork_url = _get_high_res_thumbnail(raw_url)
                    
                    # --- ARTISTA ---
                    if type == "artist" and item.get('resultType') == 'artist':
                        normalized_results.append({
                            "type": "artist",
                            "artistName": item.get('artist'),
                            "artistId": item.get('browseId'),
                            "artworkUrl": artwork_url,
                            "source": "YTMusic"
                        })
                    
                    # --- ÁLBUM ---
                    elif type == "album" and item.get('resultType') == 'album':
                        artist_name = "Vários"
                        if item.get('artists'):
                            artist_name = item['artists'][0].get('name')
                        
                        year = str(item.get('year') or '').strip()
                        
                        normalized_results.append({
                            "type": "album",
                            "collectionId": item.get('browseId'),
                            "collectionName": item.get('title'),
                            "artistName": artist_name,
                            "artworkUrl": artwork_url,
                            "year": year,
                            "releaseDate": year, # Compatibilidade
                            "trackCount": 0,
                            "source": "YTMusic"
                        })
                        
                    # --- MÚSICA ---
                    elif type == "song" and item.get('resultType') == 'song':
                        artist_data = item.get('artists', [{}])
                        artist_name = artist_data[0].get('name', 'Desconhecido')
                        
                        album_data = item.get('album', {})
                        album_name = album_data.get('name') if album_data else "Single"
                        
                        # Extrai duração (YTMusic retorna em formato "3:45" ou duration_seconds)
                        duration_seconds = item.get('duration_seconds', 0)
                        if not duration_seconds and item.get('duration'):
                            try:
                                parts = str(item['duration']).split(':')
                                if len(parts) == 2:
                                    duration_seconds = int(parts[0]) * 60 + int(parts[1])
                                elif len(parts) == 3:
                                    duration_seconds = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
                            except:
                                pass
                        
                        normalized_results.append({
                            "type": "song",
                            "trackName": item.get('title'),
                            "artistName": artist_name,
                            "collectionName": album_name,
                            "artworkUrl": artwork_url,
                            "previewUrl": None, 
                            "year": "", # Geralmente vazio em search songs
                            "videoId": item.get('videoId'),
                            "duration": item.get('duration', ''),  # formato "3:45"
                            "durationMs": duration_seconds * 1000,
                            "source": "YTMusic"
                        })
                except Exception as e:
                    print(f"⚠️ Item YTMusic ignorado: {e}")
                    continue

            return normalized_results

        except Exception as e:
            print(f"❌ Erro YTMusic Search: {e}")
            return []

    @staticmethod
    def get_album_details(browse_id: str):
        """
        Busca detalhes e faixas de um álbum pelo browseId.
        """
        try:
            album = CatalogProvider.yt.get_album(browse_id)
            
            # Artwork em alta resolução (antes do loop de tracks)
            raw_artwork = album['thumbnails'][-1]['url'] if album.get('thumbnails') else ""
            high_res_artwork = _get_high_res_thumbnail(raw_artwork)
            
            tracks = []
            # Enumera a partir de 1 para trackNumber
            for i, track in enumerate(album.get('tracks', []), start=1):
                if not track.get('title'): continue

                artist_name = "Vários Artistas"
                if track.get('artists'):
                    artist_name = track['artists'][0].get('name')
                
                duration_sec = track.get('duration_seconds', 0)
                
                tracks.append({
                    "trackNumber": i, 
                    "trackName": track.get('title'),
                    "artistName": artist_name,
                    "collectionName": album.get('title'),
                    "durationMs": int(duration_sec) * 1000, 
                    "previewUrl": None,
                    "artworkUrl": high_res_artwork
                })
            
            year = str(album.get('year') or '')
            
            return {
                "collectionId": browse_id,
                "collectionName": album.get('title'),
                "artistName": album['artists'][0]['name'] if album.get('artists') else "Vários",
                "artworkUrl": high_res_artwork,
                "year": year,
                "releaseDate": year,
                "tracks": tracks
            }
        except Exception as e:
            print(f"❌ Erro YTMusic Album Details: {e}")
            raise e

    @staticmethod
    def get_artist_details(artist_id: str):
        """
        Busca detalhes do artista no YouTube Music (Bio, Top Songs, Albums, Singles).
        Retorna estrutura compatível com o TidalProvider.
        """
        try:
            # Busca os dados do artista
            artist = CatalogProvider.yt.get_artist(artist_id)
            
            # 1. Info Básica
            thumbnails = artist.get('thumbnails', [])
            raw_url = thumbnails[-1]['url'] if thumbnails else ""
            artwork_url = _get_high_res_thumbnail(raw_url)
            
            artist_info = {
                "artistId": artist_id,
                "artistName": artist.get('name', 'Artista'),
                "artworkUrl": artwork_url,
                "bio": artist.get('description', ''),
                "source": "YTMusic"
            }

            # 2. Álbuns
            # A API retorna um dicionário onde a chave 'albums' contém 'results'
            albums = []
            if 'albums' in artist and 'results' in artist['albums']:
                for item in artist['albums']['results']:
                    thumb = item.get('thumbnails', [])
                    raw_cover = thumb[-1]['url'] if thumb else ""
                    cover = _get_high_res_thumbnail(raw_cover)
                    year = str(item.get('year') or '')
                    
                    albums.append({
                        "type": "album",
                        "collectionId": item.get('browseId'),
                        "collectionName": item.get('title'),
                        "artistName": artist.get('name'), # Assume o próprio artista
                        "artistId": artist_id,
                        "artworkUrl": cover,
                        "year": year,
                        "releaseDate": year,
                        "source": "YTMusic"
                    })

            # 3. Singles
            singles = []
            if 'singles' in artist and 'results' in artist['singles']:
                for item in artist['singles']['results']:
                    thumb = item.get('thumbnails', [])
                    raw_cover = thumb[-1]['url'] if thumb else ""
                    cover = _get_high_res_thumbnail(raw_cover)
                    year = str(item.get('year') or '')
                    
                    singles.append({
                        "type": "single",
                        "collectionId": item.get('browseId'),
                        "collectionName": item.get('title'),
                        "artistName": artist.get('name'),
                        "artworkUrl": cover,
                        "year": year,
                        "releaseDate": year,
                        "source": "YTMusic"
                    })

            # 4. Top Tracks (Songs)
            top_tracks = []
            if 'songs' in artist and 'results' in artist['songs']:
                for item in artist['songs']['results']:
                    thumb = item.get('thumbnails', [])
                    raw_cover = thumb[-1]['url'] if thumb else ""
                    cover = _get_high_res_thumbnail(raw_cover)
                    
                    # Tenta pegar info do álbum se disponível na listagem (raro no top songs do YT)
                    album_name = "Single"
                    if item.get('album'):
                         album_name = item['album'].get('name', 'Single')

                    top_tracks.append({
                        "type": "song",
                        "trackName": item.get('title'),
                        "artistName": artist.get('name'),
                        "collectionName": album_name,
                        "artworkUrl": cover,
                        "videoId": item.get('videoId'),
                        "source": "YTMusic"
                    })

            return {
                "artist": artist_info,
                "albums": albums,
                "singles": singles,
                "topTracks": top_tracks
            }

        except Exception as e:
            print(f"❌ Erro YTMusic Artist Details: {e}")
            raise e