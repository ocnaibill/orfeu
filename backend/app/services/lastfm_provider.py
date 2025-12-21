"""
Last.fm API Provider

Fornece integração com a API do Last.fm para buscar artistas similares
e informações de gênero/tags.

API Docs: https://www.last.fm/api
"""
import os
import httpx
from typing import Optional

class LastfmProvider:
    """
    Provider para integração com Last.fm API.
    Usado para descobrir artistas similares aos favoritos do usuário.
    """
    
    BASE_URL = "http://ws.audioscrobbler.com/2.0/"
    
    @staticmethod
    def _get_api_key() -> str:
        """Retorna a API key do Last.fm configurada no ambiente."""
        key = os.getenv("LASTFM_API_KEY", "")
        if not key:
            print("⚠️ LASTFM_API_KEY não configurada!")
        return key
    
    @staticmethod
    def get_similar_artists(artist_name: str, limit: int = 10) -> list[dict]:
        """
        Busca artistas similares a um artista específico.
        
        Args:
            artist_name: Nome do artista base
            limit: Número máximo de artistas similares
            
        Returns:
            Lista com dicts contendo: name, match (0-1), mbid, url, image
        """
        if not artist_name:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "artist.getSimilar",
                "artist": artist_name,
                "api_key": api_key,
                "format": "json",
                "limit": limit,
                "autocorrect": 1  # Corrige erros de digitação
            }
            
            with httpx.Client() as client:
                response = client.get(
                    LastfmProvider.BASE_URL, 
                    params=params, 
                    timeout=10.0
                )
                
                if response.status_code != 200:
                    print(f"⚠️ Last.fm API Error: {response.status_code}")
                    return []
                
                data = response.json()
                
                # Verifica se houve erro na resposta
                if "error" in data:
                    print(f"⚠️ Last.fm Error: {data.get('message', 'Unknown error')}")
                    return []
                
                similar_artists = data.get("similarartists", {}).get("artist", [])
                
                # Normaliza os resultados
                results = []
                for artist in similar_artists:
                    # Pega a maior imagem disponível
                    images = artist.get("image", [])
                    image_url = ""
                    for img in reversed(images):  # Começa da maior
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    results.append({
                        "name": artist.get("name", ""),
                        "match": float(artist.get("match", 0)),  # Score de similaridade (0-1)
                        "mbid": artist.get("mbid", ""),
                        "url": artist.get("url", ""),
                        "image": image_url
                    })
                
                print(f"🎵 Last.fm: {len(results)} artistas similares a '{artist_name}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm get_similar_artists: {e}")
            return []
    
    @staticmethod
    def get_artist_info(artist_name: str) -> Optional[dict]:
        """
        Busca informações detalhadas de um artista, incluindo tags/gêneros.
        
        Args:
            artist_name: Nome do artista
            
        Returns:
            Dict com: name, mbid, url, tags (list), bio, stats
        """
        if not artist_name:
            return None
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return None
        
        try:
            params = {
                "method": "artist.getInfo",
                "artist": artist_name,
                "api_key": api_key,
                "format": "json",
                "autocorrect": 1
            }
            
            with httpx.Client() as client:
                response = client.get(
                    LastfmProvider.BASE_URL, 
                    params=params, 
                    timeout=10.0
                )
                
                if response.status_code != 200:
                    return None
                
                data = response.json()
                
                if "error" in data:
                    return None
                
                artist_data = data.get("artist", {})
                
                # Extrai tags
                tags = []
                for tag in artist_data.get("tags", {}).get("tag", []):
                    tags.append(tag.get("name", ""))
                
                # Pega a maior imagem
                images = artist_data.get("image", [])
                image_url = ""
                for img in reversed(images):
                    if img.get("#text"):
                        image_url = img["#text"]
                        break
                
                return {
                    "name": artist_data.get("name", artist_name),
                    "mbid": artist_data.get("mbid", ""),
                    "url": artist_data.get("url", ""),
                    "image": image_url,
                    "tags": tags,
                    "bio": artist_data.get("bio", {}).get("summary", ""),
                    "listeners": int(artist_data.get("stats", {}).get("listeners", 0)),
                    "playcount": int(artist_data.get("stats", {}).get("playcount", 0))
                }
                
        except Exception as e:
            print(f"❌ Erro Last.fm get_artist_info: {e}")
            return None
    
    @staticmethod
    def get_top_artists_by_tag(tag: str, limit: int = 10) -> list[dict]:
        """
        Busca os artistas mais populares de um gênero/tag específico.
        
        Args:
            tag: Nome do gênero/tag (ex: "indie", "rock", "electronic")
            limit: Número máximo de artistas
            
        Returns:
            Lista com dicts contendo: name, url, image
        """
        if not tag:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "tag.getTopArtists",
                "tag": tag,
                "api_key": api_key,
                "format": "json",
                "limit": limit
            }
            
            with httpx.Client() as client:
                response = client.get(
                    LastfmProvider.BASE_URL, 
                    params=params, 
                    timeout=10.0
                )
                
                if response.status_code != 200:
                    return []
                
                data = response.json()
                
                if "error" in data:
                    return []
                
                top_artists = data.get("topartists", {}).get("artist", [])
                
                results = []
                for artist in top_artists:
                    images = artist.get("image", [])
                    image_url = ""
                    for img in reversed(images):
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    results.append({
                        "name": artist.get("name", ""),
                        "url": artist.get("url", ""),
                        "image": image_url
                    })
                
                print(f"🏷️ Last.fm: {len(results)} top artistas para tag '{tag}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm get_top_artists_by_tag: {e}")
            return []
    
    # ===================================================================
    # MÉTODOS DE BUSCA
    # ===================================================================
    
    @staticmethod
    def search_tracks(query: str, limit: int = 20) -> list[dict]:
        """
        Busca músicas no Last.fm.
        
        Returns:
            Lista com dicts contendo: name, artist, url, listeners, mbid
        """
        if not query:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "track.search",
                "track": query,
                "api_key": api_key,
                "format": "json",
                "limit": limit
            }
            
            with httpx.Client() as client:
                response = client.get(LastfmProvider.BASE_URL, params=params, timeout=10.0)
                
                if response.status_code != 200:
                    return []
                
                data = response.json()
                if "error" in data:
                    return []
                
                tracks = data.get("results", {}).get("trackmatches", {}).get("track", [])
                
                results = []
                for track in tracks:
                    # Pega imagem se disponível
                    images = track.get("image", [])
                    image_url = ""
                    for img in reversed(images):
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    results.append({
                        "trackName": track.get("name", ""),
                        "artistName": track.get("artist", ""),
                        "url": track.get("url", ""),
                        "listeners": int(track.get("listeners", 0)),
                        "mbid": track.get("mbid", ""),
                        "artworkUrl": image_url,
                        "source": "LastFM"
                    })
                
                print(f"🔍 Last.fm: {len(results)} tracks para '{query}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm search_tracks: {e}")
            return []
    
    @staticmethod
    def search_albums(query: str, limit: int = 20) -> list[dict]:
        """
        Busca álbuns no Last.fm.
        """
        if not query:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "album.search",
                "album": query,
                "api_key": api_key,
                "format": "json",
                "limit": limit
            }
            
            with httpx.Client() as client:
                response = client.get(LastfmProvider.BASE_URL, params=params, timeout=10.0)
                
                if response.status_code != 200:
                    return []
                
                data = response.json()
                if "error" in data:
                    return []
                
                albums = data.get("results", {}).get("albummatches", {}).get("album", [])
                
                results = []
                for album in albums:
                    images = album.get("image", [])
                    image_url = ""
                    for img in reversed(images):
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    results.append({
                        "collectionName": album.get("name", ""),
                        "artistName": album.get("artist", ""),
                        "url": album.get("url", ""),
                        "mbid": album.get("mbid", ""),
                        "artworkUrl": image_url,
                        "source": "LastFM"
                    })
                
                print(f"🔍 Last.fm: {len(results)} álbuns para '{query}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm search_albums: {e}")
            return []
    
    @staticmethod
    def search_artists(query: str, limit: int = 20) -> list[dict]:
        """
        Busca artistas no Last.fm.
        """
        if not query:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "artist.search",
                "artist": query,
                "api_key": api_key,
                "format": "json",
                "limit": limit
            }
            
            with httpx.Client() as client:
                response = client.get(LastfmProvider.BASE_URL, params=params, timeout=10.0)
                
                if response.status_code != 200:
                    return []
                
                data = response.json()
                if "error" in data:
                    return []
                
                artists = data.get("results", {}).get("artistmatches", {}).get("artist", [])
                
                results = []
                for artist in artists:
                    images = artist.get("image", [])
                    image_url = ""
                    for img in reversed(images):
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    results.append({
                        "artistName": artist.get("name", ""),
                        "url": artist.get("url", ""),
                        "listeners": int(artist.get("listeners", 0)),
                        "mbid": artist.get("mbid", ""),
                        "artworkUrl": image_url,
                        "source": "LastFM"
                    })
                
                print(f"🔍 Last.fm: {len(results)} artistas para '{query}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm search_artists: {e}")
            return []
    
    @staticmethod
    def get_artist_top_albums(artist_name: str, limit: int = 20) -> list[dict]:
        """
        Busca os álbuns mais populares de um artista.
        """
        if not artist_name:
            return []
            
        api_key = LastfmProvider._get_api_key()
        if not api_key:
            return []
        
        try:
            params = {
                "method": "artist.getTopAlbums",
                "artist": artist_name,
                "api_key": api_key,
                "format": "json",
                "limit": limit,
                "autocorrect": 1
            }
            
            with httpx.Client() as client:
                response = client.get(LastfmProvider.BASE_URL, params=params, timeout=10.0)
                
                if response.status_code != 200:
                    return []
                
                data = response.json()
                if "error" in data:
                    return []
                
                albums = data.get("topalbums", {}).get("album", [])
                
                results = []
                for album in albums:
                    images = album.get("image", [])
                    image_url = ""
                    for img in reversed(images):
                        if img.get("#text"):
                            image_url = img["#text"]
                            break
                    
                    # Pega o artista do objeto aninhado
                    artist_obj = album.get("artist", {})
                    artist = artist_obj.get("name", artist_name) if isinstance(artist_obj, dict) else str(artist_obj)
                    
                    results.append({
                        "collectionName": album.get("name", ""),
                        "artistName": artist,
                        "url": album.get("url", ""),
                        "playcount": int(album.get("playcount", 0)),
                        "mbid": album.get("mbid", ""),
                        "artworkUrl": image_url,
                        "source": "LastFM"
                    })
                
                print(f"📀 Last.fm: {len(results)} álbuns de '{artist_name}'")
                return results
                
        except Exception as e:
            print(f"❌ Erro Last.fm get_artist_top_albums: {e}")
            return []
    
    # ===================================================================
    # MÉTODOS DE AUTENTICAÇÃO E SCROBBLING
    # ===================================================================
    
    @staticmethod
    def _get_api_secret() -> str:
        """Retorna o Shared Secret do Last.fm."""
        secret = os.getenv("LASTFM_API_SECRET", "")
        if not secret:
            print("⚠️ LASTFM_API_SECRET não configurado!")
        return secret
    
    @staticmethod
    def _generate_api_sig(params: dict) -> str:
        """
        Gera a assinatura MD5 para autenticação.
        Params devem ser ordenados alfabeticamente, concatenados, + secret no final.
        """
        import hashlib
        
        secret = LastfmProvider._get_api_secret()
        if not secret:
            return ""
        
        # Ordena os parâmetros alfabeticamente
        sorted_params = sorted(params.items())
        
        # Concatena key+value sem separadores
        sig_string = ""
        for key, value in sorted_params:
            sig_string += f"{key}{value}"
        
        # Adiciona o secret no final
        sig_string += secret
        
        # Gera MD5
        return hashlib.md5(sig_string.encode('utf-8')).hexdigest()
    
    @staticmethod
    def get_mobile_session(username: str, password: str) -> Optional[dict]:
        """
        Autentica usuário mobile e retorna session key.
        
        Returns:
            Dict com: session_key, username, subscriber
            None se falhar
        """
        api_key = LastfmProvider._get_api_key()
        secret = LastfmProvider._get_api_secret()
        
        if not api_key or not secret:
            return None
        
        try:
            # Parâmetros para assinatura (SEM api_sig e format)
            sig_params = {
                "api_key": api_key,
                "method": "auth.getMobileSession",
                "password": password,
                "username": username
            }
            
            api_sig = LastfmProvider._generate_api_sig(sig_params)
            
            # Parâmetros do POST
            post_data = {
                **sig_params,
                "api_sig": api_sig,
                "format": "json"
            }
            
            with httpx.Client() as client:
                response = client.post(
                    LastfmProvider.BASE_URL,
                    data=post_data,
                    timeout=15.0
                )
                
                data = response.json()
                
                if "error" in data:
                    print(f"❌ Last.fm auth error: {data.get('message')}")
                    return None
                
                session = data.get("session", {})
                return {
                    "session_key": session.get("key"),
                    "username": session.get("name"),
                    "subscriber": session.get("subscriber", 0)
                }
                
        except Exception as e:
            print(f"❌ Erro Last.fm get_mobile_session: {e}")
            return None
    
    @staticmethod
    def scrobble_track(
        artist: str,
        track: str,
        session_key: str,
        album: Optional[str] = None,
        timestamp: Optional[int] = None,
        duration: Optional[int] = None
    ) -> bool:
        """
        Envia um scrobble para o Last.fm.
        
        Args:
            artist: Nome do artista
            track: Nome da música
            session_key: Session key do usuário
            album: Nome do álbum (opcional)
            timestamp: Unix timestamp do início da reprodução
            duration: Duração em segundos
            
        Returns:
            True se sucesso, False se falhar
        """
        import time
        
        api_key = LastfmProvider._get_api_key()
        if not api_key or not session_key:
            return False
        
        try:
            # Timestamp padrão: agora
            if not timestamp:
                timestamp = int(time.time())
            
            # Parâmetros para assinatura
            sig_params = {
                "api_key": api_key,
                "artist": artist,
                "method": "track.scrobble",
                "sk": session_key,
                "timestamp": str(timestamp),
                "track": track
            }
            
            if album:
                sig_params["album"] = album
            if duration:
                sig_params["duration"] = str(duration)
            
            api_sig = LastfmProvider._generate_api_sig(sig_params)
            
            post_data = {
                **sig_params,
                "api_sig": api_sig,
                "format": "json"
            }
            
            with httpx.Client() as client:
                response = client.post(
                    LastfmProvider.BASE_URL,
                    data=post_data,
                    timeout=10.0
                )
                
                data = response.json()
                
                if "error" in data:
                    print(f"❌ Scrobble error: {data.get('message')}")
                    return False
                
                scrobbles = data.get("scrobbles", {})
                accepted = scrobbles.get("@attr", {}).get("accepted", 0)
                
                if int(accepted) > 0:
                    print(f"✅ Scrobbled: {artist} - {track}")
                    return True
                else:
                    print(f"⚠️ Scrobble ignorado: {artist} - {track}")
                    return False
                    
        except Exception as e:
            print(f"❌ Erro Last.fm scrobble_track: {e}")
            return False
    
    @staticmethod
    def update_now_playing(
        artist: str,
        track: str,
        session_key: str,
        album: Optional[str] = None,
        duration: Optional[int] = None
    ) -> bool:
        """
        Atualiza o 'Now Playing' do usuário no Last.fm.
        Chamado quando uma música começa a tocar.
        """
        api_key = LastfmProvider._get_api_key()
        if not api_key or not session_key:
            return False
        
        try:
            sig_params = {
                "api_key": api_key,
                "artist": artist,
                "method": "track.updateNowPlaying",
                "sk": session_key,
                "track": track
            }
            
            if album:
                sig_params["album"] = album
            if duration:
                sig_params["duration"] = str(duration)
            
            api_sig = LastfmProvider._generate_api_sig(sig_params)
            
            post_data = {
                **sig_params,
                "api_sig": api_sig,
                "format": "json"
            }
            
            with httpx.Client() as client:
                response = client.post(
                    LastfmProvider.BASE_URL,
                    data=post_data,
                    timeout=10.0
                )
                
                data = response.json()
                
                if "error" in data:
                    return False
                
                return "nowplaying" in data
                    
        except Exception as e:
            print(f"❌ Erro Last.fm update_now_playing: {e}")
            return False
