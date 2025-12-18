"""
Provedor de Letras Sincronizadas - Versão Aprimorada

Suporta múltiplas fontes via biblioteca syncedlyrics:
1. Apple Music API (TTML - sincronização por sílaba) - implementação própria
2. Musixmatch (LRC/Enhanced - sincronização por linha ou palavra)
3. LRCLIB (LRC - sincronização por linha)
4. NetEase (LRC - sincronização por linha) - ótimo para músicas asiáticas
5. Megalobiz (LRC - sincronização por linha)
6. Genius (texto plano)

O sistema tenta na ordem de qualidade:
1. Apple Music (syllable sync)
2. Musixmatch Enhanced (word-by-word)
3. Musixmatch Regular / LRCLIB / NetEase / Megalobiz (line sync)
4. Genius (plain text)
"""

import httpx
import re
import os
from typing import Optional, List, Dict, Any
from dataclasses import dataclass
import xml.etree.ElementTree as ET
import asyncio
from concurrent.futures import ThreadPoolExecutor

# Biblioteca syncedlyrics para múltiplas fontes
try:
    import syncedlyrics
    SYNCEDLYRICS_AVAILABLE = True
except ImportError:
    SYNCEDLYRICS_AVAILABLE = False
    print("⚠️ syncedlyrics não instalado. Execute: pip install syncedlyrics")


@dataclass
class LyricSegment:
    """Segmento de letra (pode ser uma palavra ou sílaba)"""
    text: str
    start_time: float  # em segundos
    end_time: float    # em segundos


@dataclass
class LyricLine:
    """Uma linha de letra com seus segmentos"""
    text: str
    start_time: float
    end_time: float
    segments: List[LyricSegment]


@dataclass 
class SyncedLyrics:
    """Letras sincronizadas completas"""
    source: str  # "apple_music", "lrclib", "plain"
    sync_type: str  # "syllable", "line", "none"
    lines: List[LyricLine]
    plain_text: str
    language: Optional[str] = None


