import httpx
from urllib.parse import quote

class ReleaseDateProvider:
    """
    Serviço especializado em encontrar a data exata de lançamento (YYYY-MM-DD)
    para desempatar álbuns do mesmo ano.
    Usa a API do iTunes Store que retorna datas precisas.
    """
    
    @staticmethod
    def get_exact_date(artist: str, album_name: str) -> str:
        try:
            # Busca específica por álbum
            term = f"{artist} {album_name}"
            url = "https://itunes.apple.com/search"
            params = {
                "term": term,
                "media": "music",
                "entity": "album",
                "limit": 1
            }
            
            with httpx.Client() as client:
                resp = client.get(url, params=params, timeout=5.0)
                if resp.status_code == 200:
                    data = resp.json()
                    if data['resultCount'] > 0:
                        # Retorna algo como "2025-08-22T07:00:00Z"
                        return data['results'][0].get('releaseDate', '')
            
            return ""
        except Exception as e:
            print(f"⚠️ Falha ao buscar data exata para '{album_name}': {e}")
            return ""