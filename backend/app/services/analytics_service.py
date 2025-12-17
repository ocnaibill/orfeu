from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from datetime import datetime, timedelta
from app import models
import urllib.parse

class AnalyticsService:
    
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
        """
        # Pega mais histórico para filtrar duplicatas de álbum
        history = db.query(models.ListenHistory.track_id, models.ListenHistory.played_at)\
            .filter(models.ListenHistory.user_id == user_id)\
            .order_by(desc(models.ListenHistory.played_at))\
            .limit(limit * 3)\
            .all()
            
        recent_albums = []
        seen_albums = set()
        
        for track_id, played_at in history:
            t = db.query(models.Track).filter(models.Track.id == track_id).first()
            if t and t.album:
                # Cria uma chave única para evitar repetir o mesmo álbum consecutivamente
                album_key = f"{t.artist} - {t.album}"
                
                if album_key in seen_albums:
                    continue
                
                seen_albums.add(album_key)
                
                # Monta objeto com tipo especial 'album_search'
                # O ID começa com 'query:' para o frontend saber que precisa buscar o ID real
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
