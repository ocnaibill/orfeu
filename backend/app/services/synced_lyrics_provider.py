"""
Provedor de Letras Sincronizadas

Suporta múltiplas fontes:
1. Apple Music API (TTML - sincronização por sílaba)
2. LRCLIB (LRC - sincronização por linha)

O sistema tenta Apple Music primeiro para melhor qualidade,
e faz fallback para LRCLIB se não encontrar.
"""

import httpx
import re
import os
from typing import Optional, List, Dict, Any
from dataclasses import dataclass
import xml.etree.ElementTree as ET


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
    """
    
    # Apple Music API (requer Developer Token)
    APPLE_MUSIC_API = "https://amp-api.music.apple.com"
    
    # LRCLIB API (gratuito, sem auth)
    LRCLIB_API = "https://lrclib.net/api"
    
    def __init__(self, apple_developer_token: Optional[str] = None):
        self.apple_token = apple_developer_token or os.getenv("APPLE_MUSIC_TOKEN")
    
    async def get_synced_lyrics(
        self,
        track_name: str,
        artist_name: str,
        album_name: Optional[str] = None,
        duration: Optional[int] = None,
        isrc: Optional[str] = None,
        apple_music_id: Optional[str] = None,
    ) -> Optional[SyncedLyrics]:
        """
        Busca letras sincronizadas de múltiplas fontes.
        
        Prioridade:
        1. Apple Music (se tiver ID ou token)
        2. LRCLIB
        """
        
        # 1. Tentar Apple Music se tiver ID ou puder buscar
        if self.apple_token:
            apple_lyrics = await self._get_apple_music_lyrics(
                track_name, artist_name, apple_music_id, isrc
            )
            if apple_lyrics:
                return apple_lyrics
        
        # 2. Fallback para LRCLIB
        lrclib_lyrics = await self._get_lrclib_lyrics(
            track_name, artist_name, album_name, duration
        )
        if lrclib_lyrics:
            return lrclib_lyrics
        
        return None
    
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
        """Parseia formato LRC para lista de linhas"""
        
        lines: List[LyricLine] = []
        
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


# Instância global
synced_lyrics_provider = SyncedLyricsProvider()
