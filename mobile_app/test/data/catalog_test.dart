import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';
import 'package:orfeu/data/catalog/catalog_models.dart';
import 'package:orfeu/data/catalog/catalog_repository.dart';
import 'package:orfeu/data/models/json.dart';

import 'fake_adapter.dart';

// Fixtures montadas a partir do que TidalProvider / CatalogProvider devolvem.

const tidalSong = {
  'type': 'song',
  'trackName': 'Karma Police',
  'artistName': 'Radiohead',
  'collectionName': 'OK Computer',
  'collectionId': '1234',
  'artworkUrl': 'https://resources.tidal.com/images/ab/cd/640x640.jpg',
  'previewUrl': null,
  'year': '1997',
  'releaseDate': '1997-05-21T00:00:00.000+0000',
  'isLossless': true,
  'source': 'Tidal',
  'tidalId': 5678,
  'duration': 264,
  'durationMs': 264000,
  'videoId': 'YTvid123',
  'isDownloaded': true,
  'filename': 'Radiohead/OK Computer/Karma Police.flac',
  'genre': 'Alternative',
};

const ytSongMinimal = {
  'type': 'song',
  'trackName': 'Creep',
  'artistName': 'Radiohead',
  'collectionName': 'Single',
  'artworkUrl': '',
  'previewUrl': null,
  'year': '',
  'videoId': 'abc123',
  'duration': '3:56',
  'durationMs': 236000,
  'source': 'YTMusic',
  'isDownloaded': false,
  'filename': null,
};

const tidalAlbum = {
  'type': 'album',
  'collectionId': '9876',
  'collectionName': 'Kid A',
  'artistName': 'Radiohead',
  'artworkUrl': 'https://resources.tidal.com/images/ef/gh/640x640.jpg',
  'year': '2000',
  'trackCount': 10,
  'source': 'Tidal',
  'isDownloaded': false,
  'filename': null,
};

const ytAlbum = {
  'type': 'album',
  'collectionId': 'MPREb_AbC123',
  'collectionName': 'Amnesiac',
  'artistName': 'Radiohead',
  'artworkUrl': 'https://lh3.googleusercontent.com/x=w800-h800',
  'year': '2001',
  'releaseDate': '2001',
  'trackCount': 0,
  'source': 'YTMusic',
};

const tidalArtist = {
  'type': 'artist',
  'artistName': 'Radiohead',
  'artistId': '3840',
  'artworkUrl': 'https://resources.tidal.com/images/ij/kl/750x750.jpg',
  'popularity': 82,
  'source': 'Tidal',
  'isDownloaded': false,
  'filename': null,
};

const ytArtist = {
  'type': 'artist',
  'artistName': 'Thom Yorke',
  'artistId': 'UCabcdef',
  'artworkUrl': 'https://lh3.googleusercontent.com/y=w800-h800',
  'source': 'YTMusic',
};

// Detalhes de artista Tidal já enriquecidos pelo Last.fm (routers/catalog.py).
const artistDetailsJson = {
  'artist': {
    'artistId': '3840',
    'artistName': 'Radiohead',
    'artworkUrl': 'https://resources.tidal.com/images/ij/kl/750x750.jpg',
    'bio': 'Radiohead are an English band. <a href="https://www.last.fm/music/Radiohead">Read more on Last.fm</a>',
    'popularity': 82,
    'tags': ['alternative', 'rock'],
    'listeners': 5000000,
    'playcount': 300000000,
  },
  'albums': [
    {
      'type': 'album',
      'collectionId': '9876',
      'collectionName': 'Kid A',
      'artistName': 'Radiohead',
      'artistId': '3840',
      'artworkUrl': 'https://resources.tidal.com/images/ef/gh/640x640.jpg',
      'year': '2000',
      'releaseDate': '2000-10-02',
      'trackCount': 10,
      'source': 'Tidal',
    },
  ],
  'singles': [
    {
      'type': 'single',
      'collectionId': '555',
      'collectionName': 'Creep',
      'artistName': 'Radiohead',
      'artistId': '3840',
      'artworkUrl': '',
      'year': '1992',
      'releaseDate': '1992-09-21',
      'trackCount': 2,
      'source': 'Tidal',
    },
  ],
  'topTracks': [
    {
      'type': 'song',
      'trackName': 'Karma Police',
      'artistName': 'Radiohead',
      'collectionName': 'OK Computer',
      'artworkUrl': 'https://resources.tidal.com/images/ab/cd/640x640.jpg',
      'tidalId': 5678,
      'isLossless': true,
      'durationMs': 264000,
      'source': 'Tidal',
    },
  ],
  'similarArtists': [
    {'name': 'Thom Yorke', 'image': 'https://img/thom.jpg', 'match': 0.87, 'artistId': null, 'source': 'LastFM'},
    {'artistId': '77', 'name': 'Muse', 'image': ''},
  ],
};

