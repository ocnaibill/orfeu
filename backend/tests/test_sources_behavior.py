"""Testes de caracterização das fontes externas (Tidal, YT Music, Soulseek).

Eles simulam os providers (sem rede) e fixam COMO o app os usa: quais métodos são
chamados, com quais argumentos, em que ordem e o que volta ao cliente. Foram escritos
antes da camada `app/sources` e precisam continuar passando sem alteração depois dela.
Por isso os fakes entram nos providers (classes/funções originais), não na camada nova.
"""
import asyncio
import os
import sys
from types import SimpleNamespace

import pytest

from app.services import local_library, slskd_client
from app.services.audio_manager import AudioManager
from app.services.catalog_provider import CatalogProvider
from app.services.lastfm_provider import LastfmProvider
from app.services.metadata_provider import MetadataProvider
from app.services.tidal_provider import TidalProvider

from conftest import MUSIC_DIR


def patch_everywhere(monkeypatch, owner, name, fake):
    """Troca `owner.name` e toda cópia importada por nome (`from x import name`) em app.*"""
    original = getattr(owner, name)
    patched = 0
    for modname, mod in list(sys.modules.items()):
        if modname.startswith("app") and mod is not None and getattr(mod, name, None) is original:
            monkeypatch.setattr(mod, name, fake)
            patched += 1
    assert patched, f"{name} não encontrado em nenhum módulo app.*"


# --------------------------------------------------------------------------
# fixtures: fakes dos providers
# --------------------------------------------------------------------------
@pytest.fixture
def tidal(client, monkeypatch):
    s = SimpleNamespace(search=[], artist=None, album=None, download=None, calls=[], raises=False)

    def search_catalog(query, limit=25, type="song"):
        s.calls.append(("search", query, limit, type))
        if s.raises:
            raise RuntimeError("tidal fora do ar")
        return [dict(i) for i in s.search]

    def get_artist_details(artist_id):
        s.calls.append(("artist", artist_id))
        if s.raises:
            raise RuntimeError("tidal fora do ar")
        return s.artist

    def get_album_details(collection_id):
        s.calls.append(("album", collection_id))
        if s.raises:
            raise RuntimeError("tidal fora do ar")
        return s.album

    def get_download_url(track_id):
        s.calls.append(("download_url", track_id))
        return s.download

    for name, fn in [("search_catalog", search_catalog), ("get_artist_details", get_artist_details),
                     ("get_album_details", get_album_details), ("get_download_url", get_download_url)]:
        monkeypatch.setattr(TidalProvider, name, staticmethod(fn))
    return s


@pytest.fixture
def yt(client, monkeypatch):
    s = SimpleNamespace(search=[], artist=None, album=None, calls=[], raises=False)

    def search_catalog(query, type="song", limit=40):
        s.calls.append(("search", query, type, limit))
        if s.raises:
            raise RuntimeError("ytmusic fora do ar")
        return [dict(i) for i in s.search]

    def get_artist_details(artist_id):
        s.calls.append(("artist", artist_id))
        if s.raises:
            raise RuntimeError("ytmusic fora do ar")
        return s.artist

    def get_album_details(browse_id):
        s.calls.append(("album", browse_id))
        if s.raises:
            raise RuntimeError("ytmusic fora do ar")
        return dict(s.album) if s.album else s.album

    for name, fn in [("search_catalog", search_catalog), ("get_artist_details", get_artist_details),
                     ("get_album_details", get_album_details)]:
        monkeypatch.setattr(CatalogProvider, name, staticmethod(fn))
    return s


@pytest.fixture
def lastfm(client, monkeypatch):
    monkeypatch.setattr(LastfmProvider, "get_similar_artists", staticmethod(lambda name, limit=6: []))
    monkeypatch.setattr(LastfmProvider, "get_artist_info", staticmethod(lambda name: {}))


@pytest.fixture
def genre_lookup(client, monkeypatch):
    s = SimpleNamespace(calls=[])

    def get_genre(artist, album_title="", track_title=""):
        s.calls.append((artist, album_title, track_title))
        return "Pop"

    monkeypatch.setattr(MetadataProvider, "get_genre", staticmethod(get_genre))
    return s


