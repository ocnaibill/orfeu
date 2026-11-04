// Os fixtures são mapas JSON literais passados a factories fromJson; o lint pede const.
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';
import 'package:orfeu/data/profile/profile_models.dart';
import 'package:orfeu/data/profile/profile_repository.dart';

import 'fake_adapter.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('completo', () {
      final p = UserProfile.fromJson({
        'username': 'bia',
        'full_name': 'Bianco Costa',
        'email': 'bia@orfeu.test',
        'profile_image_url': 'https://orfeu.test/downloads/profile_images/profile_1_ab.png',
        'stats': {
          'hours_listened': 12.5,
          'minutes_listened': 750,
          'top_genres': [
            {'genre': 'Rock', 'plays': 40},
            {'genre': 'Jazz', 'plays': 7},
          ],
          'playlist_count': 3,
          'favorites_count': 21,
        },
        'created_at': '2025-03-10T12:30:00',
      });
      expect(p.username, 'bia');
      expect(p.fullName, 'Bianco Costa');
      expect(p.email, 'bia@orfeu.test');
      expect(p.profileImageUrl, endsWith('profile_1_ab.png'));
      expect(p.stats.hoursListened, 12.5);
      expect(p.stats.minutesListened, 750);
      expect(p.stats.topGenres.map((g) => '${g.genre}:${g.plays}'), ['Rock:40', 'Jazz:7']);
      expect(p.stats.playlistCount, 3);
      expect(p.stats.favoritesCount, 21);
      expect(p.createdAt, DateTime(2025, 3, 10, 12, 30));
    });

    test('mínimo (campos nulos e stats ausente)', () {
      final p = UserProfile.fromJson({
        'username': 'bia',
        'full_name': null,
        'email': null,
        'profile_image_url': null,
        'created_at': null,
      });
      expect(p.username, 'bia');
      expect(p.fullName, isNull);
      expect(p.email, isNull);
      expect(p.profileImageUrl, isNull);
      expect(p.createdAt, isNull);
      expect(p.stats.hoursListened, 0);
      expect(p.stats.topGenres, isEmpty);
    });

    test('campos com tipo estranho', () {
      final p = UserProfile.fromJson({
        'username': 42,
        'full_name': '',
        'stats': {
          'hours_listened': '3.5',
          'minutes_listened': '210',
          'top_genres': [
            {'genre': 'Pop', 'plays': '5'},
            'lixo',
            {'plays': null},
          ],
          'playlist_count': null,
          'favorites_count': 2.0,
        },
        'created_at': 'ontem',
      });
      expect(p.username, '42');
      expect(p.fullName, isNull);
      expect(p.stats.hoursListened, 3.5);
      expect(p.stats.minutesListened, 210);
      expect(p.stats.topGenres.length, 2);
      expect(p.stats.topGenres.first.plays, 5);
      expect(p.stats.topGenres.last.genre, '');
      expect(p.stats.playlistCount, 0);
      expect(p.stats.favoritesCount, 2);
      expect(p.createdAt, isNull);
    });

    test('stats que não é mapa', () {
      final p = UserProfile.fromJson({'username': 'a', 'stats': 'x'});
      expect(p.stats.favoritesCount, 0);
    });
  });

  group('ProfileUpdate / ProfileImageUpload', () {
    test('ProfileUpdate.toJson omite nulos e usa os nomes do schema', () {
      expect(const ProfileUpdate().toJson(), isEmpty);
      expect(
        const ProfileUpdate(
          fullName: 'Nome',
          email: 'a@b.c',
          profileImageUrl: 'http://x/y.png',
          currentPassword: 'velha',
          newPassword: 'nova',
        ).toJson(),
        {
          'full_name': 'Nome',
          'email': 'a@b.c',
          'profile_image_url': 'http://x/y.png',
          'current_password': 'velha',
          'new_password': 'nova',
        },
      );
    });

    test('ProfileImageUpload usa image/png por padrão e fromBytes codifica base64', () {
      expect(const ProfileImageUpload(imageData: 'QQ==').toJson(),
          {'image_data': 'QQ==', 'content_type': 'image/png'});
      final up = ProfileImageUpload.fromBytes(Uint8List.fromList([1, 2, 3]),
          contentType: 'image/jpeg');
      expect(base64Decode(up.imageData), [1, 2, 3]);
      expect(up.toJson()['content_type'], 'image/jpeg');
    });

    test('resultados', () {
      final u = ProfileUpdateResult.fromJson({'status': 'updated', 'username': 'bia'});
      expect(u.updated, isTrue);
      expect(u.username, 'bia');
      final empty = ProfileUpdateResult.fromJson({});
      expect(empty.updated, isFalse);
      expect(empty.username, isNull);

      final img = ProfileImageResult.fromJson({'status': 'uploaded', 'url': 'http://x/p.png'});
      expect(img.uploaded, isTrue);
      expect(img.url, 'http://x/p.png');
      expect(ProfileImageResult.fromJson({'status': 7}).uploaded, isFalse);
    });
  });

  group('Last.fm models', () {
    test('LastfmStatus: completo, mínimo e tipo estranho', () {
      final full = LastfmStatus.fromJson({'connected': true, 'username': 'bia_fm'});
      expect(full.connected, isTrue);
      expect(full.username, 'bia_fm');

      final min = LastfmStatus.fromJson({'connected': false, 'username': null});
      expect(min.connected, isFalse);
      expect(min.username, isNull);

      final odd = LastfmStatus.fromJson({'connected': 'true', 'username': 99});
      expect(odd.connected, isTrue);
      expect(odd.username, '99');
      expect(LastfmStatus.fromJson({}).connected, isFalse);
    });

    test('LastfmAuthResult', () {
      final r = LastfmAuthResult.fromJson({
        'status': 'connected',
        'lastfm_username': 'bia_fm',
        'message': 'Last.fm conectado com sucesso!',
      });
      expect(r.connected, isTrue);
      expect(r.lastfmUsername, 'bia_fm');
      expect(r.message, isNotNull);
      final min = LastfmAuthResult.fromJson({});
      expect(min.connected, isFalse);
      expect(min.lastfmUsername, isNull);
      expect(LastfmAuthResult.fromJson({'status': 1, 'lastfm_username': 2}).lastfmUsername, '2');
    });

    test('requests seguem os schemas', () {
      expect(const LastfmAuthRequest(username: 'u', password: 'p').toJson(),
          {'username': 'u', 'password': 'p'});
      expect(const LastfmScrobbleRequest(artist: 'A', track: 'T').toJson(),
          {'artist': 'A', 'track': 'T'});
      expect(
        const LastfmScrobbleRequest(
                artist: 'A', track: 'T', album: 'Al', timestamp: 1700000000, duration: 215)
            .toJson(),
        {'artist': 'A', 'track': 'T', 'album': 'Al', 'timestamp': 1700000000, 'duration': 215},
      );
    });

    test('LastfmActionResult: um caso por status que o servidor devolve', () {
      final scrobbled = LastfmActionResult.fromJson(
          {'status': 'scrobbled', 'artist': 'A', 'track': 'T'});
      expect(scrobbled.status, LastfmActionStatus.scrobbled);
      expect(scrobbled.isOk, isTrue);
      expect(scrobbled.artist, 'A');
      expect(scrobbled.track, 'T');

      expect(LastfmActionResult.fromJson({'status': 'updated'}).status,
          LastfmActionStatus.updated);

      final skipped = LastfmActionResult.fromJson(
          {'status': 'skipped', 'reason': 'Last.fm não conectado'});
      expect(skipped.status, LastfmActionStatus.skipped);
      expect(skipped.isOk, isFalse);
      expect(skipped.reason, 'Last.fm não conectado');

      final failed = LastfmActionResult.fromJson(
          {'status': 'failed', 'message': 'Falha ao enviar scrobble'});
      expect(failed.status, LastfmActionStatus.failed);
      expect(failed.message, 'Falha ao enviar scrobble');

      final disc = LastfmActionResult.fromJson(
          {'status': 'disconnected', 'message': 'Last.fm desconectado.'});
      expect(disc.status, LastfmActionStatus.disconnected);
      expect(disc.isOk, isTrue);

      final odd = LastfmActionResult.fromJson({'status': 3});
      expect(odd.status, LastfmActionStatus.unknown);
      expect(odd.rawStatus, '3');
      expect(LastfmActionResult.fromJson({}).status, LastfmActionStatus.unknown);
    });
  });

  group('ProfileRepository', () {
    late FakeAdapter adapter;
    late ProfileRepository repo;

    void useResponse(Object? body, {int status = 200}) {
      adapter = FakeAdapter((_) => jsonBody(body, status: status));
      repo = ProfileRepository(ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => 'tok',
        dio: dioWith(adapter),
      ));
    }

    test('getProfile', () async {
      useResponse({
        'username': 'bia',
        'full_name': 'Bia',
        'email': 'bia@orfeu.test',
        'profile_image_url': null,
        'stats': {
          'hours_listened': 1.0,
          'minutes_listened': 60,
          'top_genres': [],
          'playlist_count': 0,
          'favorites_count': 0,
        },
        'created_at': '2025-01-01T00:00:00',
      });
      final p = await repo.getProfile();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/users/me');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(p.username, 'bia');
      expect(p.stats.minutesListened, 60);
    });

    test('updateProfile', () async {
      useResponse({'status': 'updated', 'username': 'bia'});
      final r = await repo.updateProfile(const ProfileUpdate(fullName: 'Nova'));
      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.path, '/users/me');
      expect(req.data, {'full_name': 'Nova'});
      expect(r.updated, isTrue);
    });

    test('changePassword manda current_password e new_password', () async {
      useResponse({'status': 'updated', 'username': 'bia'});
      await repo.changePassword(currentPassword: 'a', newPassword: 'b');
      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.path, '/users/me');
      expect(req.data, {'current_password': 'a', 'new_password': 'b'});
    });

    test('uploadProfileImage', () async {
      useResponse({'status': 'uploaded', 'url': 'https://orfeu.test/downloads/profile_images/p.webp'});
      final r = await repo.uploadProfileImage(
          const ProfileImageUpload(imageData: 'AAAA', contentType: 'image/webp'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/users/me/profile-image');
      expect(req.data, {'image_data': 'AAAA', 'content_type': 'image/webp'});
      expect(r.uploaded, isTrue);
      expect(r.url, endsWith('p.webp'));
    });

    test('getLastfmStatus', () async {
      useResponse({'connected': true, 'username': 'bia_fm'});
      final r = await repo.getLastfmStatus();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/users/me/lastfm');
      expect(r.connected, isTrue);
      expect(r.username, 'bia_fm');
    });

    test('connectLastfm', () async {
      useResponse({'status': 'connected', 'lastfm_username': 'bia_fm', 'message': 'ok'});
      final r = await repo.connectLastfm('bia_fm', 'segredo');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/lastfm/auth');
      expect(req.data, {'username': 'bia_fm', 'password': 'segredo'});
      expect(r.connected, isTrue);
      expect(r.lastfmUsername, 'bia_fm');
    });

    test('disconnectLastfm', () async {
      useResponse({'status': 'disconnected', 'message': 'Last.fm desconectado.'});
      final r = await repo.disconnectLastfm();
      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.path, '/lastfm/auth');
      expect(r.status, LastfmActionStatus.disconnected);
    });

    test('scrobble', () async {
      useResponse({'status': 'scrobbled', 'artist': 'A', 'track': 'T'});
      final r = await repo.scrobble(const LastfmScrobbleRequest(
          artist: 'A', track: 'T', album: 'Al', timestamp: 1700000000, duration: 200));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/lastfm/scrobble');
      expect(req.data,
          {'artist': 'A', 'track': 'T', 'album': 'Al', 'timestamp': 1700000000, 'duration': 200});
      expect(r.status, LastfmActionStatus.scrobbled);
    });

    test('updateNowPlaying (skipped é 200, não exceção)', () async {
      useResponse({'status': 'skipped', 'reason': 'Last.fm não conectado'});
      final r = await repo.updateNowPlaying(const LastfmScrobbleRequest(artist: 'A', track: 'T'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/lastfm/now-playing');
      expect(req.data, {'artist': 'A', 'track': 'T'});
      expect(r.status, LastfmActionStatus.skipped);
    });

    test('erro do servidor vira ApiException', () async {
      useResponse({'detail': 'Falha na autenticação do Last.fm. Verifique seu username e senha.'},
          status: 401);
      await expectLater(
        repo.connectLastfm('x', 'y'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Last.fm'))),
      );
    });

    test('senha atual incorreta (400)', () async {
      useResponse({'detail': 'Senha atual incorreta'}, status: 400);
      await expectLater(
        repo.changePassword(currentPassword: 'a', newPassword: 'b'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Senha atual incorreta')),
      );
    });
  });
}
