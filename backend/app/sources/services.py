"""Serviços de alto nível sobre as fontes: decidem ORDEM, FALLBACK e MERGE.

Os routers chamam estes serviços; os serviços chamam as fontes (`CatalogSource`,
`DownloadSource`). Assim a política (Tidal primeiro, YT Music de cobertura, Soulseek por
último) fica em um lugar só e as fontes ficam intercambiáveis.
"""
import re
from typing import List, Optional

from fastapi import BackgroundTasks, HTTPException

from app.schemas import SmartDownloadRequest
from app.services.local_library import normalize_text, find_local_match
from app.sources.base import CatalogSource, DownloadSource


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


class CatalogService:
    """Busca e detalhes no catálogo, combinando as fontes na ordem de prioridade."""

    def __init__(self, sources: List[CatalogSource]):
        if not sources:
            raise ValueError("CatalogService precisa de ao menos uma fonte")
        self.sources = list(sources)

    @property
    def primary(self) -> CatalogSource:
        """Fonte de maior prioridade (metadados mais ricos, IDs de álbum/artista)."""
        return self.sources[0]

    def get(self, name: str) -> CatalogSource:
        for source in self.sources:
            if source.name == name:
                return source
        raise KeyError(f"Fonte de catálogo '{name}' não registrada")

    async def search(self, query: str, type: str, limit: int) -> list:
        """Consulta todas as fontes em ordem e mescla sem duplicatas.

        Uma fonte que falha não derruba as outras. A primeira tem prioridade no merge e
        é enriquecida com dados das demais (ex.: videoId do YT Music).
        """
        per_source = []
        for source in self.sources:
            try:
                results = await source.search(query, type, limit)
                print(f"   ✅ {source.name} retornou {len(results)} resultados.")
            except Exception as e:
                print(f"   ❌ Erro em {source.name}: {e}")
                results = []
            per_source.append(results)

        rest = [item for results in per_source[1:] for item in results]
        results = merge_and_deduplicate_results(per_source[0], rest, type)
        print(f"   🔀 Após merge/dedup: {len(results)} resultados únicos")
        return results

    def _owner(self, item_id) -> Optional[CatalogSource]:
        for source in self.sources:
            if source.owns_id(item_id):
                return source
        return None

    async def artist_details(self, artist_id) -> Optional[dict]:
        """Detalhes do artista, pela fonte que emite esse formato de ID."""
        source = self._owner(artist_id)
        if source is None:
            return None
        print(f"🎤 Buscando artista em {source.name}: {artist_id}")
        return await source.artist_details(artist_id)

    async def album_details(self, album_id) -> Optional[dict]:
        source = self._owner(album_id)
        if source is None:
            return None
        return await source.album_details(album_id)


class DownloadService:
    """Baixa uma faixa tentando as fontes em ordem (Tidal direto, depois Soulseek)."""

    def __init__(self, sources: List[DownloadSource]):
        self.sources = list(sources)

    async def smart_download(self, request: SmartDownloadRequest, background_tasks: BackgroundTasks) -> dict:
        print(f"🤖 Smart Download: {request.artist} - {request.track}")

        # Primeiro verifica pelo tidal_id (mais preciso) se disponível
        local_match = find_local_match(
            artist=request.artist,
            track=request.track,
            album=request.album,
            tidal_id=request.tidalId
        )
        if local_match:
            print(f"✅ Cache Local: {local_match}")
            return {"status": "Already downloaded", "file": local_match, "display_name": request.track}

        for source in self.sources:
            result = await source.try_download(request, background_tasks)
            if result is not None:
                return result

        raise HTTPException(404, "Nenhum ficheiro encontrado.")
