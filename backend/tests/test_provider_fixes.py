"""Correções de provedores e de respostas de erro (álbum, cor, status, histórico, Last.fm)."""
import os
import subprocess
import sys
from types import SimpleNamespace

import pytest

from app.services import tidal_provider
from app.services.catalog_provider import CatalogProvider
from app.services.metadata_provider import MetadataProvider
from app.services.tidal_provider import TidalProvider
from conftest import MUSIC_DIR


# --- Tidal: detalhes do álbum ----------------------------------------------
class FakeHttpxClient:
    """Substitui httpx.Client dentro do tidal_provider."""
    response = SimpleNamespace(status_code=200, json=lambda: {})

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def get(self, url, **kwargs):
        return type(self).response


@pytest.fixture
def tidal_http(monkeypatch):
    monkeypatch.setattr(tidal_provider.httpx, "Client", FakeHttpxClient)
    monkeypatch.setattr(MetadataProvider, "get_genre", staticmethod(lambda *a, **k: "Pop"))

    def respond(status, payload=None):
        FakeHttpxClient.response = SimpleNamespace(status_code=status, json=lambda: payload or {})
    return respond


def _track(idx, duration):
    return {"item": {"id": 100 + idx, "title": f"Faixa {idx}", "trackNumber": idx, "duration": duration,
                     "artist": {"name": "Adele"}, "audioQuality": "LOSSLESS",
                     "album": {"title": "25", "cover": "aa-bb", "releaseDate": "2015-11-20"}}}


def test_tidal_album_provider_failure_is_not_an_empty_album(tidal_http):
    tidal_http(503)
    with pytest.raises(RuntimeError, match="503"):
        TidalProvider.get_album_details("1")


def test_tidal_album_not_found_returns_none(tidal_http):
    tidal_http(404)
    assert TidalProvider.get_album_details("1") is None
    tidal_http(200, {"data": {"items": []}})  # 200 vazio também é "não existe"
    assert TidalProvider.get_album_details("1") is None


def test_tidal_album_tolerates_null_duration(tidal_http):
    tidal_http(200, {"data": {"items": [_track(1, None), _track(2, 200)]}})
    album = TidalProvider.get_album_details("9")
    assert album["collectionName"] == "25" and len(album["tracks"]) == 2
    assert [t["durationMs"] for t in album["tracks"]] == [0, 200000]


# --- YT Music: faixas do álbum com videoId ------------------------------------
def test_ytmusic_album_tracks_carry_video_id(monkeypatch):
    fake = SimpleNamespace(get_album=lambda browse_id: {
        "title": "25", "year": "2015", "thumbnails": [{"url": "http://img/x=w60-h60"}],
        "artists": [{"name": "Adele"}],
        "tracks": [{"title": "Hello", "videoId": "vid1", "duration_seconds": 295, "artists": [{"name": "Adele"}]},
                   {"title": "Sem id", "duration_seconds": 10, "artists": None}]})
    monkeypatch.setattr(CatalogProvider, "yt", fake)
    tracks = CatalogProvider.get_album_details("MPREb_x")["tracks"]
    assert [t["videoId"] for t in tracks] == ["vid1", None]


# --- cor dos cards estável entre reinícios ---------------------------------------
def test_card_color_is_stable_across_processes():
    code = ("from app.services.recommendation_service import MusicRecommender;"
            "print(MusicRecommender()._format_item({'artistName':'Adele','collectionName':'25','artworkUrl':'u','collectionId':'1'})['vibrantColorHex'])")
    backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    colors = set()
    for seed in ("1", "2", "3"):
        env = {**os.environ, "PYTHONHASHSEED": seed, "PYTHONDONTWRITEBYTECODE": "1"}
        out = subprocess.run([sys.executable, "-c", code], cwd=backend, env=env,
                             capture_output=True, text=True, check=True).stdout.strip().splitlines()[-1]
        colors.add(out)
    assert len(colors) == 1, f"a cor mudou entre processos: {colors}"


