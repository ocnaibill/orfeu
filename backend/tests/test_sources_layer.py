"""Testes da camada app/sources com fontes falsas (sem Tidal/YT/Soulseek)."""
import pytest

from app.schemas import SmartDownloadRequest
from app.sources.base import CatalogSource, DownloadSource
from app.sources.registry import Sources, build_default_sources, get_sources, set_sources
from app.sources.services import CatalogService, DownloadService
from fastapi import HTTPException


@pytest.fixture
def anyio_backend():
    return "asyncio"  # plugin do anyio (já instalado com o Starlette) roda os testes async


class FakeCatalog:
    def __init__(self, name, items=None, owns=lambda i: False, fail=False, artist=None, album=None):
        self.name, self.items, self._owns, self.fail = name, items or [], owns, fail
        self.artist, self.album, self.calls = artist, album, []

    def owns_id(self, item_id):
        return self._owns(item_id)

    async def search(self, query, type="song", limit=25):
        self.calls.append(("search", query, type, limit))
        if self.fail:
            raise RuntimeError(f"{self.name} fora do ar")
        return [dict(i) for i in self.items]

    async def artist_details(self, artist_id):
        self.calls.append(("artist", artist_id))
        return self.artist

    async def album_details(self, album_id):
        self.calls.append(("album", album_id))
        return self.album


class FakeDownloader:
    def __init__(self, name, result=None, enrich=None):
        self.name, self.result, self.enrich, self.calls = name, result, enrich, []

    async def try_download(self, request, background_tasks):
        self.calls.append(request.model_copy())
        if self.enrich:
            self.enrich(request)
        return self.result


def song(artist, track, **extra):
    return {"type": "song", "artistName": artist, "trackName": track, "collectionName": "X", **extra}


@pytest.fixture(autouse=True)
def restore_default_sources():
    yield
    set_sources(None)


# --- contratos ---------------------------------------------------------------
def test_default_sources_follow_the_contracts():
    s = build_default_sources()
    assert [c.name for c in s.catalog.sources] == ["tidal", "ytmusic"]
    assert [d.name for d in s.downloads.sources] == ["tidal", "soulseek"]
    assert all(isinstance(c, CatalogSource) for c in s.catalog.sources)
    assert all(isinstance(d, DownloadSource) for d in s.downloads.sources)
    assert s.catalog.primary.name == "tidal" and s.catalog.get("ytmusic").name == "ytmusic"


def test_default_id_ownership():
    tidal, yt = build_default_sources().catalog.sources
    assert tidal.owns_id("123") and tidal.owns_id(123) and not tidal.owns_id("UCabc")
    assert yt.owns_id("UCabc") and yt.owns_id("MPREb_x") and not yt.owns_id("123")


def test_get_unknown_source_raises():
    with pytest.raises(KeyError):
        CatalogService([FakeCatalog("a")]).get("nope")
    with pytest.raises(ValueError):
        CatalogService([])


# --- catálogo: ordem, merge e falhas ----------------------------------------------
@pytest.mark.anyio
async def test_search_merges_three_sources_in_priority_order():
    a = FakeCatalog("a", [song("Adele", "Hello", tidalId=1)])
    b = FakeCatalog("b", [song("Adele", "Hello", videoId="v1"), song("Adele", "Skyfall")])
    c = FakeCatalog("c", [song("Adele", "Skyfall", videoId="dup"), song("Adele", "Easy On Me")])
    result = await CatalogService([a, b, c]).search("adele", "song", 10)
    assert [i["trackName"] for i in result] == ["Hello", "Skyfall", "Easy On Me"]
    assert result[0]["tidalId"] == 1 and result[0]["videoId"] == "v1"  # primária enriquecida
    assert a.calls == b.calls == c.calls == [("search", "adele", "song", 10)]


@pytest.mark.anyio
async def test_search_skips_a_failing_source():
    svc = CatalogService([FakeCatalog("a", fail=True), FakeCatalog("b", [song("Adele", "Hello")])])
    assert [i["trackName"] for i in await svc.search("adele", "song", 5)] == ["Hello"]
    assert await CatalogService([FakeCatalog("a", fail=True)]).search("x", "song", 5) == []


@pytest.mark.anyio
async def test_details_are_routed_by_id_ownership():
    a = FakeCatalog("a", owns=lambda i: str(i).isdigit(), artist={"from": "a"}, album={"from": "a"})
    b = FakeCatalog("b", owns=lambda i: not str(i).isdigit(), artist={"from": "b"}, album={"from": "b"})
    svc = CatalogService([a, b])
    assert await svc.artist_details("12") == {"from": "a"}
    assert await svc.artist_details("UC1") == {"from": "b"}
    assert await svc.album_details("MP1") == {"from": "b"}
    assert [c[0] for c in a.calls] == ["artist"] and [c[0] for c in b.calls] == ["artist", "album"]
    assert await CatalogService([FakeCatalog("z")]).artist_details("1") is None  # ninguém é dono


# --- download: ordem e fallback ---------------------------------------------------
def req(**kw):
    return SmartDownloadRequest(artist="Radiohead", track="Creep", **kw)


@pytest.mark.anyio
async def test_first_source_that_delivers_wins():
    first = FakeDownloader("first", {"status": "from first"})
    second = FakeDownloader("second", {"status": "from second"})
    assert await DownloadService([first, second]).smart_download(req(), None) == {"status": "from first"}
    assert second.calls == []


@pytest.mark.anyio
async def test_falls_through_none_and_shares_the_enriched_request():
    first = FakeDownloader("first", None, enrich=lambda r: setattr(r, "album", "Pablo Honey"))
    second = FakeDownloader("second", {"status": "from second"})
    assert await DownloadService([first, second]).smart_download(req(), None) == {"status": "from second"}
    assert second.calls[0].album == "Pablo Honey"  # o que a primeira descobriu chega à seguinte


@pytest.mark.anyio
async def test_all_sources_failing_is_404():
    svc = DownloadService([FakeDownloader("a"), FakeDownloader("b")])
    with pytest.raises(HTTPException) as exc:
        await svc.smart_download(req(), None)
    assert exc.value.status_code == 404 and exc.value.detail == "Nenhum ficheiro encontrado."


# --- plugando fontes no app inteiro -------------------------------------------------
def test_app_uses_whatever_sources_are_registered(client, auth):
    cat = FakeCatalog("only", [song("Adele", "Hello", tidalId=5)])
    dl = FakeDownloader("only", {"status": "fake download"})
    set_sources(Sources(catalog=CatalogService([cat]), downloads=DownloadService([dl]), soulseek=None))

    r = client.get("/search/catalog", params={"query": "adele"})
    assert [i["trackName"] for i in r.json()] == ["Hello"] and cat.calls

    r = client.post("/download/smart", headers=auth, json={"artist": "Zed", "track": "Nobody", "tidalId": 424242})
    assert r.json() == {"status": "fake download"} and dl.calls[0].track == "Nobody"


def test_set_sources_none_restores_defaults():
    set_sources(Sources(catalog=CatalogService([FakeCatalog("x")]), downloads=DownloadService([]), soulseek=None))
    set_sources(None)
    assert [c.name for c in get_sources().catalog.sources] == ["tidal", "ytmusic"]