class SyncedLyricsProvider:
    """
    Provedor de letras sincronizadas com suporte a múltiplas fontes.
    
    Prioridade:
    1. Musixmatch Enhanced (word-by-word karaoke)
    2. Musixmatch (line sync)
    3. LRCLIB (line sync)
    4. NetEase (apenas para músicas asiáticas)
    """
    
    # Apple Music API (requer Developer Token)
    APPLE_MUSIC_API = "https://amp-api.music.apple.com"
    
    # LRCLIB API (gratuito, sem auth) - backup próprio
    LRCLIB_API = "https://lrclib.net/api"
    
    # Executor para rodar syncedlyrics (síncrono) em thread
    _executor = ThreadPoolExecutor(max_workers=3)
    
    # Caracteres para detectar músicas asiáticas (CJK)
    CJK_RANGES = (
        '\u4e00-\u9fff'    # CJK Unified Ideographs (Chinese)
        '\u3040-\u309f'    # Hiragana (Japanese)
        '\u30a0-\u30ff'    # Katakana (Japanese)
        '\uac00-\ud7af'    # Hangul Syllables (Korean)
    )
    
    def __init__(self, apple_developer_token: Optional[str] = None):
        self.apple_token = apple_developer_token or os.getenv("APPLE_MUSIC_TOKEN")
    
    def _is_asian_text(self, text: str) -> bool:
        """Detecta se o texto contém caracteres asiáticos (CJK)"""
        import re
        pattern = f'[{self.CJK_RANGES}]'
        return bool(re.search(pattern, text))
    
    async def get_synced_lyrics(
        self,
        track_name: str,
        artist_name: str,
        album_name: Optional[str] = None,
        duration: Optional[int] = None,
        isrc: Optional[str] = None,
        apple_music_id: Optional[str] = None,
        prefer_enhanced: bool = True,
    ) -> Optional[SyncedLyrics]:
        """
        Busca letras sincronizadas de múltiplas fontes.
        
        Prioridade:
        1. Musixmatch Enhanced (word-by-word karaoke)
        2. Musixmatch (line sync)
        3. LRCLIB (line sync)
        4. NetEase (apenas para músicas asiáticas)
        
        Args:
            track_name: Nome da música
            artist_name: Nome do artista
            album_name: Nome do álbum (opcional)
            duration: Duração em segundos (opcional)
            isrc: Código ISRC (opcional)
            apple_music_id: ID do Apple Music (opcional)
            prefer_enhanced: Se True, tenta buscar lyrics word-by-word primeiro
        """
        
        search_term = f"{track_name} {artist_name}"
        is_asian = self._is_asian_text(track_name) or self._is_asian_text(artist_name)
        
        if SYNCEDLYRICS_AVAILABLE:
            # 1. Musixmatch Enhanced (word-by-word karaoke)
            if prefer_enhanced:
                print(f"🔍 Buscando: Musixmatch Enhanced...")
                enhanced_lyrics = await self._get_syncedlyrics(
                    search_term, enhanced=True, synced_only=True, providers=["Musixmatch"]
                )
                if enhanced_lyrics and enhanced_lyrics.sync_type == "word":
                    print(f"✅ Letras encontradas: Musixmatch Enhanced (word sync)")
                    return enhanced_lyrics
            
            # 2. Musixmatch (line sync)
            print(f"🔍 Buscando: Musixmatch...")
            musixmatch_lyrics = await self._get_syncedlyrics(
                search_term, enhanced=False, synced_only=True, providers=["Musixmatch"]
            )
            if musixmatch_lyrics and musixmatch_lyrics.sync_type == "line":
                print(f"✅ Letras encontradas: Musixmatch (line sync)")
                return musixmatch_lyrics
            
            # 3. LRCLIB (line sync)
            print(f"🔍 Buscando: LRCLIB...")
            lrclib_lyrics = await self._get_syncedlyrics(
                search_term, enhanced=False, synced_only=True, providers=["Lrclib"]
            )
            if lrclib_lyrics and lrclib_lyrics.sync_type == "line":
                print(f"✅ Letras encontradas: LRCLIB (line sync)")
                return lrclib_lyrics
            
            # 4. NetEase (apenas para músicas asiáticas)
            if is_asian:
                print(f"🔍 Buscando: NetEase (música asiática detectada)...")
                netease_lyrics = await self._get_syncedlyrics(
                    search_term, enhanced=False, synced_only=True, providers=["NetEase"]
                )
                if netease_lyrics and netease_lyrics.sync_type == "line":
                    print(f"✅ Letras encontradas: NetEase (line sync)")
                    return netease_lyrics
        
        # 5. Fallback para implementação própria do LRCLIB
        print(f"🔍 Buscando: LRCLIB (fallback interno)...")
        lrclib_fallback = await self._get_lrclib_lyrics(
            track_name, artist_name, album_name, duration
        )
        if lrclib_fallback:
            print(f"✅ Letras encontradas: LRCLIB fallback ({lrclib_fallback.sync_type})")
            return lrclib_fallback
        
        print(f"❌ Nenhuma letra encontrada para: {search_term}")
        return None
    
    async def _get_syncedlyrics(
        self,
        search_term: str,
        enhanced: bool = False,
        synced_only: bool = True,
        plain_only: bool = False,
        providers: Optional[List[str]] = None,
    ) -> Optional[SyncedLyrics]:
        """
        Busca letras usando a biblioteca syncedlyrics.
        
        Roda em thread separada pois syncedlyrics é síncrono.
        """
        if not SYNCEDLYRICS_AVAILABLE:
            return None
        
        try:
            loop = asyncio.get_event_loop()
            
            # Executa syncedlyrics.search em thread
            lrc = await loop.run_in_executor(
                self._executor,
                lambda: syncedlyrics.search(
                    search_term,
                    enhanced=enhanced,
                    synced_only=synced_only,
                    plain_only=plain_only,
                    providers=providers or [],
                )
            )
            
            if not lrc:
                return None
            
            # Determina o tipo de sincronização e fonte
            sync_type = self._identify_sync_type(lrc)
            source = self._identify_source(lrc, enhanced)
            
            # Parseia LRC para estrutura
            if sync_type in ("word", "line"):
                lines = self._parse_lrc(lrc)
            else:
                lines = []
            
            return SyncedLyrics(
                source=source,
                sync_type=sync_type,
                lines=lines,
                plain_text=self._lrc_to_plain(lrc) if lines else lrc,
            )
            
        except Exception as e:
            print(f"⚠️ Erro syncedlyrics: {e}")
            return None
    
    def _identify_sync_type(self, lrc: str) -> str:
        """Identifica o tipo de sincronização do LRC"""
        if not lrc:
            return "none"
        
        # Enhanced/word-by-word tem tags como <00:01.23>
        if re.search(r'<\d+:\d+\.\d+>', lrc):
            return "word"
        
        # Line sync tem tags como [00:01.23]
        if re.search(r'\[\d+:\d+\.\d+\]', lrc):
            return "line"
        
        return "none"
    
    def _identify_source(self, lrc: str, enhanced: bool) -> str:
        """Tenta identificar a fonte das letras"""
        if enhanced and re.search(r'<\d+:\d+\.\d+>', lrc):
            return "musixmatch_enhanced"
        return "syncedlyrics"
    
    def _lrc_to_plain(self, lrc: str) -> str:
        """Converte LRC para texto plano"""
        # Remove timestamps [MM:SS.mm] e <MM:SS.mm>
        plain = re.sub(r'\[\d+:\d+[\.:]?\d*\]\s*', '', lrc)
        plain = re.sub(r'<\d+:\d+[\.:]?\d*>\s*', '', plain)
        return plain.strip()
    
    async def _get_apple_music_lyrics(
        self,
        track_name: str,
        artist_name: str,
        apple_music_id: Optional[str] = None,
        isrc: Optional[str] = None,
    ) -> Optional[SyncedLyrics]:
        """Busca letras no Apple Music (TTML com sincronização por sílaba)"""
        
        if not self.apple_token:
            return None
        
        try:
            async with httpx.AsyncClient() as client:
                headers = {
                    "Authorization": f"Bearer {self.apple_token}",
                    "Origin": "https://music.apple.com",
                }
                
                song_id = apple_music_id
                
                # Se não tem ID, busca pelo nome ou ISRC
                if not song_id:
                    song_id = await self._search_apple_music_id(
                        client, headers, track_name, artist_name, isrc
                    )
                
                if not song_id:
                    print(f"⚠️ Apple Music: Não encontrou ID para {track_name}")
                    return None
                
                # Busca as letras syllable-lyrics
                lyrics_url = f"{self.APPLE_MUSIC_API}/v1/catalog/br/songs/{song_id}/syllable-lyrics"
                
                resp = await client.get(lyrics_url, headers=headers, timeout=10.0)
                
                if resp.status_code != 200:
                    print(f"⚠️ Apple Music lyrics: {resp.status_code}")
                    return None
                
                data = resp.json()
                
                # Extrai TTML
                ttml = data.get("data", [{}])[0].get("attributes", {}).get("ttml")
                
                if not ttml:
                    print("⚠️ Apple Music: TTML não encontrado")
                    return None
                
                # Parseia TTML
                return self._parse_ttml(ttml)
                
        except Exception as e:
            print(f"❌ Erro Apple Music lyrics: {e}")
            return None
    
    async def _search_apple_music_id(
        self,
        client: httpx.AsyncClient,
        headers: dict,
        track_name: str,
        artist_name: str,
        isrc: Optional[str] = None,
    ) -> Optional[str]:
        """Busca o Apple Music ID de uma música"""
        
        try:
            # Tentar por ISRC primeiro (mais preciso)
            if isrc:
                url = f"{self.APPLE_MUSIC_API}/v1/catalog/br/songs"
                params = {"filter[isrc]": isrc}
                resp = await client.get(url, headers=headers, params=params, timeout=5.0)
                
                if resp.status_code == 200:
                    data = resp.json()
                    if data.get("data"):
                        return data["data"][0]["id"]
            
            # Buscar por nome
            search_url = f"{self.APPLE_MUSIC_API}/v1/catalog/br/search"
            params = {
                "term": f"{track_name} {artist_name}",
                "types": "songs",
                "limit": 5,
            }
            
            resp = await client.get(search_url, headers=headers, params=params, timeout=5.0)
            
            if resp.status_code == 200:
                data = resp.json()
                songs = data.get("results", {}).get("songs", {}).get("data", [])
                
                # Encontra a melhor match
                for song in songs:
                    attrs = song.get("attributes", {})
                    if (
                        track_name.lower() in attrs.get("name", "").lower() and
                        artist_name.lower() in attrs.get("artistName", "").lower()
                    ):
                        return song["id"]
                
                # Se não achou match exato, retorna o primeiro
                if songs:
                    return songs[0]["id"]
                    
        except Exception as e:
            print(f"⚠️ Erro buscando Apple Music ID: {e}")
        
        return None
    
    def _parse_ttml(self, ttml: str) -> Optional[SyncedLyrics]:
        """Parseia TTML do Apple Music para estrutura de letras"""
        
        try:
            # Remove namespace para facilitar parsing
            ttml = re.sub(r'\sxmlns[^"]*"[^"]*"', '', ttml)
            root = ET.fromstring(ttml)
            
            lines: List[LyricLine] = []
            plain_lines: List[str] = []
            
            # Encontra todos os elementos <p> (parágrafos/linhas)
            for p in root.iter('p'):
                line_text_parts = []
                segments: List[LyricSegment] = []
                line_start = float('inf')
                line_end = 0.0
                
                # Processa spans (segmentos/sílabas)
                for span in p.iter('span'):
                    text = span.text or ""
                    if not text.strip():
                        continue
                    
                    begin = span.get('begin', '0s')
                    end = span.get('end', '0s')
                    
                    start_time = self._parse_time(begin)
                    end_time = self._parse_time(end)
                    
                    line_start = min(line_start, start_time)
                    line_end = max(line_end, end_time)
                    
                    segments.append(LyricSegment(
                        text=text,
                        start_time=start_time,
                        end_time=end_time,
                    ))
                    line_text_parts.append(text)
                
                # Se não tem spans, pega o texto do <p> diretamente
                if not segments and p.text:
                    text = p.text.strip()
                    if text:
                        begin = p.get('begin', '0s')
                        end = p.get('end', '0s')
                        start_time = self._parse_time(begin)
                        end_time = self._parse_time(end)
                        
                        segments.append(LyricSegment(
                            text=text,
                            start_time=start_time,
                            end_time=end_time,
                        ))
                        line_text_parts.append(text)
                        line_start = start_time
                        line_end = end_time
                
                if segments:
                    line_text = "".join(line_text_parts)
                    lines.append(LyricLine(
                        text=line_text,
                        start_time=line_start if line_start != float('inf') else 0,
                        end_time=line_end,
                        segments=segments,
                    ))
                    plain_lines.append(line_text)
            
            if not lines:
                return None
            
            return SyncedLyrics(
                source="apple_music",
                sync_type="syllable",
                lines=lines,
                plain_text="\n".join(plain_lines),
            )
            
        except Exception as e:
            print(f"❌ Erro parsing TTML: {e}")
            return None
    
    def _parse_time(self, time_str: str) -> float:
        """Converte string de tempo TTML para segundos"""
        
        # Remove 's' suffix se existir
        time_str = time_str.rstrip('s')
        
        # Formato: HH:MM:SS.mmm ou MM:SS.mmm ou SS.mmm
        if ':' in time_str:
            parts = time_str.split(':')
            if len(parts) == 3:
                h, m, s = parts
                return float(h) * 3600 + float(m) * 60 + float(s)
            elif len(parts) == 2:
                m, s = parts
                return float(m) * 60 + float(s)
        
        # Apenas segundos
        try:
            return float(time_str)
        except:
            return 0.0
    
    async def _get_lrclib_lyrics(
        self,
        track_name: str,
        artist_name: str,
        album_name: Optional[str] = None,
        duration: Optional[int] = None,
    ) -> Optional[SyncedLyrics]:
        """Busca letras no LRCLIB (LRC com sincronização por linha)"""
        
        try:
            async with httpx.AsyncClient() as client:
                # 1. Busca exata
                params = {
                    "artist_name": artist_name,
                    "track_name": track_name,
                }
                if album_name:
                    params["album_name"] = album_name
                if duration:
                    params["duration"] = duration
                
                resp = await client.get(
                    f"{self.LRCLIB_API}/get",
                    params=params,
                    timeout=5.0
                )
                
                data = None
                
                if resp.status_code == 200:
                    data = resp.json()
                elif resp.status_code == 404:
                    # 2. Busca aproximada
                    search_params = {"q": f"{artist_name} {track_name}"}
                    search_resp = await client.get(
                        f"{self.LRCLIB_API}/search",
                        params=search_params,
                        timeout=5.0
                    )
                    if search_resp.status_code == 200:
                        results = search_resp.json()
                        if results:
                            data = results[0]
                
                if not data:
                    return None
                
                # Prefere letras sincronizadas
                synced_lrc = data.get("syncedLyrics")
                plain_lyrics = data.get("plainLyrics", "")
                
                if synced_lrc:
                    lines = self._parse_lrc(synced_lrc)
                    return SyncedLyrics(
                        source="lrclib",
                        sync_type="line",
                        lines=lines,
                        plain_text=plain_lyrics or "\n".join(l.text for l in lines),
                    )
                elif plain_lyrics:
                    # Sem sincronização, retorna texto plano
                    return SyncedLyrics(
                        source="lrclib",
                        sync_type="none",
                        lines=[],
                        plain_text=plain_lyrics,
                    )
                
        except Exception as e:
            print(f"❌ Erro LRCLIB: {e}")
        
        return None
    
    def _parse_lrc(self, lrc: str) -> List[LyricLine]:
        """Parseia formato LRC para lista de linhas (suporta enhanced/word-by-word)"""
        
        lines: List[LyricLine] = []
        
        # Detecta se é Enhanced (word-by-word) ou line sync
        is_enhanced = bool(re.search(r'<\d+:\d+\.\d+>', lrc))
        
        if is_enhanced:
            return self._parse_enhanced_lrc(lrc)
        
        # Regex para [MM:SS.mm] ou [MM:SS:mm]
        pattern = r'\[(\d+):(\d+)[\.:](\d+)\]\s*(.*)'
        
        for line in lrc.split('\n'):
            match = re.match(pattern, line.strip())
            if match:
                minutes = int(match.group(1))
                seconds = int(match.group(2))
                milliseconds = int(match.group(3))
                text = match.group(4).strip()
                
                if text:  # Ignora linhas vazias
                    start_time = minutes * 60 + seconds + milliseconds / 100
                    
                    lines.append(LyricLine(
                        text=text,
                        start_time=start_time,
                        end_time=0,  # Será calculado depois
                        segments=[LyricSegment(
                            text=text,
                            start_time=start_time,
                            end_time=0,
                        )],
                    ))
        
        # Calcula end_time baseado no início da próxima linha
        for i, line in enumerate(lines):
            if i < len(lines) - 1:
                line.end_time = lines[i + 1].start_time
                line.segments[0].end_time = line.end_time
            else:
                # Última linha: assume 5 segundos de duração
                line.end_time = line.start_time + 5.0
                line.segments[0].end_time = line.end_time
        
        return lines
    
    def _parse_enhanced_lrc(self, lrc: str) -> List[LyricLine]:
        """
        Parseia formato Enhanced LRC (word-by-word).
        
        Formato: [00:12.34] <00:12.34> word1 <00:12.56> word2 <00:12.78> word3
        """
        lines: List[LyricLine] = []
        
        # Pattern para linha com timestamp inicial
        line_pattern = r'\[(\d+):(\d+)[\.:](\d+)\]\s*(.*)'
        # Pattern para word timestamps
        word_pattern = r'<(\d+):(\d+)[\.:](\d+)>\s*([^<\n]*)'
        
        for line in lrc.split('\n'):
            line_match = re.match(line_pattern, line.strip())
            if not line_match:
                continue
            
            minutes = int(line_match.group(1))
            seconds = int(line_match.group(2))
            milliseconds = int(line_match.group(3))
            line_start = minutes * 60 + seconds + milliseconds / 100
            
            content = line_match.group(4)
            
            # Extrai palavras com timestamps
            segments: List[LyricSegment] = []
            word_matches = list(re.finditer(word_pattern, content))
            
            if word_matches:
                for i, wmatch in enumerate(word_matches):
                    w_min = int(wmatch.group(1))
                    w_sec = int(wmatch.group(2))
                    w_ms = int(wmatch.group(3))
                    word_text = wmatch.group(4).strip()
                    
                    if word_text:
                        word_start = w_min * 60 + w_sec + w_ms / 100
                        
                        # End time é o início da próxima palavra
                        if i < len(word_matches) - 1:
                            next_match = word_matches[i + 1]
                            word_end = int(next_match.group(1)) * 60 + int(next_match.group(2)) + int(next_match.group(3)) / 100
                        else:
                            word_end = word_start + 0.5  # Assume 500ms para última palavra
                        
                        segments.append(LyricSegment(
                            text=word_text,
                            start_time=word_start,
                            end_time=word_end,
                        ))
            else:
                # Fallback: linha sem word timestamps
                text = content.strip()
                if text:
                    segments.append(LyricSegment(
                        text=text,
                        start_time=line_start,
                        end_time=line_start + 3.0,
                    ))
            
            if segments:
                line_text = " ".join(s.text for s in segments)
                line_end = segments[-1].end_time if segments else line_start + 3.0
                
                lines.append(LyricLine(
                    text=line_text,
                    start_time=line_start,
                    end_time=line_end,
                    segments=segments,
                ))
        
        return lines


