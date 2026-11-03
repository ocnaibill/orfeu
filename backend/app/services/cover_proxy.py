import hashlib
import time
from typing import Dict

from app.core import config

# --- Cache de Proxy de Imagem ---
# Dict mutado in place: nunca reatribuir.
SHORT_URL_MAP: Dict[str, dict] = {}
PROXY_EXPIRY_SECONDS = 3600

def get_short_cover_url(filename: str) -> str:
    hash_object = hashlib.sha256(filename.encode())
    short_hash = hash_object.hexdigest()[:12]
    SHORT_URL_MAP[short_hash] = {
        "filename": filename,
        "expires": time.time() + PROXY_EXPIRY_SECONDS
    }
    # Substitua pelo seu domínio real em produção se necessário, ou use relativa
    return f"{config.PUBLIC_BASE_URL}/cover/short/{short_hash}"
