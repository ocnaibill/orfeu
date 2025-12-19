from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from datetime import datetime, timedelta
from app import models
import urllib.parse
import httpx

class AnalyticsService:
    
    TIDAL_API = "https://triton.squid.wtf"
    
    @staticmethod
    async def _get_artist_image(artist_name: str) -> str:
        """Busca a imagem do artista no Tidal."""
        if not artist_name or artist_name == "Nenhum" or artist_name == "Desconhecido":
            return ""
        
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(f"{AnalyticsService.TIDAL_API}/search/artists", params={"q": artist_name, "limit": 1})
                if resp.status_code == 200:
                    data = resp.json()
                    items = data.get("data", {}).get("items", []) if isinstance(data.get("data"), dict) else data.get("data", [])
                    if items and len(items) > 0:
                        artist_data = items[0]
                        # Tenta diferentes estruturas de imagem
                        picture = artist_data.get("picture") or artist_data.get("image") or artist_data.get("artworkUrl")
                        if picture:
                            if isinstance(picture, str):
                                return picture if picture.startswith("http") else f"https://resources.tidal.com/images/{picture.replace('-', '/')}/750x750.jpg"
                            elif isinstance(picture, dict):
                                return picture.get("large") or picture.get("medium") or picture.get("small", "")
        except Exception as e:
            print(f"⚠️ Erro ao buscar imagem do artista: {e}")
        return ""
    
    @staticmethod
    def get_user_stats(db: Session, user_id: int, days: int = 30):
        """
        Retorna estatísticas gerais do usuário nos últimos X dias.
        """
        start_date = datetime.utcnow() - timedelta(days=days)
        
        base_query = db.query(models.ListenHistory).filter(
            models.ListenHistory.user_id == user_id,
            models.ListenHistory.played_at >= start_date
        )

        total_seconds = base_query.with_entities(func.sum(models.ListenHistory.duration_listened)).scalar() or 0
        total_minutes = int(total_seconds / 60)
        total_plays = base_query.count()

        top_artist = db.query(models.Track.artist, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == user_id, models.ListenHistory.played_at >= start_date)\
            .group_by(models.Track.artist)\
            .order_by(desc('count'))\
            .first()

        # Conta artistas únicos ouvidos
        unique_artists = db.query(func.count(func.distinct(models.Track.artist)))\
            .join(models.ListenHistory)\
            .filter(
                models.ListenHistory.user_id == user_id,
                models.ListenHistory.played_at >= start_date,
                models.Track.artist != None,
                models.Track.artist != "Desconhecido"
            ).scalar() or 0

        # Conta gêneros únicos ouvidos
        unique_genres = db.query(func.count(func.distinct(models.Track.genre)))\
            .join(models.ListenHistory)\
            .filter(
                models.ListenHistory.user_id == user_id,
                models.ListenHistory.played_at >= start_date,
                models.Track.genre != None,
                models.Track.genre != ""
            ).scalar() or 0

        return {
            "period_days": days,
            "total_minutes": total_minutes,
            "total_plays": total_plays,
            "top_artist": top_artist[0] if top_artist else "Nenhum",
            "top_artist_plays": top_artist[1] if top_artist else 0,
            "unique_artists": unique_artists,
            "unique_genres": unique_genres
        }
    
    @staticmethod
    async def get_user_stats_async(db: Session, user_id: int, days: int = 30):
        """
        Versão assíncrona que inclui imagem do artista top.
        """
        stats = AnalyticsService.get_user_stats(db, user_id, days)
        
        # Busca a imagem do artista top
        if stats["top_artist"] and stats["top_artist"] != "Nenhum":
            artist_image = await AnalyticsService._get_artist_image(stats["top_artist"])
            stats["top_artist_image"] = artist_image
        else:
            stats["top_artist_image"] = ""
        
        return stats

    @staticmethod
    def get_top_tracks(db: Session, user_id: int, limit: int = 10, days: int = 30):
        start_date = datetime.utcnow() - timedelta(days=days)
        
        results = db.query(models.Track, func.count(models.ListenHistory.id).label('play_count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == user_id, models.ListenHistory.played_at >= start_date)\
            .group_by(models.Track.id)\
            .order_by(desc('play_count'))\
            .limit(limit)\
            .all()
            
        return [
            {
                "filename": t.filename,
                "display_name": t.title,
                "artist": t.artist,
                "plays": count,
                # Codifica o filename para a URL ser válida
                "coverProxyUrl": f"https://orfeu.ocnaibill.dev/cover?filename={urllib.parse.quote(t.filename)}" if t.filename else None
            }
            for t, count in results
        ]

    @staticmethod
    def get_global_rankings(db: Session):
        time_ranking = db.query(models.User.username, func.sum(models.ListenHistory.duration_listened).label('total_sec'))\
            .join(models.ListenHistory)\
            .group_by(models.User.id)\
            .order_by(desc('total_sec'))\
            .limit(10)\
            .all()

        return {
            "most_active_users": [
                {"username": r[0], "minutes": int((r[1] or 0) / 60)} 
                for r in time_ranking
            ]
        }
    
    @staticmethod
    def create_retro_playlist(db: Session, user_id: int, month: int, year: int):
        playlist_name = f"Retrospectiva {month}/{year}"
        
        exists = db.query(models.Playlist).filter(
            models.Playlist.user_id == user_id, 
            models.Playlist.name == playlist_name
        ).first()
        
        if exists: return exists

        top_tracks = db.query(models.Track.id)\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == user_id)\
            .group_by(models.Track.id)\
            .order_by(desc(func.count(models.ListenHistory.id)))\
            .limit(20)\
            .all()
            
        if not top_tracks: return None

        new_playlist = models.Playlist(name=playlist_name, user_id=user_id, is_public=True)
        db.add(new_playlist)
        db.commit()
        db.refresh(new_playlist)

        for i, (track_id,) in enumerate(top_tracks):
            item = models.PlaylistItem(playlist_id=new_playlist.id, track_id=track_id, order=i)
            db.add(item)
        
        db.commit()
        return new_playlist

    # --- RECENTEMENTE TOCADOS (AGORA AGRUPADO POR ÁLBUM) ---
    @staticmethod
    def get_recently_played(db: Session, user_id: int, limit: int = 10):
        """
        Retorna os álbuns das últimas músicas ouvidas.
        Mostra apenas uma entrada por álbum (o mais recente).
        """
        import re
        from collections import Counter
        
        def normalize_string(s: str) -> str:
            """Normaliza string removendo acentos e caracteres especiais"""
            if not s:
                return ""
            # Lowercase
            s = s.lower().strip()
            # Remove caracteres especiais e múltiplos espaços
            s = re.sub(r'[^\w\s]', '', s)
            s = re.sub(r'\s+', ' ', s)
            return s
        
        def get_album_info_from_tracks(db: Session, album_id: str) -> tuple:
            """
            Busca as informações do álbum baseado nas tracks que têm esse album_id.
            Retorna o nome do álbum e artista mais comuns entre as tracks.
            Isso evita usar metadados errados de uma única track.
            """
            tracks_with_album = db.query(models.Track.album, models.Track.artist)\
                .filter(models.Track.album_id == album_id)\
                .all()
            
            if not tracks_with_album:
                return None, None
            
            # Conta as ocorrências de cada nome de álbum e artista
            album_names = Counter([t.album for t in tracks_with_album if t.album])
            artist_names = Counter([t.artist for t in tracks_with_album if t.artist])
            
            # Retorna os mais comuns
            most_common_album = album_names.most_common(1)[0][0] if album_names else None
            most_common_artist = artist_names.most_common(1)[0][0] if artist_names else None
            
            return most_common_album, most_common_artist
        
        # Pega mais histórico para filtrar duplicatas de álbum
        history = db.query(models.ListenHistory.track_id, models.ListenHistory.played_at)\
            .filter(models.ListenHistory.user_id == user_id)\
            .order_by(desc(models.ListenHistory.played_at))\
            .limit(limit * 10)\
            .all()
            
        recent_albums = []
        seen_albums = set()
        
        for track_id, played_at in history:
            t = db.query(models.Track).filter(models.Track.id == track_id).first()
            if not t or not t.album:
                continue
                
            # Cria chave única para o álbum (normalizada)
            if t.album_id:
                album_key = f"id:{t.album_id}"
            else:
                # Normaliza: lowercase, sem acentos, sem caracteres especiais
                artist_norm = normalize_string(t.artist or "")
                album_norm = normalize_string(t.album or "")
                album_key = f"{artist_norm}|{album_norm}"
            
            # Pula se já vimos este álbum
            if album_key in seen_albums:
                continue
            
            seen_albums.add(album_key)
            
            # Se tiver album_id salvo, busca informações corretas do álbum
            if t.album_id:
                # Primeiro, tenta buscar em SavedAlbum (cache confiável)
                saved_album = db.query(models.SavedAlbum)\
                    .filter(models.SavedAlbum.album_id == t.album_id)\
                    .first()
                
                if saved_album:
                    # Usa os metadados do álbum salvo (mais confiável)
                    album_title = saved_album.title
                    album_artist = saved_album.artist
                else:
                    # Busca nas tracks: pega os metadados mais comuns
                    # para evitar usar metadados errados de uma única track
                    common_album, common_artist = get_album_info_from_tracks(db, t.album_id)
                    album_title = common_album or t.album
                    album_artist = common_artist or t.artist
                
                recent_albums.append({
                    "type": "album",
                    "id": t.album_id,
                    "title": album_title,
                    "artist": album_artist,
                    "imageUrl": f"https://orfeu.ocnaibill.dev/cover?filename={urllib.parse.quote(t.filename)}",
                    "played_at": played_at
                })
            else:
                # Fallback: precisa buscar (pode retornar álbum errado)
                recent_albums.append({
                    "type": "album_search", 
                    "title": t.album,
                    "artist": t.artist,
                    "imageUrl": f"https://orfeu.ocnaibill.dev/cover?filename={urllib.parse.quote(t.filename)}",
                    "search_query": f"{t.artist} {t.album}",
                    "played_at": played_at
                })
            
            if len(recent_albums) >= limit:
                break
        
        return recent_albums

    @staticmethod
    def get_user_favorite_genres(db: Session, user_id: int, limit: int = 6, days: int = 90):
        """
        Retorna os gêneros mais ouvidos pelo usuário nos últimos X dias.
        Baseado no tempo de escuta acumulado por gênero.
        """
        from datetime import datetime, timedelta
        
        start_date = datetime.utcnow() - timedelta(days=days)
        
        # Agrupa por gênero e soma tempo de escuta
        results = db.query(
            models.Track.genre,
            func.sum(models.ListenHistory.duration_listened).label('total_time'),
            func.count(models.ListenHistory.id).label('play_count')
        ).join(models.ListenHistory)\
         .filter(
            models.ListenHistory.user_id == user_id,
            models.ListenHistory.played_at >= start_date,
            models.Track.genre != None,
            models.Track.genre != "",
            models.Track.genre != "Desconhecido"
         )\
         .group_by(models.Track.genre)\
         .order_by(desc('total_time'))\
         .limit(limit)\
         .all()
        
        return [
            {
                "name": genre,
                "total_minutes": int((total_time or 0) / 60),
                "play_count": play_count
            }
            for genre, total_time, play_count in results
        ]
