import os

# Diretórios (dentro do container)
MUSIC_DIR = os.getenv("MUSIC_DIR", "/downloads")
PUBLIC_DIR = os.getenv("PUBLIC_DIR", "/downloads_public")
PLAYLIST_COVERS_DIR = f"{PUBLIC_DIR}/playlist_covers"
PROFILE_IMAGES_DIR = f"{PUBLIC_DIR}/profile_images"
WEB_APP_DIR = f"{PUBLIC_DIR}/web"

# Arquivo de configuração de atualizações (OTA)
UPDATES_CONFIG_PATH = os.getenv("UPDATES_CONFIG_PATH", "/app/updates.json")

# URL pública do servidor (sem barra final)
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "https://orfeu.ocnaibill.dev").rstrip("/")

API_VERSION = "2.4.0"


def ensure_dirs():
    os.makedirs(PUBLIC_DIR, exist_ok=True)
    os.makedirs(PLAYLIST_COVERS_DIR, exist_ok=True)
