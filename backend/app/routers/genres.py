from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from typing import Optional

from app.deps import get_current_user
from app.database import get_db
from app import models
from app.services.analytics_service import AnalyticsService
from app.services.genre_config import get_all_genres, get_genre_config, get_featured_genres
from app.services.genre_cache import (
    SUPPORTED_GENRES, _genre_cache_memory,
    fetch_genre_tracks_from_api, update_genre_cache_single,
    update_all_genres_cache, get_cached_genre_tracks,
)

router = APIRouter(tags=["genres"])

@router.get("/genres")
def list_all_genres():
    """
    Retorna a lista completa de gêneros disponíveis para explorar.
    Usado na seção 'Conheça mais' da busca.
    """
    return {"genres": get_all_genres()}

@router.get("/genres/stats")
def get_genre_statistics(db: Session = Depends(get_db)):
    """
    Retorna estatísticas dos gêneros das músicas baixadas.
    Útil para mostrar gêneros reais na biblioteca.
    """
    # Conta tracks por gênero
    genre_counts = db.query(
        models.Track.genre, 
        func.count(models.Track.id).label('count')
    ).filter(
        models.Track.genre.isnot(None), 
        models.Track.genre != '',
        models.Track.genre != 'Desconhecido'
    ).group_by(models.Track.genre).order_by(desc('count')).all()
    
    # Cores padrão para gêneros populares
    genre_colors = {
        'Pop': 0xFFE91E63,
        'Rock': 0xFFF44336,
        'Jazz': 0xFF9C27B0,
        'Hip-Hop': 0xFF673AB7,
        'R&B': 0xFF3F51B5,
        'R&B/Soul': 0xFF3F51B5,
        'Electronic': 0xFF00BCD4,
        'Dance': 0xFF00BCD4,
        'Classical': 0xFF795548,
        'Country': 0xFFFF9800,
        'Latin': 0xFFFFEB3B,
        'Reggae': 0xFF4CAF50,
        'Blues': 0xFF2196F3,
        'Metal': 0xFF424242,
        'Folk': 0xFF8BC34A,
        'Soul': 0xFF9C27B0,
        'Funk': 0xFFFF5722,
        'Punk': 0xFFE91E63,
        'Indie': 0xFF009688,
        'Alternative': 0xFF607D8B,
        'J-Pop': 0xFFFF4081,
        'K-Pop': 0xFFE040FB,
        'Anime': 0xFFFF6E40,
        'Soundtrack': 0xFF7C4DFF,
        'Video Game': 0xFF536DFE,
        'Bossa Nova': 0xFF26A69A,
        'MPB': 0xFF66BB6A,
        'Singer-Songwriter': 0xFFAB47BC,
    }
    
    genres = []
    for genre, count in genre_counts:
        config = get_genre_config(genre)
        color = genre_colors.get(genre, config.get("color", 0xFF9E9E9E) if config else 0xFF9E9E9E)
        genres.append({
            "name": genre,
            "count": count,
            "color": color,
            "search_query": config.get("search_query", genre) if config else genre,
        })
    
    return {"genres": genres, "total_tracks": sum(c for _, c in genre_counts)}

@router.get("/genres/featured")
def list_featured_genres(limit: int = 20):
    """
    Retorna os gêneros em destaque para a seção 'Conheça mais'.
    """
    return {"genres": get_featured_genres(limit)}

