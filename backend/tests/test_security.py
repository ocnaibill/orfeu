import pytest

ADMIN_ROUTES = [
    ("get", "/library"),
    ("post", "/library/scan"),
    ("post", "/library/organize"),
    ("get", "/library/legacy"),
    ("post", "/genres/refresh-cache"),
    ("get", "/lyrics/providers/test"),
    ("post", "/lyrics/providers/musixmatch/reset"),
    ("post", "/download/smart"),
    ("post", "/download"),
    ("post", "/download/auto"),
    ("get", "/download/status?filename=x"),
    ("post", "/search/abc"),
    ("get", "/results/abc"),
    ("get", "/analytics/rankings"),
    ("get", "/users/me"),
]


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_requires_login(client, method, path):
    assert getattr(client, method)(path).status_code == 401


@pytest.mark.parametrize("evil", ["../secret.txt", "Artist/../../secret.txt", "/etc/passwd", ".."])
def test_stream_path_traversal_blocked(client, music_file, evil):
    r = client.get("/stream", params={"filename": evil})
    assert r.status_code == 404
    assert b"TOP SECRET" not in r.content


def test_downloads_path_traversal_blocked(client):
    assert client.get("/downloads/../../etc/passwd").status_code == 404


def test_register_closed_by_default(client, monkeypatch):
    monkeypatch.setenv("ALLOW_REGISTRATION", "false")
    r = client.post("/auth/register", json={"username": "eve", "email": "e@e.com", "full_name": "E", "password": "x"})
    assert r.status_code == 403
