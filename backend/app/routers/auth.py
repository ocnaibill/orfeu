import os

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app import auth_utils, models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import Token, UserCreate

router = APIRouter(tags=["auth"])


@router.post("/auth/register", response_model=Token)
def register(user: UserCreate, db: Session = Depends(get_db)):
    if os.getenv("ALLOW_REGISTRATION", "false").lower() != "true":
        raise HTTPException(status_code=403, detail="Cadastro desativado neste servidor")
    # Verifica se existe
    db_user = db.query(models.User).filter(models.User.username == user.username).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Username já cadastrado")
    
    # Cria usuário
    hashed_pwd = auth_utils.get_password_hash(user.password)
    db_user = models.User(
        username=user.username, 
        email=user.email, 
        full_name=user.full_name, 
        hashed_password=hashed_pwd
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    
    # Gera Token
    access_token = auth_utils.create_access_token(data={"sub": db_user.username})
    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/token", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if not user or not auth_utils.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuário ou senha incorretos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = auth_utils.create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@router.get("/auth/media-token")
def media_token(current_user: models.User = Depends(get_current_user)):
    """Token de curta duração e escopo restrito para URLs de mídia (?mt=), sem expor o token da conta."""
    return {
        "token": auth_utils.create_media_token(current_user.username),
        "expires_in": auth_utils.MEDIA_TOKEN_EXPIRE_HOURS * 3600,
    }
