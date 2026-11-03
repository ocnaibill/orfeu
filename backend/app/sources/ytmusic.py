"""YouTube Music (ytmusicapi): cobertura extra de catálogo."""
from fastapi.concurrency import run_in_threadpool

from app.services.catalog_provider import CatalogProvider
from app.services.metadata_provider import MetadataProvider


class YTMusicCatalog:
    name = "ytmusic"

    def owns_id(self, item_id) -> bool:
        # IDs do YT Music não são numéricos (UC..., MPREb_...)
        return not str(item_id).isdigit()

    async def search(self, query: str, type: str = "song", limit: int = 40) -> list:
        return await run_in_threadpool(CatalogProvider.search_catalog, query, type, limit)

    async def artist_details(self, artist_id):
        return await run_in_threadpool(CatalogProvider.get_artist_details, artist_id)

    async def album_details(self, album_id):
        details = await run_in_threadpool(CatalogProvider.get_album_details, album_id)
        # Enriquece o álbum do YT Music com gênero (o Tidal já faz isso internamente)
        if details and not details.get('genre'):
            genre = await run_in_threadpool(MetadataProvider.get_genre, details['artistName'], details['collectionName'])
            details['genre'] = genre
        return details
