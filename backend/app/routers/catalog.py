from fastapi import APIRouter, HTTPException, Query, Depends
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.deps import get_current_user
from app.database import get_db
from app import models
from app.schemas import UpdateAlbumGenreRequest
from app.services.audio_manager import AudioManager
from app.services.local_library import find_local_match
from app.sources.registry import get_sources

router = APIRouter(tags=["catalog"])

@router.get("/search/catalog")
async def search_catalog(
    query: str, 
    limit: int = 20, 
    offset: int = 0, 
    type: str = Query("song", enum=["song", "album", "artist"]) 
):
    """
    Busca no catálogo de músicas.
    Prioridade: TIDAL (metadados ricos, capas HD, IDs de álbum) + YTMusic para cobertura extra.
    Remove duplicatas automaticamente.
    """
    print(f"🔎 Buscando no catálogo: '{query}' [Type: {type}, Limit: {limit}, Offset: {offset}]")
    
    fetch_limit = limit + offset + 20  # Pega mais para compensar duplicatas removidas
    
    results = await get_sources().catalog.search(query, type, fetch_limit)
    
    # 4. Paginação
    total_items = len(results)
    final_page = []
    
    if total_items > offset:
        end = offset + limit
        final_page = results[offset:end]
    
    print(f"   📤 Retornando {len(final_page)} itens (Offset: {offset}, Total: {total_items})")

    # 5. Verifica downloads locais
    for item in final_page:
        if item.get('type') == 'song':
            tidal_id = item.get('tidalId')
            album = item.get('collectionName')
            
            local_file = find_local_match(
                artist=item.get('artistName', ''), 
                track=item.get('trackName', ''),
                album=album,
                tidal_id=tidal_id
            )
            item['isDownloaded'] = local_file is not None
            item['filename'] = local_file
            
            if local_file:
                try:
                    tags = AudioManager.get_audio_tags(local_file)
                    item['genre'] = tags.get('genre')
                except:
                    pass
        else:
            item['isDownloaded'] = False
            item['filename'] = None

    return final_page


@router.get("/catalog/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Retorna detalhes completos do artista (Bio, Álbuns, Singles, Top Tracks).
    Suporta TIDAL (IDs numéricos) e YTMusic (IDs alfanuméricos/UC...).
    Enriquece com dados do Last.fm (artistas similares, bio, tags).
    """
    from app.services.lastfm_provider import LastfmProvider
    
    try:
        result = await get_sources().catalog.artist_details(artist_id)
        
        if not result:
            raise HTTPException(status_code=404, detail="Artista não encontrado")
        
        # Enriquece com Last.fm
        artist_name = result.get("artist", {}).get("artistName", "")
        if not artist_name:
            artist_name = result.get("artist", {}).get("name", "")
        
        if artist_name:
            print(f"🎵 Enriquecendo '{artist_name}' com Last.fm...")
            
            # 1. Artistas similares do Last.fm (melhor qualidade)
            lastfm_similar = await run_in_threadpool(
                LastfmProvider.get_similar_artists, artist_name, 10
            )
            
            if lastfm_similar:
                # Formata para o padrão esperado pelo app
                similar_artists = []
                for sim in lastfm_similar:
                    similar_artists.append({
                        "name": sim.get("name", ""),
                        "image": sim.get("image", ""),
                        "match": sim.get("match", 0),
                        "artistId": None,  # Last.fm não tem IDs do Tidal
                        "source": "LastFM"
                    })
                result["similarArtists"] = similar_artists
                print(f"   ✅ {len(similar_artists)} artistas similares via Last.fm")
            
            # 2. Informações extras do artista (bio, tags, listeners)
            lastfm_info = await run_in_threadpool(
                LastfmProvider.get_artist_info, artist_name
            )
            
            if lastfm_info:
                # Adiciona ou enriquece info do artista
                if not result.get("artist"):
                    result["artist"] = {}
                
                result["artist"]["bio"] = lastfm_info.get("bio", "")
                result["artist"]["tags"] = lastfm_info.get("tags", [])
                result["artist"]["listeners"] = lastfm_info.get("listeners", 0)
                result["artist"]["playcount"] = lastfm_info.get("playcount", 0)
                
                # Usa imagem do Last.fm se não tiver
                if not result["artist"].get("artworkUrl") and lastfm_info.get("image"):
                    result["artist"]["artworkUrl"] = lastfm_info["image"]
        
        return result

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Erro detalhes artista: {e}")
        raise HTTPException(status_code=500, detail="Erro ao buscar detalhes do artista")

@router.get("/catalog/album/{collection_id}")
async def get_album_details(collection_id: str):
    """
    Busca detalhes do álbum. Tenta Tidal primeiro, depois YTMusic.
    Agora enriquece com GÊNERO via iTunes.
    """
    try:
        result = await get_sources().catalog.album_details(collection_id)
    except Exception as e:
        print(f"❌ Erro rota album: {e}")
        raise HTTPException(status_code=502, detail="Falha ao consultar o catálogo")

    if not result:
        raise HTTPException(status_code=404, detail="Album not found")
    return result

@router.post("/catalog/album/update-genre", dependencies=[Depends(get_current_user)])
def update_album_tracks_genre(req: UpdateAlbumGenreRequest, db: Session = Depends(get_db)):
    """
    Atualiza o gênero de todas as tracks que pertencem a um álbum específico.
    Chamado quando o app abre um álbum e descobre o gênero.
    """
    if not req.genre or req.genre == "Desconhecido":
        return {"status": "skipped", "message": "Gênero inválido"}
    
    # Atualiza tracks pelo album_id
    updated = db.query(models.Track).filter(
        models.Track.album_id == req.album_id,
        (models.Track.genre == None) | (models.Track.genre == "") | (models.Track.genre == "Desconhecido")
    ).update({"genre": req.genre}, synchronize_session=False)
    
    db.commit()
    print(f"🎸 Atualizado gênero '{req.genre}' em {updated} tracks do álbum {req.album_id}")
    
    return {"status": "updated", "tracks_updated": updated, "genre": req.genre}
