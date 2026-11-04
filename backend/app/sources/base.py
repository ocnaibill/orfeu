"""Contratos das fontes externas.

O resto do app fala com estas interfaces, nunca com Tidal, YT Music ou Soulseek
diretamente. Para trocar uma fonte (ou adicionar outra), escreva uma classe que
cumpra o contrato e registre em `registry.build_default_sources()`.

Os dados trafegam como dicts no formato que o app já usa (trackName, artistName,
collectionName, artworkUrl, tidalId...). Tipar isso é um passo futuro separado.
"""
from typing import Optional, Protocol, runtime_checkable

from fastapi import BackgroundTasks

from app.schemas import SmartDownloadRequest


@runtime_checkable
class CatalogSource(Protocol):
    """Catálogo de música: busca e detalhes de artista/álbum."""

    name: str

    def owns_id(self, item_id) -> bool:
        """True se este catálogo é quem emite IDs desse formato (usado para rotear detalhes)."""

    async def search(self, query: str, type: str = "song", limit: int = 25) -> list:
        """Busca `song`, `album` ou `artist`. Levanta exceção se a fonte falhar."""

    async def artist_details(self, artist_id) -> Optional[dict]:
        ...

    async def album_details(self, album_id) -> Optional[dict]:
        ...


@runtime_checkable
class DownloadSource(Protocol):
    """Fonte capaz de baixar uma faixa."""

    name: str

    async def try_download(self, request: SmartDownloadRequest, background_tasks: BackgroundTasks) -> Optional[dict]:
        """Tenta baixar. Devolve a resposta para o cliente, ou None se esta fonte não conseguiu
        (o próximo da lista tenta). `request` pode ser enriquecido (álbum, capa, id) para as
        fontes seguintes."""
