import asyncio
import time
from typing import Optional, Dict
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app import models
from app.services.catalog_provider import CatalogProvider

# =====================================================
# CACHE DE GÊNEROS - Sistema de atualização automática
# =====================================================
# ATENÇÃO: _cache_last_refresh e _genre_cache_task são reatribuídos (global)
# apenas neste módulo. Quem precisar lê-los deve usar genre_cache._nome
# (nunca "from ... import _nome").

# Lista de todos os gêneros suportados
SUPPORTED_GENRES = [
    "pop", "rock", "hip hop", "rap", "r&b", "electronic", "edm",
    "jazz", "classical", "country", "latin", "reggaeton", "k-pop",
    "j-pop", "metal", "indie", "alternative", "soul", "funk", 
    "blues", "reggae", "folk", "acoustic", "dance", "house",
    "techno", "ambient", "soundtrack", "anime", "brazilian",
    "mpb", "sertanejo", "pagode", "forró", "bossa nova"
]

# Queries otimizadas para cada gênero
GENRE_QUERIES = {
    "pop": "top pop hits 2024",
    "rock": "best rock songs",
    "hip hop": "hip hop hits 2024",
    "hip-hop": "hip hop hits 2024",
    "rap": "rap hits 2024",
    "r&b": "r&b hits 2024",
    "rnb": "r&b hits 2024",
    "electronic": "electronic dance music",
    "edm": "edm hits",
    "jazz": "jazz classics",
    "classical": "classical music popular",
    "country": "country hits 2024",
    "latin": "latin hits 2024",
    "reggaeton": "reggaeton hits 2024",
    "k-pop": "kpop hits 2024",
    "kpop": "kpop hits 2024",
    "j-pop": "jpop hits",
    "jpop": "jpop hits",
    "metal": "metal songs",
    "indie": "indie music hits",
    "alternative": "alternative rock hits",
    "soul": "soul music classics",
    "funk": "funk music hits",
    "blues": "blues music",
    "reggae": "reggae hits",
    "folk": "folk music",
    "acoustic": "acoustic songs",
    "dance": "dance music hits",
    "house": "house music",
    "techno": "techno music",
    "ambient": "ambient music",
    "soundtrack": "movie soundtracks popular",
    "anime": "anime openings",
    "brazilian": "brazilian music hits",
    "mpb": "mpb musica popular brasileira",
    "sertanejo": "sertanejo 2024",
    "pagode": "pagode hits",
    "forró": "forró hits",
    "bossa nova": "bossa nova classics",
}

# Cache em memória para evitar I/O constante (atualizado quando o banco é atualizado)
_genre_cache_memory: Dict[str, dict] = {}
_cache_last_refresh: float = 0
CACHE_MEMORY_TTL = 3600  # 1 hora em memória antes de revalidar com banco

async def fetch_genre_tracks_from_api(genre_name: str, limit: int = 100) -> list:
    """Busca tracks de um gênero no YouTube Music (chamada à API real)."""
    genre_lower = genre_name.lower().strip()
    search_query = GENRE_QUERIES.get(genre_lower, f"{genre_name} music hits")
    
    print(f"🎵 [API] Buscando tracks do gênero '{genre_name}' com query: '{search_query}'")
    
    results = await run_in_threadpool(
        CatalogProvider.search_catalog, 
        search_query, 
        "song", 
        limit
    )
    
    if not results:
        return []
    
    tracks = []
    seen_tracks = set()
    
    for item in results:
        track_key = f"{item.get('artistName', '').lower()}_{item.get('trackName', '').lower()}"
        if track_key in seen_tracks:
            continue
        seen_tracks.add(track_key)
        
        duration_ms = item.get('durationMs', 0)
        
        # Filtra tracks muito longas ou curtas
        if duration_ms > 600000 or (duration_ms > 0 and duration_ms < 30000):
            continue
        
        tracks.append({
            "trackName": item.get('trackName', ''),
            "artistName": item.get('artistName', ''),
            "collectionName": item.get('collectionName', ''),
            "artworkUrl": item.get('artworkUrl', ''),
            "videoId": item.get('videoId'),
            "duration": item.get('duration', ''),
            "durationMs": duration_ms,
            "source": "YTMusic",
            "genre": genre_name,
        })
    
    return tracks

