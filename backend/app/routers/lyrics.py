from fastapi import APIRouter, HTTPException, Depends
from typing import Optional

from app.deps import get_current_user
from app.services.audio_manager import AudioManager
from app.services.lyrics_provider import LyricsProvider
from app.services.synced_lyrics_provider import (
    synced_lyrics_provider, 
    SyncedLyrics,
    get_available_providers,
    get_musixmatch_token_status,
    reset_musixmatch_token,
    test_musixmatch_connection,
)

router = APIRouter(tags=["lyrics"])

@router.get("/lyrics")
async def get_lyrics(filename: str):
    full_path = AudioManager.find_local_file(filename)
    lyrics = await LyricsProvider.get_lyrics(full_path)
    if not lyrics: raise HTTPException(404, "Letra não encontrada")
    return lyrics

@router.get("/lyrics/synced")
async def get_synced_lyrics(
    track: str,
    artist: str,
    album: Optional[str] = None,
    duration: Optional[int] = None,
    isrc: Optional[str] = None,
    apple_music_id: Optional[str] = None,
):
    """
    Busca letras sincronizadas para uma música.
    
    Retorna letras com timing por sílaba (Apple Music) ou por linha (LRCLIB).
    """
    lyrics = await synced_lyrics_provider.get_synced_lyrics(
        track_name=track,
        artist_name=artist,
        album_name=album,
        duration=duration,
        isrc=isrc,
        apple_music_id=apple_music_id,
    )
    
    if not lyrics:
        raise HTTPException(404, "Letras não encontradas")
    
    # Converte para dict serializável
    return {
        "source": lyrics.source,
        "syncType": lyrics.sync_type,
        "plainText": lyrics.plain_text,
        "language": lyrics.language,
        "lines": [
            {
                "text": line.text,
                "startTime": line.start_time,
                "endTime": line.end_time,
                "segments": [
                    {
                        "text": seg.text,
                        "startTime": seg.start_time,
                        "endTime": seg.end_time,
                    }
                    for seg in line.segments
                ]
            }
            for line in lyrics.lines
        ]
    }

@router.get("/lyrics/providers")
async def list_lyrics_providers():
    """Lista os providers de letras disponíveis e seus status."""
    return {
        "providers": get_available_providers(),
        "musixmatch": get_musixmatch_token_status(),
    }

@router.get("/lyrics/providers/test", dependencies=[Depends(get_current_user)])
async def test_lyrics_providers():
    """Testa se os providers de letras estão funcionando."""
    musixmatch_status = await test_musixmatch_connection()
    
    return {
        "musixmatch": musixmatch_status,
        "token_status": get_musixmatch_token_status(),
    }

@router.post("/lyrics/providers/musixmatch/reset", dependencies=[Depends(get_current_user)])
async def reset_musixmatch():
    """
    Reseta o token do Musixmatch.
    
    Use quando o Musixmatch estiver retornando erro 401.
    """
    was_reset = reset_musixmatch_token()
    
    return {
        "reset": was_reset,
        "message": "Token removido. Próxima busca vai gerar um novo." if was_reset else "Token não existia.",
        "token_status": get_musixmatch_token_status(),
    }

@router.get("/lyrics/plain")
async def get_plain_lyrics(filename: str):
    """Busca letras (pode ser sincronizadas ou não) para um arquivo local."""
    full_path = AudioManager.find_local_file(filename)
    lyrics = await LyricsProvider.get_lyrics(full_path)
    
    if not lyrics:
        raise HTTPException(404, "Letras não encontradas")
    
    return lyrics