@pytest.fixture
def slskd(client, monkeypatch):
    s = SimpleNamespace(searches=[], downloads=[], results=[], status=None, download_response={"status": "queued"})

    async def search_slskd(query):
        s.searches.append(query)
        return {"search_id": "s1"}

    async def get_search_results(search_id):
        return s.results

    async def download_slskd(username, filename, size=None):
        s.downloads.append((username, filename, size))
        return s.download_response

    async def get_transfer_status(filename):
        return s.status

    patch_everywhere(monkeypatch, slskd_client, "search_slskd", search_slskd)
    patch_everywhere(monkeypatch, slskd_client, "get_search_results", get_search_results)
    patch_everywhere(monkeypatch, slskd_client, "download_slskd", download_slskd)
    patch_everywhere(monkeypatch, slskd_client, "get_transfer_status", get_transfer_status)

    real_sleep = asyncio.sleep

    async def fast_sleep(delay, *a, **k):
        await real_sleep(0)

    monkeypatch.setattr(asyncio, "sleep", fast_sleep)
    return s


@pytest.fixture
def bg_download(client, monkeypatch):
    calls = []

    async def fake(url, dest_path, metadata, cover_url=None):
        calls.append((url, dest_path, metadata, cover_url))

    patch_everywhere(monkeypatch, local_library, "download_file_background", fake)
    return calls


def _peers(n=16, filename="\\\\music\\Radiohead - Creep.flac", size=123):
    return [{"username": f"u{i}", "locked": False, "slotsFree": True, "queueLength": 0,
             "uploadSpeed": 1_000_000, "files": [{"filename": filename, "size": size}]} for i in range(n)]


HELLO_T = {"type": "song", "trackName": "Hello", "artistName": "Adele", "collectionName": "25",
           "tidalId": 111, "artworkUrl": "http://img/t.jpg"}
HELLO_YT = {"type": "song", "trackName": "Hello", "artistName": "Adele", "collectionName": "25", "videoId": "vid1"}
SKYFALL_YT = {"type": "song", "trackName": "Skyfall", "artistName": "Adele", "collectionName": "Skyfall", "videoId": "vid2"}


# --------------------------------------------------------------------------
# GET /search/catalog
# --------------------------------------------------------------------------
def test_search_merges_tidal_first_and_enriches_with_videoid(client, tidal, yt):
    tidal.search = [HELLO_T]
    yt.search = [HELLO_YT, SKYFALL_YT]
    r = client.get("/search/catalog", params={"query": "adele", "limit": 20, "offset": 0, "type": "song"})
    assert r.status_code == 200
    body = r.json()
    assert [i["trackName"] for i in body] == ["Hello", "Skyfall"]
    assert body[0]["tidalId"] == 111 and body[0]["videoId"] == "vid1"  # Tidal prioritário, enriquecido
    assert body[1]["videoId"] == "vid2"
    assert all(i["isDownloaded"] is False and i["filename"] is None for i in body)
    # contrato de chamada: Tidal (query, limit+offset+20, type) e YT (query, type, limit+offset+20)
    assert tidal.calls == [("search", "adele", 40, "song")]
    assert yt.calls == [("search", "adele", "song", 40)]


def test_search_survives_one_source_down(client, tidal, yt):
    tidal.search, yt.search = [HELLO_T], [SKYFALL_YT]
    tidal.raises = True
    r = client.get("/search/catalog", params={"query": "adele"})
    assert [i["trackName"] for i in r.json()] == ["Skyfall"]
    tidal.raises, yt.raises = False, True
    r = client.get("/search/catalog", params={"query": "adele"})
    assert [i["trackName"] for i in r.json()] == ["Hello"]
    tidal.raises = True
    assert client.get("/search/catalog", params={"query": "adele"}).json() == []


def test_search_pagination_and_type(client, tidal, yt):
    tidal.search = [HELLO_T]
    yt.search = [SKYFALL_YT]
    r = client.get("/search/catalog", params={"query": "adele", "limit": 1, "offset": 1})
    assert [i["trackName"] for i in r.json()] == ["Skyfall"]
    assert tidal.calls[-1] == ("search", "adele", 22, "song")
    client.get("/search/catalog", params={"query": "adele", "type": "album"})
    assert tidal.calls[-1] == ("search", "adele", 40, "album") and yt.calls[-1] == ("search", "adele", "album", 40)