async def update_genre_cache_single(db: Session, genre_name: str) -> bool:
    """Atualiza o cache de um único gênero."""
    try:
        tracks = await fetch_genre_tracks_from_api(genre_name)
        
        if not tracks:
            print(f"⚠️ Nenhuma track encontrada para '{genre_name}'")
            return False
        
        genre_lower = genre_name.lower().strip()
        
        # Upsert no banco de dados
        existing = db.query(models.GenreCache).filter(
            models.GenreCache.genre_name == genre_lower
        ).first()
        
        if existing:
            existing.tracks = tracks
            existing.track_count = len(tracks)
            existing.source = "ytmusic"
        else:
            cache_entry = models.GenreCache(
                genre_name=genre_lower,
                tracks=tracks,
                track_count=len(tracks),
                source="ytmusic"
            )
            db.add(cache_entry)
        
        db.commit()
        
        # Atualiza cache em memória
        _genre_cache_memory[genre_lower] = {
            "tracks": tracks,
            "track_count": len(tracks),
            "source": "ytmusic"
        }
        
        print(f"✅ Cache atualizado para '{genre_name}': {len(tracks)} tracks")
        return True
        
    except Exception as e:
        print(f"❌ Erro ao atualizar cache de '{genre_name}': {e}")
        db.rollback()
        return False

async def update_all_genres_cache():
    """Atualiza o cache de todos os gêneros. Executado em background."""
    from app.database import SessionLocal
    
    print("🔄 Iniciando atualização completa do cache de gêneros...")
    start_time = time.time()
    
    db = SessionLocal()
    success_count = 0
    
    try:
        for genre in SUPPORTED_GENRES:
            try:
                if await update_genre_cache_single(db, genre):
                    success_count += 1
                # Delay entre requests para não sobrecarregar a API
                await asyncio.sleep(2)
            except Exception as e:
                print(f"❌ Erro no gênero '{genre}': {e}")
                continue
        
        elapsed = time.time() - start_time
        print(f"✅ Cache de gêneros atualizado! {success_count}/{len(SUPPORTED_GENRES)} gêneros em {elapsed:.1f}s")
        
        global _cache_last_refresh
        _cache_last_refresh = time.time()
        
    finally:
        db.close()

def get_cached_genre_tracks(db: Session, genre_name: str) -> Optional[dict]:
    """Busca tracks do cache (memória primeiro, depois banco)."""
    genre_lower = genre_name.lower().strip()
    
    # Tenta cache em memória primeiro
    if genre_lower in _genre_cache_memory:
        return _genre_cache_memory[genre_lower]
    
    # Se não está em memória, busca no banco
    cached = db.query(models.GenreCache).filter(
        models.GenreCache.genre_name == genre_lower
    ).first()
    
    if cached:
        # Carrega em memória para próximas requisições
        _genre_cache_memory[genre_lower] = {
            "tracks": cached.tracks,
            "track_count": cached.track_count,
            "source": cached.source,
            "updated_at": cached.updated_at.isoformat() if cached.updated_at else None
        }
        return _genre_cache_memory[genre_lower]
    
    return None

# Background task scheduler
_genre_cache_task: Optional[asyncio.Task] = None

async def genre_cache_scheduler():
    """Loop que atualiza o cache a cada 24 horas."""
    while True:
        try:
            await update_all_genres_cache()
        except Exception as e:
            print(f"❌ Erro no scheduler de cache: {e}")
        
        # Aguarda 24 horas
        await asyncio.sleep(24 * 60 * 60)

async def startup():
    """Inicializa o scheduler de cache de gêneros na inicialização."""
    global _genre_cache_task
    
    # Carrega cache existente do banco para memória
    from app.database import SessionLocal
    db = SessionLocal()
    try:
        cached_genres = db.query(models.GenreCache).all()
        for cached in cached_genres:
            _genre_cache_memory[cached.genre_name] = {
                "tracks": cached.tracks,
                "track_count": cached.track_count,
                "source": cached.source,
                "updated_at": cached.updated_at.isoformat() if cached.updated_at else None
            }
        print(f"📦 Cache carregado: {len(cached_genres)} gêneros em memória")
    finally:
        db.close()
    
    # Inicia o scheduler em background
    _genre_cache_task = asyncio.create_task(genre_cache_scheduler())
    print("🚀 Scheduler de cache de gêneros iniciado (atualização a cada 24h)")

async def shutdown():
    """Cancela o scheduler ao desligar."""
    global _genre_cache_task
    if _genre_cache_task:
        _genre_cache_task.cancel()
        print("⏹️ Scheduler de cache de gêneros encerrado")
