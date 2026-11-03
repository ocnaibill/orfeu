from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.services.analytics_service import AnalyticsService

router = APIRouter(tags=["analytics"])


# --- ANALYTICS (PERFIL) ---
@router.get("/users/me/analytics/summary")
async def get_my_analytics(days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return await AnalyticsService.get_user_stats_async(db, current_user.id, days)

@router.get("/users/me/analytics/top-tracks")
def get_my_top_tracks(limit: int = 10, days: int = 30, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_top_tracks(db, current_user.id, limit, days)


@router.get("/analytics/rankings")
def get_global_rankings(db: Session = Depends(get_db)):
    """
    Retorna o ranking global de usuários (quem ouviu mais).
    """
    return AnalyticsService.get_global_rankings(db)

@router.post("/users/me/analytics/generate-playlist")
def generate_retro_playlist(month: int, year: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Gera a playlist automática do mês e salva na conta do usuário.
    """
    pl = AnalyticsService.create_retro_playlist(db, current_user.id, month, year)
    if not pl:
        raise HTTPException(400, "Não há dados suficientes para gerar playlist.")
    return {"status": "created", "playlist_id": pl.id, "name": pl.name}