# Instância global
synced_lyrics_provider = SyncedLyricsProvider()


# Funções auxiliares para uso direto
async def get_lyrics(
    track_name: str,
    artist_name: str,
    album_name: Optional[str] = None,
    prefer_enhanced: bool = True,
) -> Optional[SyncedLyrics]:
    """
    Função auxiliar para buscar letras rapidamente.
    
    Exemplo:
        lyrics = await get_lyrics("Bad Guy", "Billie Eilish")
        if lyrics:
            print(f"Fonte: {lyrics.source}, Tipo: {lyrics.sync_type}")
            for line in lyrics.lines:
                print(f"[{line.start_time:.2f}] {line.text}")
    """
    return await synced_lyrics_provider.get_synced_lyrics(
        track_name=track_name,
        artist_name=artist_name,
        album_name=album_name,
        prefer_enhanced=prefer_enhanced,
    )


def get_available_providers() -> List[str]:
    """Retorna lista de providers disponíveis (em ordem de prioridade)"""
    providers = []
    
    if SYNCEDLYRICS_AVAILABLE:
        providers.extend([
            "musixmatch_enhanced",  # 1. Word-by-word karaoke
            "musixmatch",           # 2. Line sync
            "lrclib",               # 3. Line sync
            "netease",              # 4. Para músicas asiáticas
        ])
    
    providers.append("lrclib_internal")  # Fallback
    
    return providers


