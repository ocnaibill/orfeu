"""Autenticação das rotas de mídia: Bearer no header ou token de mídia em ?mt=."""
import pytest

MEDIA_ROUTES = [
    "/stream?filename=Artist/song.flac",
    "/cover?filename=Artist/song.flac",
    "/metadata?filename=Artist/song.flac",
    "/lyrics?filename=Artist/song.flac",
    "/lyrics/plain?filename=Artist/song.flac",
    "/lyrics/synced?filename=Artist/song.flac&artist=A&title=T",
]


@pytest.fixture(scope="module")
def media_token(client, auth):
    r = client.get("/auth/media-token", headers=auth)
    assert r.status_code == 200, r.text
    assert r.json()["expires_in"] > 0
    return r.json()["token"]


@pytest.mark.parametrize("path", MEDIA_ROUTES)
def test_media_routes_require_auth(client, music_file, path):
    assert client.get(path).status_code == 401


def test_stream_with_bearer_header(client, auth, music_file):
    r = client.get("/stream", params={"filename": "Artist/song.flac"}, headers=auth)
    assert r.status_code == 200 and r.content.startswith(b"fLaC")


def test_stream_with_media_token_in_query(client, media_token, music_file):
    r = client.get("/stream", params={"filename": "Artist/song.flac", "mt": media_token})
    assert r.status_code == 200 and r.content.startswith(b"fLaC")
    r = client.get("/stream", params={"filename": "Artist/song.flac", "mt": media_token}, headers={"range": "bytes=0-3"})
    assert r.status_code == 206 and r.content == b"fLaC"


def test_full_access_token_is_rejected_in_query(client, auth, music_file):
    """Nunca aceitar a credencial da conta em URL (vai para log/histórico)."""
    full = auth["Authorization"].split(" ", 1)[1]
    r = client.get("/stream", params={"filename": "Artist/song.flac", "mt": full})
    assert r.status_code == 401


def test_media_token_does_not_work_as_account_token(client, media_token):
    bearer = {"Authorization": f"Bearer {media_token}"}
    assert client.get("/users/me", headers=bearer).status_code == 401
    assert client.get("/library", headers=bearer).status_code == 401
    assert client.get("/auth/media-token", headers=bearer).status_code == 401  # não renova a si mesmo


def test_garbage_tokens_are_rejected(client, music_file):
    assert client.get("/stream", params={"filename": "Artist/song.flac", "mt": "lixo"}).status_code == 401
    r = client.get("/stream", params={"filename": "Artist/song.flac"}, headers={"Authorization": "Bearer lixo"})
    assert r.status_code == 401


def test_media_token_requires_login(client):
    assert client.get("/auth/media-token").status_code == 401


def test_cover_short_stays_public_and_does_not_redirect_to_protected_route(client, auth, music_file, monkeypatch):
    """O Discord busca a capa sem credencial: a rota curta serve a imagem em vez de redirecionar."""
    from app.services import cover_proxy
    from app.services.lyrics_provider import LyricsProvider

    async def no_online_cover(path):
        return None

    monkeypatch.setattr(LyricsProvider, "get_online_cover", staticmethod(no_online_cover))
    url = cover_proxy.get_short_cover_url("Artist/song.flac")
    r = client.get("/cover/short/" + url.rsplit("/", 1)[1], follow_redirects=False)
    # Serve direto (200 ou 404 da própria lógica de capa): nunca 401 nem redirect para /cover.
    assert r.status_code in (200, 404)
    assert "location" not in r.headers


def test_analytics_cover_urls_are_the_public_short_ones(client, auth):
    """Respostas que a UI mostra como imagem não podem apontar para /cover (exige login)."""
    from app import models
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(username="bia").first()
        track = db.query(models.Track).filter_by(filename="Artist/song.flac").first()
        if track is None:
            track = models.Track(filename="Artist/song.flac", title="Song", artist="Artist", album="Album",
                                 duration=10.0)
            db.add(track)
        track.album_id = "alb1"
        db.commit()
        db.add(models.ListenHistory(user_id=user.id, track_id=track.id, duration_listened=10.0))
        db.commit()
    finally:
        db.close()

    top = client.get("/users/me/analytics/top-tracks", headers=auth).json()
    assert top and "/cover/short/" in top[0]["coverProxyUrl"]

    recent = client.get("/home/continue-listening", headers=auth).json()
    assert recent and all("/cover?" not in item["imageUrl"] for item in recent)
    assert all("/cover/short/" in item["imageUrl"] for item in recent)


# --- chave de transição: MEDIA_AUTH_REQUIRED ---------------------------------------
def test_media_auth_can_be_relaxed_for_old_clients_during_rollout(client, music_file, monkeypatch):
    monkeypatch.setenv("MEDIA_AUTH_REQUIRED", "false")
    assert client.get("/stream", params={"filename": "Artist/song.flac"}).status_code == 200
    assert client.get("/metadata", params={"filename": "Artist/song.flac"}).status_code in (200, 404)
    # mesmo relaxada, credencial inválida continua sendo recusada
    r = client.get("/stream", params={"filename": "Artist/song.flac", "mt": "lixo"})
    assert r.status_code == 401
    r = client.get("/stream", params={"filename": "Artist/song.flac"}, headers={"Authorization": "Bearer lixo"})
    assert r.status_code == 401
    # e a chave não afeta as rotas que nunca foram de mídia
    assert client.get("/library").status_code == 401
    assert client.get("/users/me").status_code == 401


def test_media_auth_is_required_by_default_and_for_any_other_value(client, music_file, monkeypatch):
    monkeypatch.delenv("MEDIA_AUTH_REQUIRED", raising=False)
    assert client.get("/stream", params={"filename": "Artist/song.flac"}).status_code == 401
    for value in ("true", "1", "yes", "", "talvez"):
        monkeypatch.setenv("MEDIA_AUTH_REQUIRED", value)
        assert client.get("/stream", params={"filename": "Artist/song.flac"}).status_code == 401, value