# --------------------------------------------------------------------------
# GET /catalog/artist/{id} e /catalog/album/{id}: roteia pelo formato do ID
# --------------------------------------------------------------------------
def test_artist_routes_numeric_id_to_tidal(client, tidal, yt, lastfm):
    tidal.artist = {"artist": {"artistName": "Adele"}, "albums": [], "topSongs": []}
    r = client.get("/catalog/artist/12345")
    assert r.status_code == 200 and r.json() == tidal.artist
    assert tidal.calls == [("artist", "12345")] and yt.calls == []


def test_artist_routes_other_id_to_ytmusic(client, tidal, yt, lastfm):
    yt.artist = {"artist": {"artistName": "Adele"}, "albums": []}
    r = client.get("/catalog/artist/UCabc123")
    assert r.status_code == 200 and r.json() == yt.artist
    assert yt.calls == [("artist", "UCabc123")] and tidal.calls == []


def test_artist_not_found_and_provider_error(client, tidal, yt, lastfm):
    assert client.get("/catalog/artist/1").status_code == 404  # provider devolve None
    tidal.raises = True
    r = client.get("/catalog/artist/1")
    assert r.status_code == 500 and "tidal" not in r.text.lower()  # sem vazar a exceção


def test_album_routes_by_id_and_enriches_ytmusic_genre(client, tidal, yt, genre_lookup):
    tidal.album = {"collectionName": "25", "artistName": "Adele", "genre": "Pop"}
    assert client.get("/catalog/album/999").json() == tidal.album
    assert tidal.calls == [("album", "999")] and genre_lookup.calls == []

    yt.album = {"collectionName": "25", "artistName": "Adele"}
    body = client.get("/catalog/album/MPREb_x").json()
    assert body["genre"] == "Pop"
    assert genre_lookup.calls == [("Adele", "25", "")]

    yt.album = {"collectionName": "25", "artistName": "Adele", "genre": "Soul"}
    genre_lookup.calls.clear()
    assert client.get("/catalog/album/MPREb_y").json()["genre"] == "Soul"
    assert genre_lookup.calls == []


def test_album_provider_failure_is_502_and_unknown_album_is_404(client, tidal, yt):
    tidal.raises = True
    r = client.get("/catalog/album/1")
    assert r.status_code == 502 and r.json()["detail"] == "Falha ao consultar o catálogo"
    tidal.raises = False  # provedor ok, mas sem esse álbum
    r = client.get("/catalog/album/1")
    assert r.status_code == 404 and r.json()["detail"] == "Album not found"


# --------------------------------------------------------------------------
# POST /download/smart
# --------------------------------------------------------------------------
def test_smart_download_tidal_direct(client, auth, tidal, slskd, bg_download):
    tidal.download = {"url": "http://cdn/x.flac", "mime": "audio/flac", "codec": "flac"}
    body = {"artist": "Adele", "track": "Hello", "album": "25", "tidalId": 777, "artworkUrl": "http://img/a.jpg"}
    r = client.post("/download/smart", headers=auth, json=body)
    rel = os.path.join("Tidal", "adele", "25", "hello.flac")
    assert r.status_code == 200
    assert r.json() == {"status": "Download started", "file": rel, "source": "Tidal", "tidalId": 777}
    assert tidal.calls == [("download_url", 777)]  # id já veio: não busca de novo
    assert bg_download == [("http://cdn/x.flac", os.path.join(MUSIC_DIR, rel),
                            {"title": "Hello", "artist": "Adele", "album": "25"}, "http://img/a.jpg")]
    assert slskd.searches == []
    from app import models
    from app.database import SessionLocal
    db = SessionLocal()
    try:
        row = db.query(models.DownloadedTrack).filter_by(tidal_id=777).first()
        assert row and row.local_path == rel and row.source == "Tidal"
    finally:
        db.close()


def test_smart_download_without_album_uses_tidal_id_in_filename(client, auth, tidal, slskd, bg_download):
    tidal.download = {"url": "http://cdn/x.m4a", "mime": "audio/mp4"}
    r = client.post("/download/smart", headers=auth, json={"artist": "Adele", "track": "Hello", "tidalId": 778})
    assert r.json()["file"] == os.path.join("Tidal", "adele", "hello_778.m4a")


