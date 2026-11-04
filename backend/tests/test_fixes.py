import base64


# --- troca de senha -------------------------------------------------------
def test_change_password(client, auth):
    r = client.put("/users/me", headers=auth, json={"current_password": "errada", "new_password": "nova-senha-456"})
    assert r.status_code == 400  # senha atual incorreta

    r = client.put("/users/me", headers=auth, json={"new_password": "nova-senha-456"})
    assert r.status_code == 400  # falta a senha atual

    r = client.put("/users/me", headers=auth, json={"current_password": "senha-antiga-123", "new_password": "nova-senha-456"})
    assert r.status_code == 200, r.text

    assert client.post("/token", data={"username": "bia", "password": "senha-antiga-123"}).status_code == 401
    assert client.post("/token", data={"username": "bia", "password": "nova-senha-456"}).status_code == 200


# --- upload de imagem ----------------------------------------------------
def test_profile_image_too_large_is_400(client, auth):
    big = base64.b64encode(b"\0" * (10 * 1024 * 1024 + 1)).decode()
    r = client.post("/users/me/profile-image", headers=auth, json={"image_data": big, "content_type": "image/png"})
    assert r.status_code == 400
    assert "grande" in r.json()["detail"]


# --- endpoints legados / públicos ---------------------------------------
def test_download_auto_is_explicit_501(client, auth):
    r = client.post("/download/auto", headers=auth, json={"search_id": "abc"})
    assert r.status_code == 501


def test_rankings_ok_with_token(client, auth):
    assert client.get("/analytics/rankings", headers=auth).status_code == 200


# --- /stream: Range ------------------------------------------------------
def _stream(client, auth, rng=None):
    headers = {**auth, **({"range": rng} if rng else {})}
    return client.get("/stream", params={"filename": "Artist/song.flac"}, headers=headers)


def test_stream_full_and_content_type(client, auth, music_file):
    r = _stream(client, auth)
    assert r.status_code == 200 and r.headers["content-type"] == "audio/flac"
    assert r.headers["accept-ranges"] == "bytes" and len(r.content) == 104


def test_stream_range_start_end(client, auth, music_file):
    r = _stream(client, auth, "bytes=0-3")
    assert r.status_code == 206 and r.content == b"fLaC"
    assert r.headers["content-range"] == "bytes 0-3/104"


def test_stream_range_open_ended(client, auth, music_file):
    r = _stream(client, auth, "bytes=100-")
    assert r.status_code == 206 and len(r.content) == 4
    assert r.headers["content-range"] == "bytes 100-103/104"


def test_stream_range_suffix(client, auth, music_file):
    r = _stream(client, auth, "bytes=-4")
    assert r.status_code == 206 and r.content == b"fLaC"[:0] + bytes(range(100))[-4:]
    assert r.headers["content-range"] == "bytes 100-103/104"


def test_stream_range_end_is_clamped(client, auth, music_file):
    r = _stream(client, auth, "bytes=100-9999")
    assert r.status_code == 206 and r.headers["content-range"] == "bytes 100-103/104"


def test_stream_range_unsatisfiable(client, auth, music_file):
    r = _stream(client, auth, "bytes=500-")
    assert r.status_code == 416 and r.headers["content-range"] == "bytes */104"


def test_stream_range_malformed_serves_full_file(client, auth, music_file):
    for bad in ["bytes=abc", "bytes", "items=0-3", "bytes=0-1,5-6", "bytes=5-2", "bytes=-0"]:
        r = _stream(client, auth, bad)
        assert r.status_code == 200 and len(r.content) == 104, bad


# --- sync da biblioteca: sessão própria ---------------------------------
def test_sync_files_to_db_uses_its_own_session(client, music_file, auth, monkeypatch):
    from app import models
    from app.database import SessionLocal
    from app.services import local_library

    monkeypatch.setattr(local_library, "fetch_and_assign_genre", lambda *a, **k: "Rock")
    monkeypatch.setattr(local_library.AudioManager, "get_audio_tags",
                        staticmethod(lambda p: {"title": "Song", "artist": "Artist", "album": "Album", "genre": None}), raising=False)
    monkeypatch.setattr(local_library.AudioManager, "get_audio_metadata",
                        staticmethod(lambda p: {"duration": 10, "format": "FLAC", "bitrate": 900}), raising=False)

    # /library/scan agora não recebe a sessão da request; a task abre a própria.
    r = client.post("/library/scan", headers=auth)
    assert r.status_code == 200

    db = SessionLocal()
    try:
        track = db.query(models.Track).filter(models.Track.filename == "Artist/song.flac").first()
        assert track is not None and track.genre == "Rock"
    finally:
        db.close()
