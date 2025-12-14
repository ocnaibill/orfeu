from ytmusicapi import YTMusic

class CatalogProvider:
    # Inicializa sem autenticação (apenas busca pública)
    # Se precisar de conteúdo +18 restrito, precisaria de headers_auth.json
    yt = YTMusic()

    @staticmethod
    def search_catalog(query: str, type: str = "song", limit: int = 40):
        """
        Busca músicas ou álbuns no YouTube Music.
        """
        filter_type = "songs" if type == "song" else "albums"
        
        try:
            # O YTMusic não tem 'offset' nativo simples, então pedimos um limite maior
            # para permitir a paginação em memória no main.py
            raw_results = CatalogProvider.yt.search(query, filter=filter_type, limit=100)
            
            normalized_results = []
            
            for item in raw_results:
                # Pega a maior imagem disponível
                thumbnails = item.get('thumbnails', [])
                artwork_url = thumbnails[-1]['url'] if thumbnails else ""
                
                # Dados comuns
                artist_data = item.get('artists', [{}])
                artist_name = artist_data[0].get('name', 'Desconhecido')
                
                if type == "song":
                    album_data = item.get('album', {})
                    album_name = album_data.get('name') if album_data else "Single"
                    
                    normalized_results.append({
                        "type": "song",
                        "trackName": item.get('title'),
                        "artistName": artist_name,
                        "collectionName": album_name,
                        "artworkUrl": artwork_url,
                        "previewUrl": None, # YTMusic não dá preview de áudio direto
                        "year": item.get('year', ''), # Às vezes vem, às vezes não
                        "videoId": item.get('videoId')
                    })
                
                elif type == "album":
                    normalized_results.append({
                        "type": "album",
                        "collectionId": item.get('browseId'), # ID do Álbum no YTMusic (String)
                        "collectionName": item.get('title'),
                        "artistName": artist_name,
                        "artworkUrl": artwork_url,
                        "year": item.get('year', ''),
                        "trackCount": 0 # YTMusic search não retorna count na lista
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
            for track in album.get('tracks', []):
                # Alguns itens podem ser inválidos
                if not track.get('title'): continue

                artist_name = "Vários Artistas"
                if track.get('artists'):
                    artist_name = track['artists'][0].get('name')
                
                # Duração em ms
                duration_sec = track.get('duration_seconds', 0)
                
                tracks.append({
                    "trackNumber": 0, # YTMusic não garante numeração sequencial limpa na API
                    "trackName": track.get('title'),
                    "artistName": artist_name,
                    "collectionName": album.get('title'),
                    "durationMs": duration_sec * 1000,
                    "previewUrl": None,
                    # Dados para smart download
                    "artworkUrl": album['thumbnails'][-1]['url'] if album.get('thumbnails') else ""
                })

            return {
                "collectionId": browse_id,
                "collectionName": album.get('title'),
                "artistName": album['artists'][0]['name'] if album.get('artists') else "Vários",
                "artworkUrl": album['thumbnails'][-1]['url'] if album.get('thumbnails') else "",
                "year": album.get('year', ''),
                "tracks": tracks
            }
        except Exception as e:
            print(f"❌ Erro YTMusic Album Details: {e}")
            raise e