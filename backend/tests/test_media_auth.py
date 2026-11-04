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