def test_smart_download_resolves_tidal_id_by_fuzzy_search(client, auth, tidal, slskd, bg_download):
    tidal.search = [{"artistName": "Adele", "trackName": "Hello", "tidalId": 222, "artworkUrl": "http://img/z.jpg",
                     "collectionName": "25"}]
    tidal.download = {"url": "http://cdn/y.flac", "mime": "audio/flac"}
    r = client.post("/download/smart", headers=auth, json={"artist": "Adele", "track": "Hello"})
    assert r.status_code == 200
    # id, capa e álbum vêm do melhor match e entram no restante do fluxo
    assert r.json() == {"status": "Download started", "file": os.path.join("Tidal", "adele", "25", "hello.flac"),
                        "source": "Tidal", "tidalId": 222}
    assert tidal.calls[0] == ("search", "Adele Hello", 5, "song") and tidal.calls[1] == ("download_url", 222)
    assert bg_download[0][3] == "http://img/z.jpg"


def test_smart_download_falls_back_to_soulseek_when_tidal_has_no_url(client, auth, tidal, slskd, bg_download):
    tidal.download = None
    slskd.results = _peers()
    slskd.download_response = {"status": "queued", "id": "abc"}
    r = client.post("/download/smart", headers=auth, json={"artist": "Radiohead", "track": "Creep", "tidalId": 779})
    assert r.status_code == 200 and r.json() == {"status": "queued", "id": "abc"}
    assert slskd.searches == ["Radiohead Creep"]
    assert slskd.downloads == [("u0", "\\\\music\\Radiohead - Creep.flac", 123)]  # empate: o primeiro vence
    assert bg_download == []


def test_smart_download_soulseek_when_tidal_finds_nothing(client, auth, tidal, slskd, bg_download):
    slskd.results = _peers()
    r = client.post("/download/smart", headers=auth, json={"artist": "Radiohead", "track": "Creep"})
    assert r.status_code == 200
    assert tidal.calls == [("search", "Radiohead Creep", 5, "song")]
    assert len(slskd.downloads) == 1


def test_smart_download_soulseek_prefers_free_slot_and_flac(client, auth, tidal, slskd, bg_download):
    busy = {"username": "busy", "locked": False, "slotsFree": False, "queueLength": 5, "uploadSpeed": 9_000_000,
            "files": [{"filename": "Radiohead - Creep.flac", "size": 1}]}
    free_mp3 = {"username": "free_mp3", "locked": False, "slotsFree": True, "queueLength": 0, "uploadSpeed": 1,
                "files": [{"filename": "Radiohead - Creep.mp3", "size": 2}]}
    locked = {"username": "locked", "locked": True, "slotsFree": True, "files": [{"filename": "Radiohead - Creep.flac", "size": 3}]}
    slskd.results = [busy, free_mp3, locked]  # slot livre (+100000) vence FLAC ocupado; bloqueado é ignorado
    client.post("/download/smart", headers=auth, json={"artist": "Radiohead", "track": "Creep"})
    assert slskd.downloads[0][0] == "free_mp3"


def test_smart_download_nothing_found_is_404(client, auth, tidal, slskd, bg_download):
    slskd.results = []
    r = client.post("/download/smart", headers=auth, json={"artist": "Zzzz", "track": "Qqqq"})
    assert r.status_code == 404 and r.json()["detail"] == "Nenhum ficheiro encontrado."
    assert slskd.downloads == []


def test_smart_download_local_cache_short_circuits(client, auth, tidal, slskd, bg_download):
    rel = os.path.join("Tidal", "adele", "cached", "hello.flac")
    full = os.path.join(MUSIC_DIR, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "wb") as f:
        f.write(b"fLaC" + b"\0" * 10)
    local_library.register_download(tidal_id=888, title="Hello", artist="Adele", album="cached",
                                    local_path=rel, source="Tidal")
    r = client.post("/download/smart", headers=auth, json={"artist": "Adele", "track": "Hello", "tidalId": 888})
    assert r.json() == {"status": "Already downloaded", "file": full, "display_name": "Hello"}
    assert tidal.calls == [] and slskd.searches == [] and bg_download == []


