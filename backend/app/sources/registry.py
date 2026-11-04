"""Composição das fontes: ordem de prioridade e acesso global (com troca para testes)."""
from dataclasses import dataclass
from typing import Optional

from app.sources.services import CatalogService, DownloadService
from app.sources.soulseek import SoulseekDownloader
from app.sources.tidal import TidalCatalog, TidalDownloader
from app.sources.ytmusic import YTMusicCatalog


@dataclass
class Sources:
    catalog: CatalogService
    downloads: DownloadService
    soulseek: SoulseekDownloader  # acesso à API bruta do slskd (rotas legadas)


def build_default_sources() -> Sources:
    """Ordem de prioridade do app: catálogo Tidal > YT Music; download Tidal > Soulseek."""
    soulseek = SoulseekDownloader()
    return Sources(
        catalog=CatalogService([TidalCatalog(), YTMusicCatalog()]),
        downloads=DownloadService([TidalDownloader(), soulseek]),
        soulseek=soulseek,
    )


_sources: Optional[Sources] = None


def get_sources() -> Sources:
    global _sources
    if _sources is None:
        _sources = build_default_sources()
    return _sources


def set_sources(sources: Optional[Sources]) -> None:
    """Troca as fontes (testes, ou outra configuração). `None` volta ao padrão."""
    global _sources
    _sources = sources