@router.get("/users/me/genres/favorites")
def get_user_favorite_genres(
    limit: int = 6, 
    days: int = 90, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    """
    Retorna os gêneros favoritos do usuário baseado no histórico de escuta.
    Os gêneros são ordenados pelo tempo total de escuta.
    """
    favorites = AnalyticsService.get_user_favorite_genres(db, current_user.id, limit, days)
    
    # Enriquece com cores e configs do genre_config se disponível
    enriched = []
    for fav in favorites:
        config = get_genre_config(fav["name"])
        enriched.append({
            "name": fav["name"],
            "total_minutes": fav["total_minutes"],
            "play_count": fav["play_count"],
            "color": config.get("color", 0xFF9E9E9E) if config else 0xFF9E9E9E,
            "search_query": config.get("search_query", fav["name"]) if config else fav["name"],
            "playlist_id": config.get("playlist_id") if config else None,
        })
    
    return {"favorites": enriched}

@router.get("/genres/{genre_name}/tracks")
async def get_genre_top_tracks(
    genre_name: str,
    limit: int = 100,
    force_refresh: bool = False,
    db: Session = Depends(get_db),
):
    """
    Retorna as top tracks de um gênero específico.
    Usa cache atualizado a cada 24h para resposta instantânea.
    Use force_refresh=true para forçar atualização do cache.
    """
    try:
        genre_lower = genre_name.lower().strip()
        
        # Tenta buscar do cache primeiro (se não forçar refresh)
        if not force_refresh:
            cached = get_cached_genre_tracks(db, genre_lower)
            if cached and cached.get("tracks"):
                tracks = cached["tracks"][:limit]  # Aplica limit
                print(f"📦 [CACHE] Retornando {len(tracks)} tracks de '{genre_name}' do cache")
                return {
                    "genre": genre_name,
                    "source": "cache",
                    "cached": True,
                    "updated_at": cached.get("updated_at"),
                    "tracks": tracks
                }
        
        # Se não tem cache ou force_refresh, busca da API e atualiza cache
        print(f"🔄 [LIVE] Buscando tracks de '{genre_name}' da API...")
        
        tracks = await fetch_genre_tracks_from_api(genre_name, limit)
        
        if tracks:
            # Atualiza cache em background
            await update_genre_cache_single(db, genre_name)
            
            print(f"✅ Encontradas {len(tracks)} tracks para o gênero '{genre_name}'")
            return {
                "genre": genre_name,
                "source": "ytmusic",
                "cached": False,
                "tracks": tracks[:limit]
            }
        
        print(f"⚠️ Nenhum resultado para o gênero '{genre_name}'")
        return {"genre": genre_name, "source": "ytmusic", "cached": False, "tracks": []}
                
    except Exception as e:
        print(f"❌ Erro ao buscar tracks do gênero {genre_name}: {e}")
        import traceback
        traceback.print_exc()
    
    return {"genre": genre_name, "source": "error", "cached": False, "tracks": []}

@router.post("/genres/refresh-cache", dependencies=[Depends(get_current_user)])
async def refresh_genres_cache(
    genre: Optional[str] = None,
    background_tasks: BackgroundTasks = BackgroundTasks(),
    db: Session = Depends(get_db),
):
    """
    Força atualização do cache de gêneros.
    Se 'genre' for especificado, atualiza apenas esse gênero.
    Caso contrário, atualiza todos os gêneros em background.
    """
    if genre:
        # Atualiza um gênero específico
        success = await update_genre_cache_single(db, genre)
        if success:
            return {"status": "success", "message": f"Cache de '{genre}' atualizado"}
        return {"status": "error", "message": f"Falha ao atualizar cache de '{genre}'"}
    
    # Atualiza todos em background
    background_tasks.add_task(update_all_genres_cache)
    return {
        "status": "started",
        "message": f"Atualização de {len(SUPPORTED_GENRES)} gêneros iniciada em background"
    }

@router.get("/genres/cache-status")
async def get_genres_cache_status(db: Session = Depends(get_db)):
    """
    Retorna o status do cache de gêneros.
    """
    cached_genres = db.query(models.GenreCache).all()
    
    status = []
    for cached in cached_genres:
        status.append({
            "genre": cached.genre_name,
            "track_count": cached.track_count,
            "updated_at": cached.updated_at.isoformat() if cached.updated_at else None,
        })
    
    return {
        "total_cached": len(cached_genres),
        "total_supported": len(SUPPORTED_GENRES),
        "memory_cache_size": len(_genre_cache_memory),
        "genres": status
    }
