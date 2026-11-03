"""Fixtures dos testes. O ambiente precisa ser definido ANTES de importar o app."""
import os
import tempfile

_tmp = tempfile.mkdtemp(prefix="orfeu-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["SECRET_KEY"] = "t" * 64
os.environ["ALLOW_REGISTRATION"] = "true"
os.environ["MUSIC_DIR"] = f"{_tmp}/downloads"
os.environ["PUBLIC_DIR"] = f"{_tmp}/downloads_public"
os.makedirs(os.environ["MUSIC_DIR"] + "/Artist", exist_ok=True)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

TMP = _tmp
MUSIC_DIR = os.environ["MUSIC_DIR"]


@pytest.fixture(scope="session")
def client():
    from app.main import app
    # Sem `with`: não dispara o lifespan (scheduler de gêneros chama a rede).
    return TestClient(app)


@pytest.fixture(scope="session")
def music_file():
    path = f"{MUSIC_DIR}/Artist/song.flac"
    with open(path, "wb") as f:
        f.write(b"fLaC" + bytes(range(100)))
    with open(f"{TMP}/secret.txt", "w") as f:
        f.write("TOP SECRET")
    return path


@pytest.fixture(scope="session")
def auth(client):
    r = client.post("/auth/register", json={
        "username": "bia", "email": "bia@example.com", "full_name": "Bia", "password": "senha-antiga-123",
    })
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}
