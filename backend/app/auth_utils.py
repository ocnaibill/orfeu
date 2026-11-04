from passlib.context import CryptContext
from datetime import datetime, timedelta, timezone
from jose import jwt
from typing import Optional
import os

# SECRET_KEY é obrigatória: sem default, para nunca subir com uma chave conhecida.
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY or len(SECRET_KEY) < 32:
    raise RuntimeError(
        "SECRET_KEY ausente ou curta (<32 chars). Gere uma com: openssl rand -hex 32"
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = int(os.getenv("ACCESS_TOKEN_EXPIRE_DAYS", "90"))
# Token de mídia: escopo restrito, aceito só em ?mt= das rotas de mídia (stream/capa/letra).
# Existe para clientes que não conseguem mandar header (player HTML5 da web).
MEDIA_TOKEN_EXPIRE_HOURS = int(os.getenv("MEDIA_TOKEN_EXPIRE_HOURS", "12"))
MEDIA_SCOPE = "media"


def media_auth_required() -> bool:
    """MEDIA_AUTH_REQUIRED=false deixa stream/capa/letra abertos (SÓ para a transição:
    servidor novo no ar enquanto os apps antigos, que não mandam token, não atualizaram).
    Lido a cada requisição, então dá para virar a chave sem recompilar."""
    return os.getenv("MEDIA_AUTH_REQUIRED", "true").strip().lower() != "false"

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS))
    to_encode["exp"] = expire
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_media_token(username: str) -> str:
    return create_access_token(
        data={"sub": username, "scope": MEDIA_SCOPE},
        expires_delta=timedelta(hours=MEDIA_TOKEN_EXPIRE_HOURS),
    )
