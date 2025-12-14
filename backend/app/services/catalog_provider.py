from ytmusicapi import YTMusic

class CatalogProvider:
    # Inicializa sem autenticação (apenas busca pública)
    yt = YTMusic()

    @staticmethod
    def search_catalog(query: str, type: str = "song", limit: int = 40):
        """
        Busca músicas ou álbuns no YouTube Music.
        """
        filter_type = "songs" if type == "song" else "albums"
        
        try:
            # Pede mais resultados para permitir paginação
            raw_results = CatalogProvider.yt.search(query, filter=filter_type, limit=100)
            
            normalized_results = []
            
            for item in raw_results:
                thumbnails = item.get('thumbnails', [])
                artwork_url = thumbnails[-1]['url'] if thumbnails else ""
                
                artist_data = item.get('artists', [{}])
                artist_name = artist_data[0].get('name', 'Desconhecido')
                
                # CORREÇÃO DO ANO:
                # Garante que seja string vazia se for None ou não existir
                year = str(item.get('year') or '').strip()
                
                if type == "song":
                    album_data = item.get('album', {})
                    album_name = album_data.get('name') if album_data else "Single"
                    
                    normalized_results.append({
                        "type": "song",
                        "trackName": item.get('title'),
                        "artistName": artist_name,
                        "collectionName": album_name,
                        "artworkUrl": artwork_url,
                        "previewUrl": None, 
                        "year": year, 
                        "videoId": item.get('videoId')
                    })
                
                elif type == "album":
                    normalized_results.append({
                        "type": "album",
                        "collectionId": item.get('browseId'),
                        "collectionName": item.get('title'),
                        "artistName": artist_name,
                        "artworkUrl": artwork_url,
                        "year": year,
                        "trackCount": 0
                    })

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
            
            tracks = []
            # CORREÇÃO NUMERAÇÃO:
            # Usamos enumerate(start=1) para garantir numeração sequencial correta (1, 2, 3...)
            # baseada na ordem que o YouTube entrega.
            for i, track in enumerate(album.get('tracks', []), start=1):
                if not track.get('title'): continue

                artist_name = "Vários Artistas"
                if track.get('artists'):
                    artist_name = track['artists'][0].get('name')
                
                duration_sec = track.get('duration_seconds', 0)
                
                tracks.append({
                    "trackNumber": i, # Agora usa o índice do loop + 1
                    "trackName": track.get('title'),
                    "artistName": artist_name,
                    "collectionName": album.get('title'),
                    "durationMs": int(duration_sec) * 1000, # Garante int
                    "previewUrl": None,
                    "artworkUrl": album['thumbnails'][-1]['url'] if album.get('thumbnails') else ""
                })

            return {
                "collectionId": browse_id,
                "collectionName": album.get('title'),
                "artistName": album['artists'][0]['name'] if album.get('artists') else "Vários",
                "artworkUrl": album['thumbnails'][-1]['url'] if album.get('thumbnails') else "",
                "year": str(album.get('year') or ''),
                "tracks": tracks
            }
        except Exception as e:
            print(f"❌ Erro YTMusic Album Details: {e}")
            raise e