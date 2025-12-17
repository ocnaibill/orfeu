import httpx
import urllib.parse

class MetadataProvider:
    """
    Serviço auxiliar para buscar metadados que faltam nas APIs principais (Tidal/YT),
    principalmente Gêneros, usando a API pública do iTunes.
    """
    
    @staticmethod
    def get_genre(artist: str, album_title: str = "", track_title: str = "") -> str:
        """
        Tenta descobrir o gênero principal. 
        Prioridade: Busca por Álbum -> Busca por Track -> Retorna None
        """
        try:
            # 1. Tenta buscar pelo Álbum (Mais preciso para gênero)
            if album_title and album_title.lower() not in ["single", "unknown", ""]:
                term = f"{artist} {album_title}"
                genre = MetadataProvider._query_itunes(term, entity="album")
                if genre: return genre

            # 2. Se falhar ou for single, tenta pela música
            if track_title:
                term = f"{artist} {track_title}"
                genre = MetadataProvider._query_itunes(term, entity="song")
                if genre: return genre
                
            return "Desconhecido"
            
        except Exception as e:
            print(f"⚠️ Erro ao buscar gênero externo: {e}")
            return "Desconhecido"

    @staticmethod
    def _query_itunes(term: str, entity: str) -> str:
        try:
            encoded_term = urllib.parse.quote(term)
            url = f"https://itunes.apple.com/search?term={encoded_term}&entity={entity}&limit=1"
            
            with httpx.Client() as client:
                resp = client.get(url, timeout=3.0) # Timeout curto para não travar o app
                if resp.status_code == 200:
                    data = resp.json()
                    if data.get('resultCount', 0) > 0:
                        return data['results'][0].get('primaryGenreName')
        except:
            pass
        return None