// Álbum Tidal: faixas com tidalId; gênero vem do MetadataProvider.
const albumDetailsJson = {
  'collectionId': '9876',
  'collectionName': 'Kid A',
  'artistName': 'Radiohead',
  'artworkUrl': 'https://resources.tidal.com/images/ef/gh/640x640.jpg',
  'year': '2000',
  'genre': 'Alternative',
  'tracks': [
    {
      'trackNumber': 1,
      'trackName': 'Everything in Its Right Place',
      'artistName': 'Radiohead',
      'collectionName': 'Kid A',
      'durationMs': 251000,
      'previewUrl': null,
      'artworkUrl': 'https://resources.tidal.com/images/ef/gh/640x640.jpg',
      'tidalId': 111,
      'isLossless': true,
    },
    {
      'trackNumber': 2,
      'trackName': 'Kid A',
      'artistName': 'Radiohead',
      'collectionName': 'Kid A',
      'durationMs': 284000,
      'previewUrl': null,
      'artworkUrl': '',
      'tidalId': 112,
      'isLossless': false,
    },
  ],
};

void main() {
  group('CatalogSong.fromJson', () {
    test('fixture completo (Tidal + arquivo local)', () {
      final s = CatalogSong.fromJson(tidalSong);
      expect(s.trackName, 'Karma Police');
      expect(s.artistName, 'Radiohead');
      expect(s.collectionName, 'OK Computer');
      expect(s.collectionId, '1234');
      expect(s.artworkUrl, startsWith('https://resources.tidal.com'));
      expect(s.tidalId, 5678);
      expect(s.videoId, 'YTvid123');
      expect(s.durationMs, 264000);
      expect(s.duration, const Duration(minutes: 4, seconds: 24));
      expect(s.year, '1997');
      expect(s.releaseDate, startsWith('1997-05-21'));
      expect(s.isLossless, isTrue);
      expect(s.source, 'Tidal');
      expect(s.isDownloaded, isTrue);
      expect(s.filename, 'Radiohead/OK Computer/Karma Police.flac');
      expect(s.genre, 'Alternative');
      expect(s.trackNumber, isNull);
    });

    test('fixture mínimo (YT Music): vazios viram null, sem tidalId', () {
      final s = CatalogSong.fromJson(ytSongMinimal);
      expect(s.trackName, 'Creep');
      expect(s.videoId, 'abc123');
      expect(s.tidalId, isNull);
      expect(s.artworkUrl, isNull);
      expect(s.year, isNull);
      expect(s.durationMs, 236000);
      expect(s.isLossless, isFalse);
      expect(s.isDownloaded, isFalse);
      expect(s.filename, isNull);
      expect(s.genre, isNull);
    });

    test('campos ausentes ou de tipo estranho não lançam', () {
      final empty = CatalogSong.fromJson(const {});
      expect(empty.trackName, '');
      expect(empty.artistName, '');
      expect(empty.durationMs, isNull);
      expect(empty.duration, isNull);

      final odd = CatalogSong.fromJson(const {
        'trackName': 42,
        'artistName': null,
        'tidalId': '5678',
        'collectionId': 1234,
        'durationMs': '1000',
        'isLossless': 'true',
        'isDownloaded': 1,
        'trackNumber': '3',
        'genre': ['x'],
      });
      expect(odd.trackName, '42');
      expect(odd.artistName, '');
      expect(odd.tidalId, 5678);
      expect(odd.collectionId, '1234');
      expect(odd.durationMs, 1000);
      expect(odd.isLossless, isTrue);
      expect(odd.isDownloaded, isTrue);
      expect(odd.trackNumber, 3);
      expect(odd.genre, "[x]");
    });
  });

  group('CatalogAlbum.fromJson', () {
    test('completo (Tidal)', () {
      final a = CatalogAlbum.fromJson(tidalAlbum);
      expect(a.collectionId, '9876');
      expect(a.collectionName, 'Kid A');
      expect(a.artistName, 'Radiohead');
      expect(a.year, '2000');
      expect(a.trackCount, 10);
      expect(a.source, 'Tidal');
      expect(a.isSingle, isFalse);
      expect(a.artistId, isNull);
    });

    test('YT Music: id alfanumérico, trackCount 0', () {
      final a = CatalogAlbum.fromJson(ytAlbum);
      expect(a.collectionId, 'MPREb_AbC123');
      expect(a.releaseDate, '2001');
      expect(a.trackCount, 0);
    });

    test('single da discografia', () {
      final a = CatalogAlbum.fromJson(maps(artistDetailsJson['singles']).first);
      expect(a.isSingle, isTrue);
      expect(a.artistId, '3840');
      expect(a.artworkUrl, isNull);
      expect(a.trackCount, 2);
    });

    test('mínimo e tipos estranhos', () {
      final a = CatalogAlbum.fromJson(const {'collectionId': 99, 'trackCount': '12', 'year': 2001});
      expect(a.collectionId, '99');
      expect(a.collectionName, '');
      expect(a.trackCount, 12);
      expect(a.year, '2001');
      final b = CatalogAlbum.fromJson(const {});
      expect(b.collectionId, '');
      expect(b.trackCount, isNull);
    });
  });

  group('CatalogArtist.fromJson', () {
    test('Tidal completo', () {
      final a = CatalogArtist.fromJson(tidalArtist);
      expect(a.artistId, '3840');
      expect(a.artistName, 'Radiohead');
      expect(a.popularity, 82);
      expect(a.source, 'Tidal');
      expect(a.tags, isEmpty);
      expect(a.bio, isNull);
    });

    test('YT Music mínimo', () {
      final a = CatalogArtist.fromJson(ytArtist);
      expect(a.artistId, 'UCabcdef');
      expect(a.popularity, isNull);
    });

    test('enriquecido pelo Last.fm e bio sem HTML', () {
      final a = CatalogArtist.fromJson(asJson(artistDetailsJson['artist']));
      expect(a.tags, ['alternative', 'rock']);
      expect(a.listeners, 5000000);
      expect(a.playcount, 300000000);
      expect(a.bio, contains('<a href'));
      expect(a.plainBio, 'Radiohead are an English band. Read more on Last.fm');
    });

    test('odd: id numérico, name no lugar de artistName, listeners em texto', () {
      final a = CatalogArtist.fromJson(const {
        'artistId': 3840,
        'name': 'Fallback',
        'listeners': '12',
        'tags': 'não é lista',
        'bio': '',
      });
      expect(a.artistId, '3840');
      expect(a.artistName, 'Fallback');
      expect(a.listeners, 12);
      expect(a.tags, isEmpty);
      expect(a.bio, isNull);
      expect(a.plainBio, isNull);
      expect(CatalogArtist.fromJson(const {'bio': '<p></p>'}).plainBio, isNull);
    });
  });

  group('SearchItem.tryParse', () {
    test('escolhe a classe pelo type', () {
      expect(SearchItem.tryParse(tidalSong), isA<CatalogSong>());
      expect(SearchItem.tryParse(tidalAlbum), isA<CatalogAlbum>());
      expect(SearchItem.tryParse(const {'type': 'single', 'collectionId': '1'}),
          isA<CatalogAlbum>().having((a) => a.isSingle, 'isSingle', true));
      expect(SearchItem.tryParse(tidalArtist), isA<CatalogArtist>());
    });

    test('sem type deduz pelas chaves; type desconhecido ou nada reconhecível dá null', () {
      expect(SearchItem.tryParse(const {'trackName': 'x'}), isA<CatalogSong>());
      expect(SearchItem.tryParse(const {'collectionId': '1'}), isA<CatalogAlbum>());
      expect(SearchItem.tryParse(const {'artistId': '1'}), isA<CatalogArtist>());
      expect(SearchItem.tryParse(const {'type': 'playlist', 'trackName': 'x'}), isNull);
      expect(SearchItem.tryParse(const {}), isNull);
    });

    test('permite switch exaustivo', () {
      String kind(SearchItem i) => switch (i) {
            CatalogSong() => 'song',
            CatalogAlbum() => 'album',
            CatalogArtist() => 'artist',
          };
      expect(kind(SearchItem.tryParse(tidalSong)!), 'song');
      expect(kind(SearchItem.tryParse(ytAlbum)!), 'album');
      expect(kind(SearchItem.tryParse(ytArtist)!), 'artist');
    });
  });

  group('SimilarArtist.fromJson', () {
    test('Last.fm: com match, sem id', () {
      final s = SimilarArtist.fromJson(
          maps(artistDetailsJson['similarArtists']).first);
      expect(s.name, 'Thom Yorke');
      expect(s.match, 0.87);
      expect(s.artistId, isNull);
      expect(s.source, 'LastFM');
      expect(s.image, 'https://img/thom.jpg');
    });

    test('Tidal: com id, sem match; match inteiro vira double', () {
      final s = SimilarArtist.fromJson(
          maps(artistDetailsJson['similarArtists']).last);
      expect(s.artistId, '77');
      expect(s.image, isNull);
      expect(s.match, isNull);
      expect(SimilarArtist.fromJson(const {'name': 'x', 'match': 1}).match, 1.0);
      expect(SimilarArtist.fromJson(const {}).name, '');
    });
  });

  group('ArtistDetails.fromJson', () {
    test('completo', () {
      final d = ArtistDetails.fromJson(artistDetailsJson);
      expect(d.artist.artistName, 'Radiohead');
      expect(d.albums.single.collectionName, 'Kid A');
      expect(d.singles.single.isSingle, isTrue);
      expect(d.topTracks.single.tidalId, 5678);
      expect(d.similarArtists.map((s) => s.name), ['Thom Yorke', 'Muse']);
    });

    test('mínimo (YT Music sem similares)', () {
      final d = ArtistDetails.fromJson(const {
        'artist': {'artistId': 'UCabcdef', 'artistName': 'Thom Yorke', 'source': 'YTMusic'},
        'albums': [],
        'singles': [],
        'topTracks': [
          {'type': 'song', 'trackName': 'Black Swan', 'artistName': 'Thom Yorke', 'videoId': 'v1'},
        ],
      });
      expect(d.artist.artistId, 'UCabcdef');
      expect(d.albums, isEmpty);
      expect(d.similarArtists, isEmpty);
      expect(d.topTracks.single.videoId, 'v1');
    });

    test('listas inválidas e itens que não são mapas são ignorados', () {
      final d = ArtistDetails.fromJson(const {
        'artist': 'oops',
        'albums': 'nada',
        'singles': [1, null, {'collectionId': '5', 'collectionName': 'ok'}],
        'topTracks': null,
      });
      expect(d.artist.artistId, '');
      expect(d.albums, isEmpty);
      expect(d.singles.map((a) => a.collectionId), ['5']);
      expect(d.topTracks, isEmpty);
      expect(ArtistDetails.fromJson(const {}).artist.artistName, '');
    });
  });

  group('AlbumDetails.fromJson', () {
    test('completo (Tidal)', () {
      final a = AlbumDetails.fromJson(albumDetailsJson);
      expect(a.collectionId, '9876');
      expect(a.genre, 'Alternative');
      expect(a.knownGenre, 'Alternative');
      expect(a.tracks, hasLength(2));
      expect(a.tracks.first.trackNumber, 1);
      expect(a.tracks.first.tidalId, 111);
      expect(a.tracks.first.isLossless, isTrue);
      expect(a.tracks.last.artworkUrl, isNull);
      expect(a.tracks.last.isLossless, isFalse);
    });

    test('mínimo (YT Music: sem gênero, tracks sem tidalId/videoId)', () {
      final a = AlbumDetails.fromJson(const {
        'collectionId': 'MPREb_AbC123',
        'collectionName': 'Amnesiac',
        'artistName': 'Radiohead',
        'year': '2001',
        'releaseDate': '2001',
        'tracks': [
          {'trackNumber': 1, 'trackName': 'Packt Like Sardines', 'artistName': 'Radiohead', 'durationMs': 240000},
        ],
      });
      expect(a.genre, isNull);
      expect(a.releaseDate, '2001');
      expect(a.tracks.single.tidalId, isNull);
      expect(a.tracks.single.videoId, isNull);
    });

    test('Desconhecido não é gênero conhecido; id numérico vira texto; tudo ausente não lança', () {
      final a = AlbumDetails.fromJson(const {'collectionId': 9876, 'genre': 'Desconhecido', 'tracks': 'x'});
      expect(a.collectionId, '9876');
      expect(a.genre, 'Desconhecido');
      expect(a.knownGenre, isNull);
      expect(a.tracks, isEmpty);
      expect(AlbumDetails.fromJson(const {}).collectionName, '');
    });
  });

  group('update-genre', () {
    test('request serializa com as chaves do schema', () {
      expect(const UpdateAlbumGenreRequest(albumId: '9876', genre: 'Rock').toJson(),
          {'album_id': '9876', 'genre': 'Rock'});
    });

    test('resultado updated e skipped', () {
      final u = UpdateAlbumGenreResult.fromJson(
          const {'status': 'updated', 'tracks_updated': 7, 'genre': 'Rock'});
      expect(u.wasUpdated, isTrue);
      expect(u.tracksUpdated, 7);
      expect(u.genre, 'Rock');
      final s = UpdateAlbumGenreResult.fromJson(
          const {'status': 'skipped', 'message': 'Gênero inválido'});
      expect(s.wasUpdated, isFalse);
      expect(s.tracksUpdated, 0);
      expect(s.message, 'Gênero inválido');
      expect(UpdateAlbumGenreResult.fromJson(const {}).status, '');
    });
  });

  group('CatalogRepository', () {
    late FakeAdapter adapter;

    CatalogRepository repo(Object? Function(String path) respond, {int status = 200}) {
      adapter = FakeAdapter((o) => jsonBody(respond(o.path), status: status));
      final api = ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => 'tok',
        dio: dioWith(adapter),
      );
      return CatalogRepository(api);
    }

    test('search: envia query, limit, offset e type; devolve músicas tipadas', () async {
      final r = repo((_) => [tidalSong, ytSongMinimal]);
      final items = await r.search('radiohead creep', limit: 5, offset: 10);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/search/catalog');
      expect(req.uri.queryParameters,
          {'query': 'radiohead creep', 'limit': '5', 'offset': '10', 'type': 'song'});
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(items, hasLength(2));
      expect(items.first, isA<CatalogSong>().having((s) => s.tidalId, 'tidalId', 5678));
      expect((items.last as CatalogSong).videoId, 'abc123');
    });

    test('search usa o type pedido para tipar, mesmo sem type no item', () async {
      final r = repo((_) => [
            {'collectionId': 'MPREb_x', 'collectionName': 'A', 'artistName': 'B'},
            'lixo',
          ]);
      final items = await r.search('a', type: CatalogSearchType.album);
      expect(adapter.requests.single.uri.queryParameters['type'], 'album');
      expect(items.single, isA<CatalogAlbum>());
    });

    test('searchSongs / searchAlbums / searchArtists', () async {
      var r = repo((_) => [tidalSong]);
      final songs = await r.searchSongs('x');
      expect(songs.single.trackName, 'Karma Police');
      expect(adapter.requests.single.uri.queryParameters,
          {'query': 'x', 'limit': '20', 'offset': '0', 'type': 'song'});

      r = repo((_) => [tidalAlbum, ytAlbum]);
      final albums = await r.searchAlbums('x', limit: 2);
      expect(albums.map((a) => a.collectionId), ['9876', 'MPREb_AbC123']);
      expect(adapter.requests.single.uri.queryParameters['type'], 'album');
      expect(adapter.requests.single.uri.queryParameters['limit'], '2');

      r = repo((_) => [tidalArtist, ytArtist]);
      final artists = await r.searchArtists('x', offset: 3);
      expect(artists.map((a) => a.artistId), ['3840', 'UCabcdef']);
      expect(adapter.requests.single.uri.queryParameters['type'], 'artist');
      expect(adapter.requests.single.uri.queryParameters['offset'], '3');
    });

    test('search com resposta que não é lista devolve vazio', () async {
      final r = repo((_) => {'detail': 'x'});
      expect(await r.search('a'), isEmpty);
    });

    test('artist: GET com id codificado e resposta tipada', () async {
      final r = repo((_) => artistDetailsJson);
      final d = await r.artist('UC ab/c');
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.toString(), 'https://orfeu.test/catalog/artist/UC%20ab%2Fc');
      expect(req.uri.query, isEmpty);
      expect(d.artist.artistName, 'Radiohead');
      expect(d.artist.listeners, 5000000);
      expect(d.albums.single.collectionId, '9876');
      expect(d.singles.single.isSingle, isTrue);
      expect(d.similarArtists, hasLength(2));
    });

    test('album: GET com id codificado e faixas tipadas', () async {
      final r = repo((_) => albumDetailsJson);
      final a = await r.album('MPREb_AbC123');
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/catalog/album/MPREb_AbC123');
      expect(a.collectionName, 'Kid A');
      expect(a.tracks.map((t) => t.tidalId), [111, 112]);
    });

    test('updateAlbumGenre: POST com o corpo do schema', () async {
      final r = repo((_) => {'status': 'updated', 'tracks_updated': 4, 'genre': 'Rock'});
      final res = await r.updateAlbumGenre('9876', 'Rock');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/catalog/album/update-genre');
      expect(req.data, {'album_id': '9876', 'genre': 'Rock'});
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(res.wasUpdated, isTrue);
      expect(res.tracksUpdated, 4);
    });

    test('erro do servidor vira ApiException com a mensagem do detail', () async {
      final r = repo((_) => {'detail': 'Artista não encontrado'}, status: 404);
      await expectLater(
        r.artist('999'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.isNotFound, 'isNotFound', true)
            .having((e) => e.message, 'message', 'Artista não encontrado')),
      );
      await expectLater(r.search('x'), throwsA(isA<ApiException>()));
      await expectLater(r.album('1'), throwsA(isA<ApiException>()));
      await expectLater(r.updateAlbumGenre('1', 'Rock'), throwsA(isA<ApiException>()));
    });
  });
}

List<Map<String, dynamic>> maps(Object? list) =>
    [for (final e in list! as List) Map<String, dynamic>.from(e as Map)];
