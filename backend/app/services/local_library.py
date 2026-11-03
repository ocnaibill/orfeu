import os
import httpx
from typing import Optional
from sqlalchemy.orm import Session
from fastapi.concurrency import run_in_threadpool
from unidecode import unidecode
from thefuzz import fuzz

from app import models
from app.core import config
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.metadata_provider import MetadataProvider


def normalize_text(text: str) -> str:
    if not text: return ""
    return unidecode(text.lower().replace("$", "s").replace("&", "and")).strip()

def get_db_session():
    """Helper para obter sessão do banco fora de contexto de request."""
    from app.database import SessionLocal
    return SessionLocal()

def find_local_match_by_tidal_id(tidal_id: int) -> Optional[str]:
    """
    Busca arquivo local pelo tidal_id na tabela downloaded_tracks.
    Esta é a forma preferida de encontrar arquivos - garante unicidade.
    """
    if not tidal_id:
        return None
    
    db = get_db_session()
    try:
        downloaded = db.query(models.DownloadedTrack).filter(
            models.DownloadedTrack.tidal_id == tidal_id
        ).first()
        
        if downloaded and downloaded.local_path:
            full_path = os.path.join(config.MUSIC_DIR, downloaded.local_path)
            if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
                return full_path
    except Exception as e:
        print(f"⚠️ Erro ao buscar por tidal_id: {e}")
    finally:
        db.close()
    
    return None

def find_local_match(artist: str, track: str, album: str = None, tidal_id: int = None) -> Optional[str]:
    """
    Busca arquivo local. Prioridade:
    1. tidal_id (mais preciso - garante unicidade)
    2. artist + track + album (match EXATO no banco)
    3. NÃO faz mais fallback fuzzy para evitar falsos positivos
    """
    print(f"🔍 find_local_match: artist='{artist}', track='{track}', album='{album}', tidal_id={tidal_id}")
    
    # 1. Primeiro tenta pelo tidal_id (mais confiável)
    if tidal_id:
        result = find_local_match_by_tidal_id(tidal_id)
        if result:
            print(f"   ✅ Encontrado por tidal_id: {result}")
            return result
        else:
            print(f"   ❌ Não encontrado por tidal_id")
    
    # 2. Busca no banco downloaded_tracks - precisa ter TODOS os campos batendo
    db = get_db_session()
    try:
        # Normaliza para comparação
        artist_norm = normalize_text(artist).lower() if artist else ""
        track_norm = normalize_text(track).lower() if track else ""
        album_norm = normalize_text(album).lower() if album else ""
        
        # Busca todos os registros do artista
        candidates = db.query(models.DownloadedTrack).filter(
            models.DownloadedTrack.artist.ilike(f"%{artist}%")
        ).all()
        
        for candidate in candidates:
            candidate_title = normalize_text(candidate.title or "").lower()
            candidate_album = normalize_text(candidate.album or "").lower()
            
            # Verifica se o título bate (usando fuzzy com threshold alto)
            title_score = fuzz.ratio(track_norm, candidate_title)
            
            # Precisa de score >= 85 para o título
            if title_score >= 85:
                # Se temos álbum, verifica também
                if album:
                    album_score = fuzz.ratio(album_norm, candidate_album)
                    if album_score < 70:
                        print(f"   ⚠️ Álbum não bate: '{album}' vs '{candidate.album}' (score: {album_score})")
                        continue
                
                full_path = os.path.join(config.MUSIC_DIR, candidate.local_path)
                if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
                    print(f"   ✅ Encontrado no banco: {candidate.title} -> {full_path}")
                    return full_path
        
        print(f"   ❌ Não encontrado no banco (nenhum match de título >= 85%)")
        
    except Exception as e:
        print(f"⚠️ Erro ao buscar downloaded_tracks: {e}")
    finally:
        db.close()
    
    # NÃO faz mais fallback para busca fuzzy no disco
    # Isso evita falsos positivos como músicas diferentes do mesmo álbum
    print(f"   ❌ Nenhum match local encontrado para '{artist} - {track}'")
    return None

def register_download(tidal_id: int = None, ytmusic_id: str = None, 
                      title: str = None, artist: str = None, album: str = None,
                      local_path: str = None, source: str = "Tidal"):
    """
    Registra um download na tabela downloaded_tracks para rastreamento preciso.
    """
    db = get_db_session()
    try:
        # Verifica se já existe
        existing = None
        if tidal_id:
            existing = db.query(models.DownloadedTrack).filter(
                models.DownloadedTrack.tidal_id == tidal_id
            ).first()
        elif ytmusic_id:
            existing = db.query(models.DownloadedTrack).filter(
                models.DownloadedTrack.ytmusic_id == ytmusic_id
            ).first()
        
        if existing:
            # Atualiza o path se mudou
            existing.local_path = local_path
            db.commit()
            return existing
        
        # Cria novo registro
        new_download = models.DownloadedTrack(
            tidal_id=tidal_id,
            ytmusic_id=ytmusic_id,
            title=title,
            artist=artist,
            album=album,
            local_path=local_path,
            source=source
        )
        db.add(new_download)
        db.commit()
        db.refresh(new_download)
        return new_download
    except Exception as e:
        print(f"❌ Erro ao registrar download: {e}")
        db.rollback()
    finally:
        db.close()
    return None

