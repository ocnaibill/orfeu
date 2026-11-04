from typing import Optional

from fastapi import HTTPException, Depends, Query
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.database import get_db
from app import models, auth_utils

# Esquema de Segurança
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")
# Variante que não falha sozinha quando falta o header (rotas de mídia aceitam ?mt= também)
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="token", auto_error=False)


def _user_from_token(token: str, db: Session, *, media: bool) -> models.User:
    """Valida o JWT e devolve o usuário.

    media=False: aceita só o token de acesso normal (sem `scope`).
    media=True : aceita só o token de mídia (scope == "media").
    """
    try:
        payload = jwt.decode(token, auth_utils.SECRET_KEY, algorithms=[auth_utils.ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido")
    username = payload.get("sub")
    if username is None or (payload.get("scope") == auth_utils.MEDIA_SCOPE) != media:
        raise HTTPException(status_code=401, detail="Token inválido")

    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise HTTPException(status_code=401, detail="Usuário não encontrado")
    return user


# --- Helper de Usuário Atual ---
async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    return _user_from_token(token, db, media=False)


async def get_media_user(
    token: Optional[str] = Depends(oauth2_scheme_optional),
    mt: Optional[str] = Query(None, description="Token de mídia (GET /auth/media-token) para clientes sem header"),
    db: Session = Depends(get_db),
):
    """Rotas de mídia: Bearer normal no header OU token de mídia em ?mt=."""
    if token:
        return _user_from_token(token, db, media=False)
    if mt:
        return _user_from_token(mt, db, media=True)
    raise HTTPException(status_code=401, detail="Not authenticated", headers={"WWW-Authenticate": "Bearer"})
