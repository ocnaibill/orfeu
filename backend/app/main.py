"""Orfeu API — ponto de entrada.

Este arquivo só monta o app: config, lifespan, routers e o mount do web app.
Toda a lógica das rotas vive em app/routers/*.
"""
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app import auth_utils, models
from app.core import config
from app.database import engine
from app.routers import (
    analytics, auth, catalog, collection, downloads, genres, history, home,
    lastfm, library, lyrics, media, playlists, system, users,
)
from app.services import genre_cache

# Cria tabelas se não existirem
models.Base.metadata.create_all(bind=engine)

# Diretórios públicos (OTA updates, capas de playlist)
config.ensure_dirs()

if not auth_utils.media_auth_required():
    print("⚠️  MEDIA_AUTH_REQUIRED=false: stream/capa/letra estão ABERTOS. Use só na transição.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await genre_cache.startup()
    yield
    await genre_cache.shutdown()


app = FastAPI(title="Orfeu API", version=config.API_VERSION, lifespan=lifespan)

# A ordem de registro é a mesma do main.py original.
for _router in (
    system, auth, users, lastfm, collection, playlists, home, analytics,
    genres, history, library, catalog, downloads, media, lyrics,
):
    app.include_router(_router.router)

# --- Web App (SPA) ---
# Montado POR ÚLTIMO: o mount em "/app" não pode esconder rotas como /app/latest_version.
if os.path.exists(config.WEB_APP_DIR):
    app.mount("/app", StaticFiles(directory=config.WEB_APP_DIR, html=True), name="webapp")
    print("🌐 Web App montado em /app")