# --------------------------------------------------------------------------
# rotas legadas do Soulseek
# --------------------------------------------------------------------------
def test_download_status_uses_slskd_then_not_found(client, auth, slskd):
    slskd.status = {"state": "Downloading", "percent": 42.0}
    assert client.get("/download/status", headers=auth, params={"filename": "nao/existe.flac"}).json() == slskd.status
    slskd.status = None
    assert client.get("/download/status", headers=auth, params={"filename": "nao/existe.flac"}).json() == {
        "state": "NotFound", "progress": 0.0, "speed": 0, "message": "Download não encontrado"}


def test_legacy_soulseek_routes(client, auth, slskd):
    assert client.post("/search/adele", headers=auth).json() == {"search_id": "s1"}
    slskd.results = [{"username": "u"}]
    assert client.get("/results/s1", headers=auth).json() == [{"username": "u"}]
    r = client.post("/download", headers=auth, json={"username": "u", "filename": "a/b.flac", "size": 9})
    assert r.json() == {"status": "queued"} and slskd.downloads == [("u", "a/b.flac", 9)]


# --------------------------------------------------------------------------
# home: fallback de lançamentos usa o catálogo principal (Tidal)
# --------------------------------------------------------------------------
def test_home_new_releases_fallback_uses_tidal(client, auth, tidal):
    tidal.search = [{"collectionName": "25", "artistName": "Adele", "artworkUrl": "http://img/a.jpg", "collectionId": 5}]
    r = client.get("/home/new-releases", headers=auth, params={"limit": 10})
    assert r.status_code == 200
    assert r.json() == [{"title": "25", "artist": "Adele", "imageUrl": "http://img/a.jpg", "type": "album",
                         "id": 5, "vibrantColorHex": "#D4AF37", "tags": ["Popular"]}]
    assert tidal.calls == [("search", "new releases 2024", 10, "album")]


# --------------------------------------------------------------------------
# serviços internos que consultam as fontes
# --------------------------------------------------------------------------
def test_auto_tagging_tidal_then_ytmusic_fallback(client, tidal, yt, monkeypatch):
    target = os.path.join(MUSIC_DIR, "untagged", "Adele_Hello.flac")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as f:
        f.write(b"fLaC")
    embeds = []
    monkeypatch.setattr(AudioManager, "get_audio_tags", staticmethod(lambda p: {}))
    monkeypatch.setattr(AudioManager, "embed_metadata", staticmethod(lambda p, meta, cover: embeds.append((p, meta, cover))))
    yt.search = [{"artistName": "Adele", "trackName": "Hello", "collectionName": "25"}]

    asyncio.run(local_library.process_library_auto_tagging())

    assert ("search", "adele hello", 1, "song") in tidal.calls  # Tidal primeiro
    assert ("search", "adele hello", "song", 1) in yt.calls      # YT só quando o Tidal não acha
    assert (target, {"title": "Hello", "artist": "Adele", "album": "25"}, None) in embeds


def test_auto_tagging_does_not_call_ytmusic_when_tidal_finds(client, tidal, yt, monkeypatch):
    target = os.path.join(MUSIC_DIR, "untagged2", "Adele_Hello.flac")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as f:
        f.write(b"fLaC")
    monkeypatch.setattr(AudioManager, "get_audio_tags", staticmethod(lambda p: {}))
    monkeypatch.setattr(AudioManager, "embed_metadata", staticmethod(lambda p, meta, cover: None))
    tidal.search = [{"artistName": "Adele", "trackName": "Hello", "collectionName": "25"}]
    asyncio.run(local_library.process_library_auto_tagging())
    assert [c for c in yt.calls if c[1] == "adele hello"] == []


def test_genre_cache_fetches_from_ytmusic(client, yt):
    from app.services import genre_cache
    yt.search = [{"artistName": "A", "trackName": "T", "collectionName": "C"}]
    out = asyncio.run(genre_cache.fetch_genre_tracks_from_api("pop", 5))
    assert yt.calls == [("search", genre_cache.GENRE_QUERIES.get("pop", "pop music hits"), "song", 5)]
    assert len(out) == 1


def test_recommender_searches_albums_on_ytmusic(client, yt):
    from app.services.recommendation_service import MusicRecommender
    yt.search = []
    assert asyncio.run(MusicRecommender()._process_artists_list(["Adele"])) == []
    assert yt.calls == [("search", "Adele", "album", 10)]