# --- /download/status --------------------------------------------------------------
def _status(client, auth, filename):
    return client.get("/download/status", headers=auth, params={"filename": filename}).json()


def test_status_short_tidal_file_is_completed(client, auth):
    """Antes: faixa do Tidal <= 1 MB nunca ficava 'Completed'."""
    rel = os.path.join("Tidal", "someone", "skit.flac")
    full = os.path.join(MUSIC_DIR, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "wb") as f:
        f.write(b"fLaC" + b"\0" * 100)  # ~100 bytes
    s = _status(client, auth, rel)
    assert s["state"] == "Completed" and s["progress"] == 100.0 and s["message"] == "Tidal Download"


def test_status_tidal_download_in_progress(client, auth):
    rel = os.path.join("Tidal", "someone", "ongoing.flac")
    tmp = os.path.join(MUSIC_DIR, rel + ".tmp")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    with open(tmp, "wb") as f:
        f.write(b"x" * 2048)
    s = _status(client, auth, rel)
    assert s["state"] == "Downloading" and s["bytes_transferred"] == 2048


def test_status_registered_but_not_started_vs_unknown(client, auth):
    from app.services import local_library
    rel = os.path.join("Tidal", "someone", "queued.flac")
    local_library.register_download(tidal_id=909090, title="Queued", artist="Someone", album="X",
                                    local_path=rel, source="Tidal")
    assert _status(client, auth, rel)["message"] == "Iniciando"
    assert _status(client, auth, "never/requested.flac")["state"] == "NotFound"


def test_status_does_not_escape_the_music_dir(client, auth):
    assert _status(client, auth, "../../etc/passwd")["state"] == "NotFound"


# --- histórico e Last.fm: erro de verdade em vez de 200 ----------------------------
def test_history_failure_is_a_real_error(client, auth, monkeypatch):
    from app.routers import history
    monkeypatch.setattr(history.AudioManager, "get_audio_tags",
                        staticmethod(lambda p: (_ for _ in ()).throw(RuntimeError("arquivo ilegível"))))
    r = client.post("/users/me/history", headers=auth,
                    json={"filename": "Artist/never-seen-before.flac", "duration_listened": 10.0})
    assert r.status_code == 404 and r.json()["detail"] == "Track não encontrada"


def _connect_lastfm(client, auth):
    from app import models
    from app.database import SessionLocal
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(username="bia").first()
        user.lastfm_session_key, user.lastfm_username = "sk", "bia_fm"
        db.commit()
    finally:
        db.close()


def test_lastfm_not_connected_is_skipped_but_failure_is_502(client, auth, monkeypatch):
    from app import models
    from app.database import SessionLocal
    from app.services.lastfm_provider import LastfmProvider
    body = {"artist": "Adele", "track": "Hello", "album": "25", "duration": 295}

    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(username="bia").first()
        user.lastfm_session_key = None
        db.commit()
    finally:
        db.close()
    assert client.post("/lastfm/scrobble", headers=auth, json=body).json()["status"] == "skipped"

    _connect_lastfm(client, auth)
    monkeypatch.setattr(LastfmProvider, "scrobble_track", staticmethod(lambda *a, **k: False))
    monkeypatch.setattr(LastfmProvider, "update_now_playing", staticmethod(lambda *a, **k: False))
    assert client.post("/lastfm/scrobble", headers=auth, json=body).status_code == 502
    assert client.post("/lastfm/now-playing", headers=auth, json=body).status_code == 502

    monkeypatch.setattr(LastfmProvider, "scrobble_track", staticmethod(lambda *a, **k: True))
    monkeypatch.setattr(LastfmProvider, "update_now_playing", staticmethod(lambda *a, **k: True))
    assert client.post("/lastfm/scrobble", headers=auth, json=body).json()["status"] == "scrobbled"
    assert client.post("/lastfm/now-playing", headers=auth, json=body).json() == {"status": "updated"}
