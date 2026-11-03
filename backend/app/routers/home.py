from urllib.parse import quote

from fastapi import APIRouter, Depends
from fastapi.concurrency import run_in_threadpool
from sqlalchemy import func, desc
from sqlalchemy.orm import Session
from thefuzz import fuzz

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.services.analytics_service import AnalyticsService
from app.services.local_library import normalize_text
from app.services.recommendation_service import MusicRecommender
from app.services.tidal_provider import TidalProvider

router = APIRouter(tags=["home"])


# --- ROTAS DA HOME (FEED & ANALYTICS)  ---
@router.get("/home/continue-listening")
def get_continue_listening(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return AnalyticsService.get_recently_played(db, current_user.id, limit)

@router.get("/home/trajectory")
def get_trajectory(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    retro_playlists = db.query(models.Playlist)\
        .filter(models.Playlist.user_id == current_user.id, models.Playlist.name.like("Retrospectiva%"))\
        .order_by(models.Playlist.created_at.desc())\
        .all()
    return [{
        "id": p.id,
        "title": p.name,
        "artist": "Orfeu Rewind",
        "imageUrl": f"https://ui-avatars.com/api/?name={quote(p.name)}&background=D4AF37&color=000&size=300",
        "type": "playlist"
    } for p in retro_playlists]

@router.get("/home/discover")
async def get_discover_weekly(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Descobertas da Semana - Artistas que você ainda não ouviu mas pode gostar.
    Usa Last.fm para encontrar artistas genuinamente similares aos favoritos do usuário.
    """
    from app.services.lastfm_provider import LastfmProvider
    
    try:
        discoveries = []
        seen_artists = set()
        
        # 1. Busca os artistas mais ouvidos do usuário
        top_artists_query = db.query(
            models.Track.artist, 
            func.count(models.ListenHistory.id).label('count')
        ).join(models.ListenHistory).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.artist.isnot(None),
            models.Track.artist != "",
            models.Track.artist != "Desconhecido"
        ).group_by(models.Track.artist).order_by(desc('count')).limit(10).all()
        
        # Set de artistas que o usuário já conhece (para não recomendar)
        known_artists = {a[0].lower() for a in top_artists_query if a[0]}
        
        # Também adiciona artistas salvos na biblioteca
        saved_artists_db = db.query(models.SavedArtist.name).filter(
            models.SavedArtist.user_id == current_user.id
        ).all()
        for sa in saved_artists_db:
            if sa[0]:
                known_artists.add(sa[0].lower())
        
        print(f"🔍 Discover para {current_user.username}: {len(known_artists)} artistas conhecidos")
        
        # 2. CASO: Usuário tem histórico - usa Last.fm para artistas similares
        if top_artists_query:
            top_artist_names = [a[0] for a in top_artists_query[:5]]  # Top 5
            
            for base_artist in top_artist_names:
                if len(discoveries) >= limit:
                    break
                
                # Busca artistas similares via Last.fm
                similar_artists = await run_in_threadpool(
                    LastfmProvider.get_similar_artists, 
                    base_artist, 
                    8  # 8 similares por artista base
                )
                
                if not similar_artists:
                    continue
                
                # Ordena por match score (maior similaridade primeiro)
                similar_artists.sort(key=lambda x: x.get('match', 0), reverse=True)
                
                for similar in similar_artists:
                    artist_name = similar.get('name', '')
                    artist_lower = artist_name.lower()
                    
                    # Pula se já conhece ou já foi adicionado
                    if artist_lower in known_artists or artist_lower in seen_artists:
                        continue
                    
                    # Pula se match muito baixo
                    if similar.get('match', 0) < 0.1:
                        continue
                    
                    seen_artists.add(artist_lower)
                    
                    # Busca o álbum mais recente desse artista no Tidal
                    try:
                        albums = await run_in_threadpool(
                            TidalProvider.search_catalog,
                            artist_name,
                            3,
                            "album"
                        )
                        
                        # Filtra álbuns do artista correto
                        artist_albums = [
                            a for a in albums 
                            if a.get('artistName', '').lower() == artist_lower
                        ]
                        
                        if artist_albums:
                            album = artist_albums[0]
                            discoveries.append({
                                "title": album['collectionName'],
                                "artist": album['artistName'],
                                "imageUrl": album.get('artworkUrl', similar.get('image', '')),
                                "type": "album",
                                "id": album['collectionId'],
                                "reason": f"Porque você curte {base_artist}",
                                "matchScore": similar.get('match', 0)
                            })
                            
                            if len(discoveries) >= limit:
                                break
                    except Exception as e:
                        print(f"⚠️ Erro buscando álbum de {artist_name}: {e}")
                        continue
        
        # 3. FALLBACK: Usuário novo sem histórico - usa gêneros populares
        if len(discoveries) < limit:
            fallback_tags = ["indie", "alternative", "pop", "electronic", "rock"]
            
            for tag in fallback_tags:
                if len(discoveries) >= limit:
                    break
                
                try:
                    tag_artists = await run_in_threadpool(
                        LastfmProvider.get_top_artists_by_tag,
                        tag,
                        5
                    )
                    
                    for artist in tag_artists:
                        artist_name = artist.get('name', '')
                        artist_lower = artist_name.lower()
                        
                        if artist_lower in known_artists or artist_lower in seen_artists:
                            continue
                        
                        seen_artists.add(artist_lower)
                        
                        # Busca álbum via Tidal
                        albums = await run_in_threadpool(
                            TidalProvider.search_catalog,
                            artist_name,
                            1,
                            "album"
                        )
                        
                        if albums:
                            album = albums[0]
                            discoveries.append({
                                "title": album['collectionName'],
                                "artist": album['artistName'],
                                "imageUrl": album.get('artworkUrl', ''),
                                "type": "album",
                                "id": album['collectionId'],
                                "reason": f"Popular em {tag.capitalize()}"
                            })
                            
                            if len(discoveries) >= limit:
                                break
                except:
                    continue
        
        # 4. Ordena por match score (se disponível) e embaralha um pouco
        import random
        if len(discoveries) > 3:
            # Mantém os top 3 por match score, embaralha o resto
            discoveries.sort(key=lambda x: x.get('matchScore', 0), reverse=True)
            top_picks = discoveries[:3]
            rest = discoveries[3:]
            random.shuffle(rest)
            discoveries = top_picks + rest
        
        print(f"✅ Discover: {len(discoveries)} descobertas para {current_user.username}")
        return discoveries[:limit]
        
    except Exception as e:
        print(f"❌ Erro em discover: {e}")
        import traceback
        traceback.print_exc()
        return []

@router.get("/home/recommendations")
async def get_recommendations(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Recomendações personalizadas baseadas no histórico real do usuário.
    
    Estratégia em 3 níveis:
    1. OURO: Outros álbuns dos artistas mais ouvidos (descoberta dentro do mesmo artista)
    2. PRATA: Álbuns de artistas do mesmo gênero que o usuário ouve
    3. BRONZE: Baseado em álbuns/artistas salvos na biblioteca
    """
    try:
        recommendations = []
        seen_ids = set()
        seen_artists = set()
        
        # =========================================================
        # 1. COLETA DE DADOS DO USUÁRIO
        # =========================================================
        
        # 1.1 Artistas mais ouvidos (com contagem)
        top_artists_data = db.query(
            models.Track.artist, 
            func.count(models.ListenHistory.id).label('play_count')
        ).join(models.ListenHistory).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.artist.isnot(None),
            models.Track.artist != "",
            models.Track.artist != "Desconhecido"
        ).group_by(models.Track.artist).order_by(desc('play_count')).limit(10).all()
        
        top_artists = [a[0] for a in top_artists_data if a[0]]
        top_artists_lower = {a.lower() for a in top_artists}
        
        # 1.2 Álbuns já ouvidos (para não recomendar repetidos)
        listened_albums = db.query(models.Track.album).join(models.ListenHistory).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.album.isnot(None)
        ).distinct().all()
        listened_albums_set = {normalize_text(a[0]) for a in listened_albums if a[0]}
        
        # 1.3 Gêneros mais ouvidos
        top_genres = db.query(models.Track.genre, func.count(models.ListenHistory.id).label('count')).join(
            models.ListenHistory
        ).filter(
            models.ListenHistory.user_id == current_user.id,
            models.Track.genre.isnot(None),
            models.Track.genre != "",
            models.Track.genre != "Desconhecido"
        ).group_by(models.Track.genre).order_by(desc('count')).limit(3).all()
        
        user_genres = [g[0] for g in top_genres] if top_genres else []
        
        # 1.4 Artistas salvos na biblioteca
        saved_artists = db.query(models.SavedArtist).filter(
            models.SavedArtist.user_id == current_user.id
        ).limit(5).all()
        saved_artist_names = [a.name for a in saved_artists]
        
        print(f"🎯 Recomendações para {current_user.username}:")
        print(f"   Top Artistas: {top_artists[:5]}")
        print(f"   Gêneros: {user_genres}")
        print(f"   Álbuns ouvidos: {len(listened_albums_set)}")
        
        # =========================================================
        # 2. FASE OURO: Outros álbuns dos artistas favoritos
        # =========================================================
        if top_artists and len(recommendations) < limit:
            print(f"🥇 Fase OURO: Buscando discografia dos top artistas...")
            
            for artist in top_artists[:5]:  # Top 5 artistas
                if len(recommendations) >= limit:
                    break
                    
                try:
                    # Busca o artista no Tidal para pegar o ID
                    artist_search = await run_in_threadpool(
                        TidalProvider.search_catalog, artist, 1, "artist"
                    )
                    
                    if not artist_search:
                        continue
                    
                    # Verifica se é realmente o artista certo
                    found_artist = artist_search[0]
                    if fuzz.token_sort_ratio(
                        normalize_text(artist), 
                        normalize_text(found_artist.get('artistName', ''))
                    ) < 85:
                        continue
                    
                    artist_id = found_artist.get('artistId')
                    if not artist_id:
                        continue
                    
                    # Busca detalhes do artista (inclui álbuns)
                    artist_details = await run_in_threadpool(
                        TidalProvider.get_artist_details, artist_id
                    )
                    
                    if not artist_details:
                        continue
                    
                    # Pega álbuns e singles
                    all_releases = artist_details.get('albums', []) + artist_details.get('singles', [])
                    
                    # Ordena por data de lançamento (mais recente primeiro)
                    all_releases.sort(key=lambda x: x.get('releaseDate', '0000'), reverse=True)
                    
                    for release in all_releases[:3]:  # Top 3 releases por artista
                        album_name = release.get('collectionName', '')
                        album_id = release.get('collectionId')
                        
                        if not album_id or album_id in seen_ids:
                            continue
                        
                        # Não recomenda álbuns já ouvidos
                        if normalize_text(album_name) in listened_albums_set:
                            continue
                        
                        seen_ids.add(album_id)
                        recommendations.append({
                            "title": album_name,
                            "artist": release.get('artistName', artist),
                            "imageUrl": release.get('artworkUrl', ''),
                            "type": "album",
                            "id": album_id,
                            "year": release.get('year', ''),
                            "reason": f"Mais de {artist}"
                        })
                        
                        if len(recommendations) >= limit:
                            break
                            
                except Exception as e:
                    print(f"   ⚠️ Erro buscando álbuns de {artist}: {e}")
                    continue
        
        # =========================================================
        # 3. FASE PRATA: Artistas do mesmo gênero
        # =========================================================
        if user_genres and len(recommendations) < limit:
            print(f"🥈 Fase PRATA: Buscando artistas dos gêneros {user_genres}...")
            
            for genre in user_genres:
                if len(recommendations) >= limit:
                    break
                
                try:
                    # Busca artistas específicos do gênero (não genérico)
                    # Usa o gênero + "artist" para buscar artistas reais
                    genre_artists = await run_in_threadpool(
                        TidalProvider.search_catalog, f"{genre}", 10, "artist"
                    )
                    
                    if not genre_artists:
                        continue
                    
                    for genre_artist in genre_artists:
                        artist_name = genre_artist.get('artistName', '')
                        
                        # Pula artistas já ouvidos
                        if artist_name.lower() in top_artists_lower:
                            continue
                        
                        # Pula artistas já recomendados
                        if artist_name.lower() in seen_artists:
                            continue
                        
                        seen_artists.add(artist_name.lower())
                        
                        # Busca o álbum mais popular desse artista
                        try:
                            artist_id = genre_artist.get('artistId')
                            if artist_id:
                                artist_details = await run_in_threadpool(
                                    TidalProvider.get_artist_details, artist_id
                                )
                                
                                if artist_details and artist_details.get('albums'):
                                    top_album = artist_details['albums'][0]
                                    album_id = top_album.get('collectionId')
                                    
                                    if album_id and album_id not in seen_ids:
                                        seen_ids.add(album_id)
                                        recommendations.append({
                                            "title": top_album.get('collectionName', ''),
                                            "artist": artist_name,
                                            "imageUrl": top_album.get('artworkUrl', ''),
                                            "type": "album",
                                            "id": album_id,
                                            "year": top_album.get('year', ''),
                                            "reason": f"Porque você curte {genre}"
                                        })
                                        
                                        if len(recommendations) >= limit:
                                            break
                        except:
                            continue
                            
                except Exception as e:
                    print(f"   ⚠️ Erro buscando gênero {genre}: {e}")
                    continue
        
        # =========================================================
        # 4. FASE BRONZE: Baseado em artistas salvos
        # =========================================================
        if saved_artist_names and len(recommendations) < limit:
            print(f"🥉 Fase BRONZE: Recomendações de artistas salvos...")
            
            for saved_artist in saved_artist_names:
                if saved_artist.lower() in top_artists_lower:
                    continue  # Já coberto na fase ouro
                    
                if len(recommendations) >= limit:
                    break
                
                try:
                    artist_search = await run_in_threadpool(
                        TidalProvider.search_catalog, saved_artist, 1, "artist"
                    )
                    
                    if artist_search:
                        artist_id = artist_search[0].get('artistId')
                        if artist_id:
                            artist_details = await run_in_threadpool(
                                TidalProvider.get_artist_details, artist_id
                            )
                            
                            if artist_details and artist_details.get('albums'):
                                for album in artist_details['albums'][:2]:
                                    album_id = album.get('collectionId')
                                    album_name = album.get('collectionName', '')
                                    
                                    if album_id in seen_ids:
                                        continue
                                    if normalize_text(album_name) in listened_albums_set:
                                        continue
                                    
                                    seen_ids.add(album_id)
                                    recommendations.append({
                                        "title": album_name,
                                        "artist": saved_artist,
                                        "imageUrl": album.get('artworkUrl', ''),
                                        "type": "album",
                                        "id": album_id,
                                        "year": album.get('year', ''),
                                        "reason": f"Da sua biblioteca"
                                    })
                                    
                                    if len(recommendations) >= limit:
                                        break
                except:
                    continue
        
        # =========================================================
        # 5. Embaralha levemente para variedade (mantendo prioridade)
        # =========================================================
        import random
        if len(recommendations) > 5:
            # Divide em grupos de prioridade e embaralha dentro de cada grupo
            high_priority = recommendations[:len(recommendations)//2]
            low_priority = recommendations[len(recommendations)//2:]
            random.shuffle(high_priority)
            random.shuffle(low_priority)
            recommendations = high_priority + low_priority
        
        print(f"✅ Retornando {len(recommendations)} recomendações personalizadas")
        return recommendations[:limit]
        
    except Exception as e:
        print(f"❌ Erro em recommendations: {e}")
        import traceback
        traceback.print_exc()
        return []

# --- NOVIDADES PERSONALIZADAS ---
@router.get("/home/new-releases")
async def get_new_releases(limit: int = 10, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    """
    Seção 'Novidades dos seus favoritos':
    - Se o usuário tem histórico: busca novidades dos artistas mais ouvidos
    - Se não tem: busca lançamentos populares recentes
    """
    try:
        # 1. Identifica Top Artistas do usuário
        top_artists_query = db.query(models.Track.artist, func.count(models.ListenHistory.id).label('count'))\
            .join(models.ListenHistory)\
            .filter(models.ListenHistory.user_id == current_user.id)\
            .group_by(models.Track.artist)\
            .order_by(desc('count'))\
            .limit(10)\
            .all()
        
        top_artists_names = [a[0] for a in top_artists_query if a[0] and a[0] != "Desconhecido"]
        
        # 2. Se tem artistas favoritos, busca novidades deles
        if top_artists_names:
            recommender = MusicRecommender()
            news = await recommender.get_new_releases(top_artists_names, limit=limit)
            if news:
                return news
        
        # 3. Fallback: Busca lançamentos populares no Tidal
        print("📢 Usuário sem histórico suficiente, buscando novidades gerais...")
        try:
            # Busca álbuns populares/novos
            results = await run_in_threadpool(TidalProvider.search_catalog, "new releases 2024", limit, "album")
            
            if results:
                return [{
                    "title": item.get('collectionName', 'Álbum'),
                    "artist": item.get('artistName', 'Artista'),
                    "imageUrl": item.get('artworkUrl', ''),
                    "type": "album",
                    "id": item.get('collectionId'),
                    "vibrantColorHex": "#D4AF37",
                    "tags": ["Popular"]
                } for item in results[:limit]]
        except Exception as fallback_e:
            print(f"⚠️ Fallback também falhou: {fallback_e}")
        
        return []

    except Exception as e:
        print(f"❌ Erro crítico em new-releases: {e}")
        return []
