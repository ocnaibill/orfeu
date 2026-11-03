import re

from fastapi import APIRouter, HTTPException, Query, Depends
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.deps import get_current_user
from app.database import get_db
from app import models
from app.schemas import UpdateAlbumGenreRequest
from app.services.audio_manager import AudioManager
from app.services.catalog_provider import CatalogProvider
from app.services.tidal_provider import TidalProvider
from app.services.metadata_provider import MetadataProvider
from app.services.local_library import normalize_text, find_local_match

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
    
    yt_results = []
    tidal_results = []
    
    # 1. TIDAL PRIMEIRO (metadados ricos, capas HD, IDs de álbum/artista)
    try:
        tidal_results = await run_in_threadpool(TidalProvider.search_catalog, query, fetch_limit, type)
        print(f"   ✅ Tidal retornou {len(tidal_results)} resultados.")
    except Exception as e:
        print(f"   ❌ Erro no Tidal: {e}")
    
    # 2. YouTube Music em paralelo (para cobertura adicional de músicas não no Tidal)
    try:
        yt_results = await run_in_threadpool(CatalogProvider.search_catalog, query, type, fetch_limit)
        print(f"   ✅ YTMusic retornou {len(yt_results)} resultados.")
    except Exception as e:
        print(f"   ❌ Erro no YTMusic: {e}")
    
    # 3. Mescla resultados com deduplicação inteligente (Tidal é prioritário)
    results = merge_and_deduplicate_results(tidal_results, yt_results, type)
    print(f"   🔀 Após merge/dedup: {len(results)} resultados únicos")
    
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

def merge_and_deduplicate_results(primary_results: list, secondary_results: list, result_type: str) -> list:
    """
    Mescla resultados removendo duplicatas.
    primary_results = Tidal (metadados ricos, capas HD, IDs)
    secondary_results = YTMusic (cobertura extra, videoId para download)
    """
    seen = {}  # Chave normalizada -> item
    final_results = []
    
    def make_key(item: dict) -> str:
        """Cria chave única normalizada para detectar duplicatas."""
        if result_type == "artist":
            name = normalize_text(item.get('artistName', ''))
            name = name.replace(' official', '').replace(' music', '').replace(' vevo', '')
            return f"artist:{name}"
        
        elif result_type == "album":
            artist = normalize_text(item.get('artistName', ''))
            album = normalize_text(item.get('collectionName', ''))
            album = re.sub(r'\s*\(?(deluxe|remaster|edition|version|expanded|anniversary)\)?.*$', '', album, flags=re.IGNORECASE)
            return f"album:{artist}:{album}"
        
        else:  # song
            artist = normalize_text(item.get('artistName', ''))
            track = normalize_text(item.get('trackName', ''))
            track = re.sub(r'\s*\(?(remix|remaster|live|acoustic|radio edit|explicit|clean)\)?.*$', '', track, flags=re.IGNORECASE)
            return f"song:{artist}:{track}"
    
    def enrich_tidal_with_ytmusic(tidal_item: dict, yt_item: dict) -> dict:
        """Enriquece item do Tidal com videoId do YTMusic (para download via yt-dlp)."""
        if yt_item.get('videoId'):
            tidal_item['videoId'] = yt_item['videoId']
        return tidal_item
    
    # Indexa YTMusic para lookup rápido (para enriquecer Tidal com videoId)
    yt_index = {}
    for item in secondary_results:
        key = make_key(item)
        if key not in yt_index:
            yt_index[key] = item
    
    # Processa TIDAL primeiro (prioridade - metadados melhores)
    for item in primary_results:
        key = make_key(item)
        if key not in seen:
            # Enriquece com videoId do YTMusic para download
            if key in yt_index:
                item = enrich_tidal_with_ytmusic(item, yt_index[key])
            seen[key] = item
            final_results.append(item)
    
    # Adiciona itens do YTMusic que NÃO existem no Tidal (cobertura extra)
    for item in secondary_results:
        key = make_key(item)
        if key not in seen:
            seen[key] = item
            final_results.append(item)
    
    return final_results

@router.get("/catalog/artist/{artist_id}")
async def get_artist_details(artist_id: str):
    """
    Retorna detalhes completos do artista (Bio, Álbuns, Singles, Top Tracks).
    Suporta TIDAL (IDs numéricos) e YTMusic (IDs alfanuméricos/UC...).
    Enriquece com dados do Last.fm (artistas similares, bio, tags).
    """
    from app.services.lastfm_provider import LastfmProvider
    
    try:
        # Lógica de roteamento baseada no formato do ID
        if artist_id.isdigit():
             # TIDAL
             print(f"🎤 Buscando artista no TIDAL: {artist_id}")
             result = await run_in_threadpool(TidalProvider.get_artist_details, artist_id)
        else:
             # YTMUSIC (IDs geralmente começam com 'UC' ou 'U' ou hash longo)
             print(f"🎤 Buscando artista no YTMusic: {artist_id}")
             result = await run_in_threadpool(CatalogProvider.get_artist_details, artist_id)
        
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
        # Identifica provider pelo formato do ID
        if collection_id.isdigit():
             # TIDAL
             return await run_in_threadpool(TidalProvider.get_album_details, collection_id)
        else:
             # YTMUSIC
             details = await run_in_threadpool(CatalogProvider.get_album_details, collection_id)
             # Enriquece YTMusic com gênero
             if details and not details.get('genre'):
                  genre = await run_in_threadpool(MetadataProvider.get_genre, details['artistName'], details['collectionName'])
                  details['genre'] = genre
             return details

    except Exception as e:
        print(f"❌ Erro rota album: {e}")
        raise HTTPException(status_code=404, detail="Album not found")

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
