// Os fixtures JSON são literais passados a factories @immutable; não precisam ser const.
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';
import 'package:orfeu/data/library/library_models.dart';
import 'package:orfeu/data/library/library_repository.dart';
import 'package:orfeu/data/library/playlist_repository.dart';

import 'fake_adapter.dart';

void main() {
  group('modelos', () {
    test('FavoriteTrack: completo, mínimo e tipos estranhos', () {
      final full = FavoriteTrack.fromJson({
        'filename': 'Daft Punk - Get Lucky.flac',
        'display_name': 'Get Lucky',
        'artist': 'Daft Punk',
        'album': 'Random Access Memories',
        'duration': 369.4,
        'format': 'flac',
        'coverProxyUrl': 'https://orfeu.test/cover/short/abc123def456',
        'isFavorite': true,
        'tidalId': 12345678,
      });
      expect(full.filename, 'Daft Punk - Get Lucky.flac');
      expect(full.displayName, 'Get Lucky');
      expect(full.album, 'Random Access Memories');
      expect(full.duration, 369.4);
      expect(full.format, 'flac');
      expect(full.coverUrl, endsWith('abc123def456'));
      expect(full.isFavorite, isTrue);
      expect(full.tidalId, '12345678');

      final min = FavoriteTrack.fromJson({'filename': 'a.mp3'});
      expect(min.filename, 'a.mp3');
      expect(min.displayName, '');
      expect(min.album, isNull);
      expect(min.duration, isNull);
      expect(min.coverUrl, isNull);
      expect(min.tidalId, isNull);
      expect(min.isFavorite, isTrue);

      final odd = FavoriteTrack.fromJson({
        'filename': 'b.mp3',
        'display_name': 42,
        'artist': null,
        'duration': 200, // int no lugar de float
        'format': '',
        'isFavorite': 'false',
        'tidalId': '999',
      });
      expect(odd.displayName, '42');
      expect(odd.artist, '');
      expect(odd.duration, 200.0);
      expect(odd.format, isNull);
      expect(odd.isFavorite, isFalse);
      expect(odd.tidalId, '999');
    });

    test('FavoriteToggleResult', () {
      expect(FavoriteToggleResult.fromJson({'status': 'added', 'track': 'X'}).isFavorite,
          isTrue);
      final removed = FavoriteToggleResult.fromJson({'status': 'removed', 'track': 'X'});
      expect(removed.isFavorite, isFalse);
      expect(removed.track, 'X');
      expect(FavoriteToggleResult.fromJson({}).isFavorite, isFalse);
    });

    test('SavedAlbum: completo, mínimo e tipos estranhos', () {
      final full = SavedAlbum.fromJson({
        'id': '77646169',
        'title': 'Discovery',
        'artist': 'Daft Punk',
        'artworkUrl': 'https://img.test/discovery.jpg',
        'year': 2001,
        'isPinned': true,
        'savedAt': '2026-03-01T12:30:00',
      });
      expect(full.id, '77646169');
      expect(full.year, 2001);
      expect(full.isPinned, isTrue);
      expect(full.savedAt, DateTime.parse('2026-03-01T12:30:00'));

      final min = SavedAlbum.fromJson({'id': 'x', 'title': 'T', 'artist': 'A'});
      expect(min.artworkUrl, isNull);
      expect(min.year, isNull);
      expect(min.isPinned, isFalse);
      expect(min.savedAt, isNull);

      final odd = SavedAlbum.fromJson({
        'id': 77646169, // número no lugar de texto
        'title': null,
        'year': '1999',
        'isPinned': 1,
        'savedAt': 'não é data',
      });
      expect(odd.id, '77646169');
      expect(odd.title, '');
      expect(odd.year, 1999);
      expect(odd.isPinned, isTrue);
      expect(odd.savedAt, isNull);
    });

    test('SavedArtist: completo, mínimo e tipos estranhos', () {
      final full = SavedArtist.fromJson({
        'id': '3',
        'name': 'Bjork',
        'imageUrl': 'https://img.test/b.jpg',
        'isPinned': true,
        'savedAt': '2026-01-02T03:04:05',
      });
      expect(full.name, 'Bjork');
      expect(full.imageUrl, 'https://img.test/b.jpg');
      expect(full.isPinned, isTrue);
      expect(full.savedAt, isNotNull);

      final min = SavedArtist.fromJson({'id': 'z', 'name': 'Z'});
      expect(min.imageUrl, isNull);
      expect(min.isPinned, isFalse);

      final odd = SavedArtist.fromJson({'id': 3, 'name': 7, 'isPinned': 'true'});
      expect(odd.id, '3');
      expect(odd.name, '7');
      expect(odd.isPinned, isTrue);
    });

    test('SaveResult', () {
      final r = SaveResult.fromJson({'message': 'ok', 'id': 5});
      expect(r.message, 'ok');
      expect(r.rowId, 5);
      expect(SaveResult.fromJson({'id': '8'}).rowId, 8);
      expect(SaveResult.fromJson({}).message, isNull);
    });

    test('PlaylistSummary: completo, mínimo (ORM do POST) e tipos estranhos', () {
      final full = PlaylistSummary.fromJson({
        'id': 4,
        'name': 'Road trip',
        'cover_url': 'https://orfeu.test/downloads/playlist_covers/p.jpg',
        'is_public': true,
        'created_at': '2026-05-05T10:00:00+00:00',
        'tracks_count': 12,
      });
      expect(full.id, 4);
      expect(full.isPublic, isTrue);
      expect(full.tracksCount, 12);
      expect(full.createdAt!.isUtc, isTrue);

      // POST /playlists devolve o ORM: sem tracks_count e cover_url nulo.
      final min = PlaylistSummary.fromJson({
        'id': 1,
        'user_id': 9,
        'name': 'Nova',
        'cover_url': null,
        'is_public': false,
      });
      expect(min.coverUrl, isNull);
      expect(min.tracksCount, isNull);
      expect(min.createdAt, isNull);
      expect(min.isPublic, isFalse);

      final odd = PlaylistSummary.fromJson({
        'id': '7',
        'name': 123,
        'is_public': 'true',
        'tracks_count': '3',
      });
      expect(odd.id, 7);
      expect(odd.name, '123');
      expect(odd.isPublic, isTrue);
      expect(odd.tracksCount, 3);
    });

    test('PlaylistDetail e PlaylistTrack: completo, mínimo e tipos estranhos', () {
      final full = PlaylistDetail.fromJson({
        'id': 4,
        'name': 'Road trip',
        'is_public': false,
        'cover_url': null,
        'tracks': [
          {
            'filename': 'a.flac',
            'display_name': 'A',
            'artist': 'Art',
            'album': 'Alb',
            'duration': 180.5,
            'format': 'flac',
            'coverProxyUrl': 'https://orfeu.test/cover/short/aaaaaaaaaaaa',
            'id': 10,
            'playlist_item_id': 55,
          },
          'lixo',
          {'filename': 'b.mp3'},
        ],
      });
      expect(full.tracks, hasLength(2));
      final t = full.tracks.first;
      expect(t.displayName, 'A');
      expect(t.duration, 180.5);
      expect(t.trackId, 10);
      expect(t.playlistItemId, 55);
      expect(t.coverUrl, contains('/cover/short/'));
      expect(full.tracks.last.trackId, isNull);
      expect(full.tracks.last.album, isNull);

      final min = PlaylistDetail.fromJson({'id': 2, 'name': 'Vazia'});
      expect(min.tracks, isEmpty);
      expect(min.coverUrl, isNull);

      final odd = PlaylistDetail.fromJson({
        'id': '2',
        'name': null,
        'tracks': 'nada',
      });
      expect(odd.id, 2);
      expect(odd.name, '');
      expect(odd.tracks, isEmpty);

      final oddTrack = PlaylistTrack.fromJson({
        'filename': 'c.mp3',
        'duration': '61.5',
        'id': '3',
        'playlist_item_id': 4.0,
      });
      expect(oddTrack.duration, 61.5);
      expect(oddTrack.trackId, 3);
      expect(oddTrack.playlistItemId, 4);
    });

    test('CoverUploadResult', () {
      expect(CoverUploadResult.fromJson({'status': 'uploaded', 'cover_url': 'u'}).coverUrl,
          'u');
      expect(CoverUploadResult.fromJson({}).coverUrl, '');
    });

    test('corpos de requisição usam os nomes do Pydantic', () {
      expect(
        const FavoriteRequest(filename: 'f', title: 't', artist: 'a').toJson(),
        {'filename': 'f', 'title': 't', 'artist': 'a'},
      );
      expect(
        const FavoriteRequest(filename: 'f', title: 't', artist: 'a', album: 'b').toJson(),
        {'filename': 'f', 'title': 't', 'artist': 'a', 'album': 'b'},
      );
      expect(
        const SaveAlbumRequest(
                albumId: '1', title: 't', artist: 'a', artworkUrl: 'u', year: 2000)
            .toJson(),
        {'album_id': '1', 'title': 't', 'artist': 'a', 'artwork_url': 'u', 'year': 2000},
      );
      expect(const SaveAlbumRequest(albumId: '1', title: 't', artist: 'a').toJson(),
          {'album_id': '1', 'title': 't', 'artist': 'a'});
      expect(const SaveArtistRequest(artistId: '2', name: 'n', imageUrl: 'i').toJson(),
          {'artist_id': '2', 'name': 'n', 'image_url': 'i'});
      expect(const SaveArtistRequest(artistId: '2', name: 'n').toJson(),
          {'artist_id': '2', 'name': 'n'});
      expect(const PlaylistCreateRequest(name: 'p').toJson(),
          {'name': 'p', 'is_public': false});
      expect(const PlaylistUpdateRequest().toJson(), isEmpty);
      expect(
        const PlaylistUpdateRequest(name: 'n', coverUrl: 'c', isPublic: false).toJson(),
        {'name': 'n', 'cover_url': 'c', 'is_public': false},
      );
      expect(const PlaylistItemAdd(filename: 'f').toJson(), {'filename': 'f'});
      expect(
        const PlaylistItemAdd(filename: 'f', title: 't', artist: 'a', album: 'b').toJson(),
        {'filename': 'f', 'title': 't', 'artist': 'a', 'album': 'b'},
      );
    });
  });

  group('LibraryRepository', () {
    late FakeAdapter adapter;
    late LibraryRepository repo;

    void setup(Object? body, {int status = 200}) {
      adapter = FakeAdapter((_) => jsonBody(body, status: status));
      repo = LibraryRepository(ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => 'tok',
        dio: dioWith(adapter),
      ));
    }

    test('toggleFavorite envia o corpo e lê o status', () async {
      setup({'status': 'added', 'track': 'Get Lucky'});
      final r = await repo.toggleFavorite(const FavoriteRequest(
          filename: 'x.flac', title: 'Get Lucky', artist: 'Daft Punk', album: 'RAM'));
      expect(r.isFavorite, isTrue);
      expect(r.track, 'Get Lucky');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/favorites');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(req.data, {
        'filename': 'x.flac',
        'title': 'Get Lucky',
        'artist': 'Daft Punk',
        'album': 'RAM',
      });
    });

    test('favorites', () async {
      setup([
        {
          'filename': 'x.flac',
          'display_name': 'Get Lucky',
          'artist': 'Daft Punk',
          'album': 'RAM',
          'duration': 369.0,
          'format': 'flac',
          'coverProxyUrl': 'https://orfeu.test/cover/short/abcdefabcdef',
          'isFavorite': true,
          'tidalId': null,
        },
      ]);
      final list = await repo.favorites();
      expect(list.single.displayName, 'Get Lucky');
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/users/me/favorites');
    });

    test('favorites tolera resposta que não é lista', () async {
      setup({'detail': 'x'});
      expect(await repo.favorites(), isEmpty);
    });

    test('savedAlbums', () async {
      setup([
        {'id': '1', 'title': 'A', 'artist': 'B', 'isPinned': true},
        {'id': 2, 'title': 'C', 'artist': 'D'},
      ]);
      final list = await repo.savedAlbums();
      expect(list.map((a) => a.id), ['1', '2']);
      expect(list.first.isPinned, isTrue);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/users/me/albums');
    });

    test('saveAlbum', () async {
      setup({'message': 'Álbum adicionado à biblioteca', 'id': 12});
      final r = await repo.saveAlbum(const SaveAlbumRequest(
          albumId: '99', title: 'T', artist: 'A', artworkUrl: 'u', year: 2020));
      expect(r.rowId, 12);
      expect(r.message, contains('adicionado'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/albums');
      expect(req.data, {
        'album_id': '99',
        'title': 'T',
        'artist': 'A',
        'artwork_url': 'u',
        'year': 2020,
      });
    });

    test('removeAlbum codifica o id no path', () async {
      setup({'message': 'Álbum removido da biblioteca'});
      await repo.removeAlbum('a/b c');
      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.toString(), 'https://orfeu.test/users/me/albums/a%2Fb%20c');
    });

    test('toggleAlbumPin devolve o novo estado', () async {
      setup({'isPinned': true});
      expect(await repo.toggleAlbumPin('77'), isTrue);
      final req = adapter.requests.single;
      expect(req.method, 'PATCH');
      expect(req.uri.path, '/users/me/albums/77/pin');
    });

    test('savedArtists', () async {
      setup([
        {'id': '5', 'name': 'Bjork', 'imageUrl': 'u', 'isPinned': false}
      ]);
      final list = await repo.savedArtists();
      expect(list.single.name, 'Bjork');
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/users/me/artists');
    });

    test('saveArtist', () async {
      setup({'message': 'Artista já está na biblioteca', 'id': 3});
      final r = await repo.saveArtist(
          const SaveArtistRequest(artistId: '5', name: 'Bjork', imageUrl: 'u'));
      expect(r.rowId, 3);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/artists');
      expect(req.data, {'artist_id': '5', 'name': 'Bjork', 'image_url': 'u'});
    });

    test('removeArtist', () async {
      setup({'message': 'Artista removido da biblioteca'});
      await repo.removeArtist('5');
      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/users/me/artists/5');
    });

    test('erro do servidor vira ApiException', () async {
      setup({'detail': 'Álbum não encontrado na biblioteca'}, status: 404);
      await expectLater(
        repo.removeAlbum('1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Álbum não encontrado na biblioteca')),
      );
      await expectLater(repo.toggleAlbumPin('1'), throwsA(isA<ApiException>()));
    });
  });

  group('PlaylistRepository', () {
    late FakeAdapter adapter;
    late PlaylistRepository repo;

    void setup(Object? body, {int status = 200}) {
      adapter = FakeAdapter((_) => jsonBody(body, status: status));
      repo = PlaylistRepository(ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => 'tok',
        dio: dioWith(adapter),
      ));
    }

    test('create', () async {
      setup({
        'id': 8,
        'user_id': 1,
        'name': 'Nova',
        'cover_url': null,
        'is_public': true,
        'created_at': '2026-06-01T00:00:00+00:00',
      });
      final p = await repo.create(const PlaylistCreateRequest(name: 'Nova', isPublic: true));
      expect(p.id, 8);
      expect(p.isPublic, isTrue);
      expect(p.createdAt, isNotNull);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/playlists');
      expect(req.data, {'name': 'Nova', 'is_public': true});
    });

    test('list', () async {
      setup([
        {
          'id': 1,
          'name': 'A',
          'cover_url': null,
          'is_public': false,
          'created_at': '2026-01-01T00:00:00',
          'tracks_count': 0,
        },
        {'id': 2, 'name': 'B', 'tracks_count': 4},
      ]);
      final list = await repo.list();
      expect(list.map((p) => p.id), [1, 2]);
      expect(list.last.tracksCount, 4);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/users/me/playlists');
    });

    test('detail', () async {
      setup({
        'id': 3,
        'name': 'Mix',
        'is_public': false,
        'cover_url': 'u',
        'tracks': [
          {
            'filename': 'a.mp3',
            'display_name': 'A',
            'artist': 'X',
            'album': null,
            'duration': 100.0,
            'format': 'mp3',
            'coverProxyUrl': null,
            'id': 1,
            'playlist_item_id': 2,
          }
        ],
      });
      final d = await repo.detail(3);
      expect(d.name, 'Mix');
      expect(d.tracks.single.playlistItemId, 2);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/users/me/playlists/3');
    });

    test('update envia só os campos informados e lê "playlist"', () async {
      setup({
        'status': 'updated',
        'playlist': {'id': 3, 'name': 'Novo nome', 'cover_url': null, 'is_public': true},
      });
      final p = await repo.update(
          3, const PlaylistUpdateRequest(name: 'Novo nome', isPublic: true));
      expect(p.name, 'Novo nome');
      expect(p.isPublic, isTrue);
      expect(p.tracksCount, isNull);
      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/users/me/playlists/3');
      expect(req.data, {'name': 'Novo nome', 'is_public': true});
    });

    test('addTrack', () async {
      setup({'status': 'added', 'track': 'A'});
      await repo.addTrack(
          3, const PlaylistItemAdd(filename: 'a.mp3', title: 'A', artist: 'X'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/playlists/3/tracks');
      expect(req.data, {'filename': 'a.mp3', 'title': 'A', 'artist': 'X'});
    });

    test('uploadCover monta o multipart com o campo "file"', () async {
      setup({
        'status': 'uploaded',
        'cover_url': 'https://orfeu.test/downloads/playlist_covers/playlist_3_ab12cd34.png',
      });
      final r = await repo.uploadCover(3, [1, 2, 3, 4], 'capa.PNG');
      expect(r.coverUrl, endsWith('playlist_3_ab12cd34.png'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/playlists/3/cover');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(req.contentType, startsWith('multipart/form-data'));
      final form = req.data as FormData;
      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'capa.PNG');
      expect(form.files.single.value.contentType.toString(), 'image/png');
      expect(form.files.single.value.length, 4);
    });

    test('uploadCover sem extensão usa image/jpeg e aceita contentType', () async {
      setup({'status': 'uploaded', 'cover_url': 'u'});
      await repo.uploadCover(3, [1], 'capa');
      await repo.uploadCover(3, [1], 'capa.bin', contentType: 'image/webp');
      final types = adapter.requests
          .map((r) => (r.data as FormData).files.single.value.contentType.toString());
      expect(types, ['image/jpeg', 'image/webp']);
    });

    test('erros viram ApiException (inclusive no upload)', () async {
      setup({'detail': 'Playlist não encontrada'}, status: 404);
      await expectLater(
        repo.detail(99),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
      await expectLater(repo.uploadCover(99, [1], 'a.jpg'), throwsA(isA<ApiException>()));

      setup({'detail': 'Sem permissão para editar esta playlist'}, status: 403);
      await expectLater(
        repo.update(1, const PlaylistUpdateRequest(name: 'x')),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });
}
