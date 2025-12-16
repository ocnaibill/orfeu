from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from datetime import datetime, timedelta
from app import models

class AnalyticsService:
    
    @staticmethod
    def get_user_stats(db: Session, user_id: int, days: int = 30):
        """
        Retorna estatísticas gerais do usuário nos últimos X dias.
        """
        start_date = datetime.utcnow() - timedelta(days=days)
        
        # Filtro base
        base_query = db.query(models.ListenHistory).filter(
            models.ListenHistory.user_id == user_id,
            models.ListenHistory.played_at >= start_date
        )

        # 1. Total de Minutos
        total_seconds = base_query.with_entities(func.sum(models.ListenHistory.duration_listened)).scalar() or 0
        total_minutes = int(total_seconds / 60)

        # 2. Total de Plays
        total_plays = base_query.count()

        # 3. Top Artista
        top_artist = db.query(models.Track.artist, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == user_id, models.ListenHistory.played_at >= start_date)\
            .group_by(models.Track.artist)\
            .order_by(desc('count'))\
            .first()

        return {
            "period_days": days,
            "total_minutes": total_minutes,
            "total_plays": total_plays,
            "top_artist": top_artist[0] if top_artist else "Nenhum",
            "top_artist_plays": top_artist[1] if top_artist else 0
        }

    @staticmethod
    def get_top_tracks(db: Session, user_id: int, limit: int = 10, days: int = 30):
        """
        Retorna as músicas mais ouvidas.
        """
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
                # Gera URL da capa se necessário
                "coverProxyUrl": f"https://orfeu.ocnaibill.dev/cover?filename={t.filename}" if t.filename else None
            }
            for t, count in results
        ]

    @staticmethod
    def get_global_rankings(db: Session):
        """
        Ranking global de usuários.
        """
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
        """
        Cria uma playlist persistente "Retrospectiva Mês/Ano".
        """
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
    
    @staticmethod
    def get_recently_played(db: Session, user_id: int, limit: int = 10):
        """
        Retorna as últimas músicas ouvidas (Histórico Inverso).
        Agrupa para não mostrar a mesma música 5x seguida.
        """
        # Subquery para pegar o MAX(id) de cada track no histórico recente
        # Isso é uma forma simples de 'distinct' por track ordenado por tempo
        history = db.query(models.ListenHistory.track_id, func.max(models.ListenHistory.played_at).label('last_played'))\
            .filter(models.ListenHistory.user_id == user_id)\
            .group_by(models.ListenHistory.track_id)\
            .order_by(desc('last_played'))\
            .limit(limit)\
            .all()
            
        recent_tracks = []
        for track_id, played_at in history:
            t = db.query(models.Track).filter(models.Track.id == track_id).first()
            if t:
                recent_tracks.append({
                    "type": "song", # Por enquanto retornamos como música, mas a UI de álbum aceita
                    "title": t.title,
                    "artist": t.artist,
                    "imageUrl": f"https://orfeu.ocnaibill.dev/cover?filename={t.filename}", # Endpoint de capa
                    "filename": t.filename,
                    "played_at": played_at
                })
        
        return recent_tracks