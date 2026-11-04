"""Casamento de nomes de arquivo do Soulseek: a extensão não deve contar na similaridade."""
from test_sources_behavior import _peers, bg_download, slskd, tidal  # noqa: F401  (fixtures)


def _download(client, auth, slskd, results):
    slskd.results = results
    r = client.post("/download/smart", headers=auth, json={"artist": "Adele", "track": "Hello"})
    return r


def test_short_title_flac_is_accepted(client, auth, tidal, slskd, bg_download):
    # Antes: "adele hello" x "adele - hello.flac" = 74 (< 75) e o FLAC era descartado.
    r = _download(client, auth, slskd, _peers(16, "Adele - Hello.flac", 111))
    assert r.status_code == 200
    assert slskd.downloads == [("u0", "Adele - Hello.flac", 111)]


def test_flac_wins_over_mp3_once_both_match(client, auth, tidal, slskd, bg_download):
    mp3 = {"username": "mp3", "locked": False, "slotsFree": True, "queueLength": 0, "uploadSpeed": 0,
           "files": [{"filename": "Adele - Hello.mp3", "size": 1}]}
    flac = {"username": "flac", "locked": False, "slotsFree": True, "queueLength": 0, "uploadSpeed": 0,
            "files": [{"filename": "Adele - Hello.flac", "size": 2}]}
    _download(client, auth, slskd, [mp3, flac])
    assert slskd.downloads[0][0] == "flac"  # FLAC +5000 contra MP3 +1000, com o mesmo slot


def test_unrelated_file_is_still_rejected(client, auth, tidal, slskd, bg_download):
    r = _download(client, auth, slskd, _peers(16, "Metallica - One.flac", 5))
    assert r.status_code == 404 and slskd.downloads == []
