from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import LastfmAuthRequest, LastfmScrobbleRequest

router = APIRouter(tags=["lastfm"])


@router.post("/lastfm/auth")
def lastfm_authenticate(
    req: LastfmAuthRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Autentica o usuário no Last.fm e salva a session key.
    O usuário precisa fornecer seu username e senha do Last.fm.
    """
    from app.services.lastfm_provider import LastfmProvider
    
    result = LastfmProvider.get_mobile_session(req.username, req.password)
    
    if not result or not result.get("session_key"):
        raise HTTPException(401, "Falha na autenticação do Last.fm. Verifique seu username e senha.")
    
    # Salva a session key no perfil do usuário
    current_user.lastfm_session_key = result["session_key"]
    current_user.lastfm_username = result.get("username", req.username)
    db.commit()
    
    return {
        "status": "connected",
        "lastfm_username": current_user.lastfm_username,
        "message": "Last.fm conectado com sucesso! Seus plays serão enviados automaticamente."
    }

@router.delete("/lastfm/auth")
def lastfm_disconnect(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Desconecta o Last.fm do usuário."""
    current_user.lastfm_session_key = None
    current_user.lastfm_username = None
    db.commit()
    
    return {"status": "disconnected", "message": "Last.fm desconectado."}

@router.get("/users/me/lastfm")
def get_lastfm_status(current_user: models.User = Depends(get_current_user)):
    """Retorna o status da conexão com o Last.fm."""
    return {
        "connected": current_user.lastfm_session_key is not None,
        "username": current_user.lastfm_username
    }

@router.post("/lastfm/scrobble")
async def lastfm_scrobble(
    req: LastfmScrobbleRequest,
    current_user: models.User = Depends(get_current_user)
):
    """
    Envia um scrobble para o Last.fm.
    Chamado quando uma música é ouvida por mais de 50% ou 4 minutos.
    """
    from app.services.lastfm_provider import LastfmProvider
    
    if not current_user.lastfm_session_key:
        return {"status": "skipped", "reason": "Last.fm não conectado"}
    
    success = await run_in_threadpool(
        LastfmProvider.scrobble_track,
        req.artist,
        req.track,
        current_user.lastfm_session_key,
        req.album,
        req.timestamp,
        req.duration
    )
    
    if success:
        return {"status": "scrobbled", "artist": req.artist, "track": req.track}
    else:
        raise HTTPException(status_code=502, detail="Falha ao enviar scrobble ao Last.fm")

@router.post("/lastfm/now-playing")
async def lastfm_update_now_playing(
    req: LastfmScrobbleRequest,
    current_user: models.User = Depends(get_current_user)
):
    """
    Atualiza o 'Now Playing' no Last.fm.
    Chamado quando uma música começa a tocar.
    """
    from app.services.lastfm_provider import LastfmProvider
    
    if not current_user.lastfm_session_key:
        return {"status": "skipped", "reason": "Last.fm não conectado"}
    
    success = await run_in_threadpool(
        LastfmProvider.update_now_playing,
        req.artist,
        req.track,
        current_user.lastfm_session_key,
        req.album,
        req.duration
    )
    
    if not success:
        raise HTTPException(status_code=502, detail="Falha ao atualizar o Now Playing no Last.fm")
    return {"status": "updated"}