def get_musixmatch_token_status() -> Dict[str, Any]:
    """
    Verifica o status do token do Musixmatch.
    
    Retorna:
        dict com 'has_token', 'expired', 'expires_in', 'token_preview'
    """
    from pathlib import Path
    import json
    import time
    
    cache_dir = Path.home() / ".cache" / "syncedlyrics"
    token_file = cache_dir / "musixmatch_token.json"
    
    result = {
        "has_token": False,
        "expired": True,
        "expires_in": 0,
        "token_preview": None,
        "cache_path": str(token_file),
    }
    
    if token_file.exists():
        try:
            with open(token_file) as f:
                data = json.load(f)
            
            token = data.get("token", "")
            exp_time = data.get("expiration_time", 0)
            current = int(time.time())
            
            result["has_token"] = bool(token)
            result["expired"] = current >= exp_time
            result["expires_in"] = max(0, exp_time - current)
            result["token_preview"] = token[:20] + "..." if token else None
        except Exception as e:
            result["error"] = str(e)
    
    return result


def reset_musixmatch_token() -> bool:
    """
    Remove o cache do token do Musixmatch para forçar renovação.
    
    Use quando o Musixmatch estiver retornando 401.
    
    Retorna:
        True se o token foi removido, False se não existia
    """
    from pathlib import Path
    
    token_file = Path.home() / ".cache" / "syncedlyrics" / "musixmatch_token.json"
    
    if token_file.exists():
        import os
        os.remove(token_file)
        print("🔄 Token do Musixmatch removido. Próxima busca vai gerar um novo.")
        return True
    
    return False