def fetch_and_assign_genre(artist: str, album: str = None, title: str = None) -> str:
    """
    Busca o gênero de uma track usando a API do iTunes.
    Retorna o gênero encontrado ou None.
    """
    try:
        genre = MetadataProvider.get_genre(artist or "", album or "", title or "")
        if genre and genre != "Desconhecido":
            print(f"🎵 Gênero encontrado: {artist} - {title} → {genre}")
            return genre
    except Exception as e:
        print(f"⚠️ Erro ao buscar gênero: {e}")
    return None

async def download_file_background(url: str, dest_path: str, metadata: dict, cover_url: str = None):
    try:
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        temp_path = dest_path + ".tmp"
        async with httpx.AsyncClient() as client:
            async with client.stream('GET', url) as response:
                response.raise_for_status()
                with open(temp_path, 'wb') as f:
                    async for chunk in response.aiter_bytes():
                        f.write(chunk)
        
        cover_bytes = None
        target_cover = cover_url or await LyricsProvider.get_online_cover(dest_path)
        if target_cover:
            try:
                async with httpx.AsyncClient() as client:
                    resp = await client.get(target_cover, timeout=10.0)
                    if resp.status_code == 200: cover_bytes = resp.content
            except: pass
        
        if os.path.exists(dest_path):
             os.remove(dest_path)

        os.rename(temp_path, dest_path)
        if metadata: await run_in_threadpool(AudioManager.embed_metadata, dest_path, metadata, cover_bytes)
        print(f"✅ Download HTTP concluído e tagueado: {dest_path}")
    except Exception as e:
        print(f"❌ Erro download background: {e}")
        if os.path.exists(temp_path): os.remove(temp_path)

def sync_files_to_db(db: Session = None):
    """Indexa os arquivos do disco no banco.

    Roda como background task (def síncrona = threadpool, não trava o event loop)
    e abre a PRÓPRIA sessão: a sessão da request já está fechada quando a task executa.
    """
    own_session = db is None
    if own_session:
        db = get_db_session()
    try:
        print("🔄 Sincronizando arquivos do disco para o DB...")
        base_path = config.MUSIC_DIR
        for root, dirs, files in os.walk(base_path):
            for file in files:
                if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, base_path)
                
                    # Verifica se já existe no banco
                    exists = db.query(models.Track).filter(models.Track.filename == rel_path).first()
                    if not exists:
                        try:
                            # Lê metadados
                            from app.services.audio_manager import AudioManager
                            tags = AudioManager.get_audio_tags(full_path)
                            meta = AudioManager.get_audio_metadata(full_path)
                        
                            # Se não tem gênero nos metadados, busca online
                            genre = tags.get('genre')
                            if not genre or genre == "" or genre == "Desconhecido":
                                artist = tags.get('artist') or "Desconhecido"
                                album = tags.get('album')
                                title = tags.get('title') or file
                                genre = fetch_and_assign_genre(artist, album, title)
                        
                            track = models.Track(
                                filename=rel_path,
                                title=tags.get('title') or file,
                                artist=tags.get('artist') or "Desconhecido",
                                album=tags.get('album'),
                                genre=genre,
                                duration=meta.get('duration', 0),
                                format=meta.get('format'),
                                bitrate=meta.get('bitrate')
                            )
                            db.add(track)
                        except Exception as e:
                            print(f"Erro ao indexar {file}: {e}")
        db.commit()
        print("✅ Sincronização concluída.")
    except Exception as e:
        db.rollback()
        print(f"❌ Erro na sincronização da biblioteca: {e}")
    finally:
        if own_session:
            db.close()

async def process_library_auto_tagging():
    from app.sources.registry import get_sources  # import tardio: app.sources depende deste módulo
    base_path = config.MUSIC_DIR
    count = 0
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.lower().endswith(('.flac', '.mp3', '.m4a')):
                full_path = os.path.join(root, file)
                try:
                    current_tags = AudioManager.get_audio_tags(full_path)
                    if not current_tags.get('artist') or not current_tags.get('title') or current_tags.get('artist') == 'Desconhecido':
                        clean_name = normalize_text(os.path.splitext(file)[0].replace("_", " "))
                        results = []
                        for source in get_sources().catalog.sources:
                            results = await source.search(clean_name, "song", 1)
                            if results: break
                        
                        if results:
                            best_match = results[0]
                            match_str = normalize_text(f"{best_match['artistName']} {best_match['trackName']}")
                            similarity = fuzz.token_set_ratio(clean_name, match_str)
                            if similarity > 80:
                                cover_bytes = None
                                if best_match.get('artworkUrl'):
                                    try:
                                        async with httpx.AsyncClient() as client:
                                            resp = await client.get(best_match['artworkUrl'])
                                            if resp.status_code == 200: cover_bytes = resp.content
                                    except: pass
                                meta = {"title": best_match['trackName'], "artist": best_match['artistName'], "album": best_match['collectionName']}
                                await run_in_threadpool(AudioManager.embed_metadata, full_path, meta, cover_bytes)
                                count += 1
                except: pass
    print(f"✨ Auto-Tagging concluído. {count} arquivos atualizados.")