async def test_musixmatch_connection() -> Dict[str, Any]:
    """
    Testa se o Musixmatch está funcionando.
    
    Retorna:
        dict com 'working', 'has_enhanced', 'message'
    """
    if not SYNCEDLYRICS_AVAILABLE:
        return {
            "working": False,
            "has_enhanced": False,
            "message": "syncedlyrics não está instalado"
        }
    
    import asyncio
    from concurrent.futures import ThreadPoolExecutor
    
    test_track = "Shape of You"
    test_artist = "Ed Sheeran"
    
    result = {
        "working": False,
        "has_enhanced": False,
        "line_sync": False,
        "message": "",
    }
    
    try:
        loop = asyncio.get_event_loop()
        executor = ThreadPoolExecutor(max_workers=1)
        
        # Testa Enhanced
        enhanced = await loop.run_in_executor(
            executor,
            lambda: syncedlyrics.search(
                f"{test_track} {test_artist}",
                enhanced=True,
                synced_only=True,
                providers=["Musixmatch"]
            )
        )
        
        if enhanced and "<" in enhanced:
            result["working"] = True
            result["has_enhanced"] = True
            result["line_sync"] = True
            result["message"] = "Musixmatch Enhanced (word-by-word) funcionando!"
        elif enhanced:
            result["working"] = True
            result["line_sync"] = True
            result["message"] = "Musixmatch funcionando (sem Enhanced)"
        else:
            # Tenta sync normal
            normal = await loop.run_in_executor(
                executor,
                lambda: syncedlyrics.search(
                    f"{test_track} {test_artist}",
                    synced_only=True,
                    providers=["Musixmatch"]
                )
            )
            
            if normal:
                result["working"] = True
                result["line_sync"] = True
                result["message"] = "Musixmatch funcionando (line sync)"
            else:
                result["message"] = "Musixmatch não retornou letras. Tente resetar o token."
                
    except Exception as e:
        result["message"] = f"Erro: {str(e)}"
    
    return result
