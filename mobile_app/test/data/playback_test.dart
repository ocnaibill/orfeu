// Os fixtures são mapas JSON literais passados a factories fromJson; o lint pede const.
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';
import 'package:orfeu/data/playback/playback_models.dart';
import 'package:orfeu/data/playback/playback_repository.dart';

import 'fake_adapter.dart';

void main() {
  group('HistoryRequest / HistoryResult', () {
    test('toJson mínimo e completo seguem o schema', () {
      expect(const HistoryRequest(filename: 'a/b.flac', durationListened: 12).toJson(),
          {'filename': 'a/b.flac', 'duration_listened': 12});
      expect(
        const HistoryRequest(
          filename: 'Tidal/A/B.flac',
          durationListened: 187.5,
          albumId: '123',
          genre: 'Rock',
          catalogTitle: 'Song',
          catalogArtist: 'Band',
          catalogAlbum: 'Record',
        ).toJson(),
        {
          'filename': 'Tidal/A/B.flac',
          'duration_listened': 187.5,
          'album_id': '123',
          'genre': 'Rock',
          'catalog_title': 'Song',
          'catalog_artist': 'Band',
          'catalog_album': 'Record',
        },
      );
    });

    test('HistoryResult: logged, error e tipo estranho', () {
      expect(HistoryResult.fromJson({'status': 'logged'}).logged, isTrue);
      final err = HistoryResult.fromJson({'status': 'error', 'message': 'Track não encontrada'});
      expect(err.logged, isFalse);
      expect(err.message, 'Track não encontrada');
      expect(HistoryResult.fromJson({'status': 1}).status, '1');
      expect(HistoryResult.fromJson({}).status, '');
    });
  });

  group('SmartDownload', () {
    test('request toJson usa tidalId/artworkUrl em camelCase', () {
      expect(const SmartDownloadRequest(artist: 'A', track: 'T').toJson(),
          {'artist': 'A', 'track': 'T'});
      expect(
        const SmartDownloadRequest(
                artist: 'A', track: 'T', album: 'Al', tidalId: 55, artworkUrl: 'http://x/c.jpg')
            .toJson(),
        {'artist': 'A', 'track': 'T', 'album': 'Al', 'tidalId': 55, 'artworkUrl': 'http://x/c.jpg'},
      );
    });

    test('Download started (Tidal)', () {
      final r = SmartDownloadResult.fromJson({
        'status': 'Download started',
        'file': 'Tidal/Band/Song_55.flac',
        'source': 'Tidal',
        'tidalId': 55,
      });
      expect(r.status, SmartDownloadStatus.started);
      expect(r.rawStatus, 'Download started');
      expect(r.file, 'Tidal/Band/Song_55.flac');
      expect(r.source, 'Tidal');
      expect(r.tidalId, 55);
      expect(r.displayName, isNull);
    });

    test('Already downloaded (cache local, com display_name)', () {
      final r = SmartDownloadResult.fromJson({
        'status': 'Already downloaded',
        'file': 'Band/Record/Song.flac',
        'display_name': 'Song',
      });
      expect(r.status, SmartDownloadStatus.alreadyDownloaded);
      expect(r.isAlreadyDownloaded, isTrue);
      expect(r.displayName, 'Song');
      expect(r.tidalId, isNull);
    });

    test('Already downloaded (soulseek, sem display_name) e Download queued', () {
      final a = SmartDownloadResult.fromJson(
          {'status': 'Already downloaded', 'file': 'x\\y.flac'});
      expect(a.status, SmartDownloadStatus.alreadyDownloaded);
      expect(a.displayName, isNull);

      final q = SmartDownloadResult.fromJson(
          {'status': 'Download queued', 'file': '@@user\\Music\\song.flac'});
      expect(q.status, SmartDownloadStatus.queued);
      expect(q.file, '@@user\\Music\\song.flac');
    });

    test('mínimo e tipos estranhos', () {
      final min = SmartDownloadResult.fromJson({});
      expect(min.status, SmartDownloadStatus.unknown);
      expect(min.file, isNull);
      final odd = SmartDownloadResult.fromJson({
        'status': 'DOWNLOAD STARTED ',
        'file': 10,
        'tidalId': '77',
      });
      expect(odd.status, SmartDownloadStatus.started);
      expect(odd.file, '10');
      expect(odd.tidalId, 77);
      expect(SmartDownloadResult.fromJson({'status': 'outra coisa'}).status,
          SmartDownloadStatus.unknown);
    });
  });

  group('DownloadStatus', () {
    test('arquivo pronto (Tidal)', () {
      final s = DownloadStatus.fromJson(
          {'state': 'Completed', 'progress': 100.0, 'speed': 0, 'message': 'Tidal Download'});
      expect(s.state, DownloadState.completed);
      expect(s.progress, 100);
      expect(s.speed, 0);
      expect(s.message, 'Tidal Download');
      expect(s.bytesTransferred, isNull);
      expect(s.isFinished, isTrue);
    });

    test('slskd em andamento (formato com percent/bytes)', () {
      final s = DownloadStatus.fromJson({
        'state': 'Downloading',
        'raw_state': 'InProgress',
        'bytes_transferred': 5000000,
        'total_bytes': 20000000,
        'speed': 250000.5,
        'percent': 25.0,
        'username': 'fulano',
      });
      expect(s.state, DownloadState.downloading);
      expect(s.rawState, 'InProgress');
      expect(s.progress, 25);
      expect(s.speed, 250000.5);
      expect(s.bytesTransferred, 5000000);
      expect(s.totalBytes, 20000000);
      expect(s.username, 'fulano');
      expect(s.isFinished, isFalse);
    });

    test('mapeia cada estado que o backend traduz', () {
      DownloadState of(String state, [String? raw]) => DownloadStatus.fromJson(
          {'state': state, if (raw != null) 'raw_state': raw}).state;
      expect(of('Completed', 'Completed, Succeeded'), DownloadState.completed);
      expect(of('Downloading', 'InProgress'), DownloadState.downloading);
      expect(of('Queued', 'Queued, Remotely'), DownloadState.queued);
      expect(of('Queued', 'Requested'), DownloadState.queued);
      expect(of('Queued', 'Initializing'), DownloadState.queued);
      expect(of('Failed', 'Completed, Rejected'), DownloadState.failed);
      expect(of('Failed', 'Completed, Cancelled'), DownloadState.failed);
      expect(of('Failed', 'Completed, Errored'), DownloadState.failed);
      expect(of('Failed', 'Completed, TimedOut'), DownloadState.failed);
      expect(of('Unknown'), DownloadState.unknown);
    });

    test('estados crus do slskd sem tradução também são entendidos', () {
      DownloadState raw(String s) => DownloadState.parse(s);
      expect(raw('Completed, Succeeded'), DownloadState.completed);
      expect(raw('InProgress'), DownloadState.downloading);
      expect(raw('Queued, Locally'), DownloadState.queued);
      expect(raw('Completed, Aborted'), DownloadState.failed);
      expect(raw('Completed'), DownloadState.completed);
      expect(raw('Banana'), DownloadState.unknown);
      expect(raw(''), DownloadState.unknown);
      expect(DownloadState.parse('NotFound'), DownloadState.notFound);
      expect(DownloadState.parse('not found'), DownloadState.notFound);
      expect(DownloadState.parse(null), DownloadState.unknown);
    });

    test('download do Tidal em andamento: Downloading com bytes', () {
      final s = DownloadStatus.fromJson({
        'state': 'Downloading', 'progress': 0.0, 'speed': 0,
        'message': 'Baixando do Tidal', 'bytes_transferred': 2048,
      });
      expect(s.state, DownloadState.downloading);
      expect(s.bytesTransferred, 2048);
      expect(s.isFinished, isFalse);
    });

    test('desconhecido pelo servidor: NotFound', () {
      final s = DownloadStatus.fromJson({
        'state': 'NotFound', 'progress': 0.0, 'speed': 0, 'message': 'Download não encontrado',
      });
      expect(s.state, DownloadState.notFound);
      expect(s.message, 'Download não encontrado');
    });

    test('ainda sem info: Unknown / Iniciando', () {
      final s = DownloadStatus.fromJson(
          {'state': 'Unknown', 'progress': 0.0, 'message': 'Iniciando'});
      expect(s.state, DownloadState.unknown);
      expect(s.progress, 0);
      expect(s.speed, 0);
      expect(s.message, 'Iniciando');
      expect(s.isFinished, isFalse);
    });

    test('mínimo e tipos estranhos', () {
      final min = DownloadStatus.fromJson({});
      expect(min.state, DownloadState.unknown);
      expect(min.progress, 0);
      expect(min.rawState, isNull);

      final odd = DownloadStatus.fromJson({
        'state': 'Downloading',
        'progress': '42.5',
        'speed': '1000',
        'bytes_transferred': '10',
        'total_bytes': 20.0,
      });
      expect(odd.progress, 42.5);
      expect(odd.speed, 1000);
      expect(odd.bytesTransferred, 10);
      expect(odd.totalBytes, 20);

      expect(DownloadStatus.fromJson({'state': 'Completed', 'percent': 130}).progress, 100);
      expect(DownloadStatus.fromJson({'state': 'Failed', 'percent': -5}).progress, 0);
    });

    test('só raw_state, sem state', () {
      expect(DownloadStatus.fromJson({'raw_state': 'Completed, Succeeded'}).state,
          DownloadState.completed);
    });
  });

  group('Letras', () {
    test('SyncedLyrics por sílaba (Apple Music), completo', () {
      final l = SyncedLyrics.fromJson({
        'source': 'apple_music',
        'syncType': 'syllable',
        'plainText': 'Hello\nWorld',
        'language': 'en',
        'lines': [
          {
            'text': 'Hello',
            'startTime': 1.0,
            'endTime': 2.5,
            'segments': [
              {'text': 'Hel', 'startTime': 1.0, 'endTime': 1.5},
              {'text': 'lo', 'startTime': 1.5, 'endTime': 2.5},
            ],
          },
          {'text': 'World', 'startTime': 3, 'endTime': 4, 'segments': []},
        ],
      });
      expect(l.source, 'apple_music');
      expect(l.syncType, LyricsSyncType.syllable);
      expect(l.language, 'en');
      expect(l.isSynced, isTrue);
      expect(l.lines.length, 2);
      expect(l.lines.first.hasSegments, isTrue);
      expect(l.lines.first.segments.last.text, 'lo');
      expect(l.lines.first.segments.last.endTime, 2.5);
      expect(l.lines.last.startTime, 3.0);
      expect(l.lines.last.hasSegments, isFalse);
    });

    test('SyncedLyrics por linha (lrclib) e lineIndexAt', () {
      final l = SyncedLyrics.fromJson({
        'source': 'lrclib',
        'syncType': 'line',
        'plainText': 'a\nb\nc',
        'language': null,
        'lines': [
          {'text': 'a', 'startTime': 0.5, 'endTime': 2.0, 'segments': []},
          {'text': 'b', 'startTime': 2.0, 'endTime': 4.0, 'segments': []},
          {'text': 'c', 'startTime': 4.0, 'endTime': 6.0, 'segments': []},
        ],
      });
      expect(l.syncType, LyricsSyncType.line);
      expect(l.language, isNull);
      expect(l.lineIndexAt(0), -1);
      expect(l.lineIndexAt(0.5), 0);
      expect(l.lineIndexAt(3.9), 1);
      expect(l.lineIndexAt(100), 2);
    });

    test('SyncedLyrics sem tempos (sync_type none) e mínimo', () {
      final l = SyncedLyrics.fromJson({
        'source': 'lrclib',
        'syncType': 'none',
        'plainText': 'só texto',
        'lines': [],
      });
      expect(l.syncType, LyricsSyncType.none);
      expect(l.isSynced, isFalse);
      expect(l.plainText, 'só texto');
      expect(l.lineIndexAt(10), -1);

      final min = SyncedLyrics.fromJson({});
      expect(min.source, '');
      expect(min.syncType, LyricsSyncType.unknown);
      expect(min.lines, isEmpty);
      expect(min.isSynced, isFalse);
    });

    test('SyncedLyrics: tipo "word" do syncedlyrics e tipos estranhos', () {
      final l = SyncedLyrics.fromJson({
        'source': 'musixmatch_enhanced',
        'syncType': 'word',
        'plainText': 3,
        'lines': [
          {'text': 'x', 'startTime': '1.5', 'endTime': null, 'segments': 'nada'},
          'lixo',
        ],
      });
      expect(l.syncType, LyricsSyncType.word);
      expect(l.rawSyncType, 'word');
      expect(l.plainText, '3');
      expect(l.lines.length, 1);
      expect(l.lines.single.startTime, 1.5);
      expect(l.lines.single.endTime, 0);
      expect(l.lines.single.segments, isEmpty);
      expect(SyncedLyrics.fromJson({'syncType': 'karaoke'}).syncType, LyricsSyncType.unknown);
    });

    test('PlainLyrics (objeto do LRCLIB)', () {
      final full = PlainLyrics.fromJson({
        'id': 1234,
        'trackName': 'Song',
        'name': 'Song (name)',
        'artistName': 'Band',
        'albumName': 'Record',
        'duration': 215.0,
        'instrumental': false,
        'plainLyrics': 'la la',
        'syncedLyrics': '[00:01.00] la la',
      });
      expect(full.id, 1234);
      expect(full.trackName, 'Song');
      expect(full.artistName, 'Band');
      expect(full.albumName, 'Record');
      expect(full.duration, 215);
      expect(full.instrumental, isFalse);
      expect(full.plainLyrics, 'la la');
      expect(full.syncedLyrics, startsWith('[00:01.00]'));
      expect(full.hasText, isTrue);

      final min = PlainLyrics.fromJson({'name': 'So o nome', 'plainLyrics': null});
      expect(min.trackName, 'So o nome');
      expect(min.hasText, isFalse);

      final odd = PlainLyrics.fromJson({'id': '9', 'duration': '120', 'instrumental': 1});
      expect(odd.id, 9);
      expect(odd.duration, 120);
      expect(odd.instrumental, isTrue);
    });
  });

  group('AppVersionInfo', () {
    test('completo', () {
      final v = AppVersionInfo.fromJson({
        'latest_version': '1.6.0',
        'release_notes_pt': 'Nova versão.',
        'platforms': {
          'android': {'url': 'https://x/o.apk'},
          'windows': {'url': 'https://x/o.exe', 'portable_url': 'https://x/o.zip'},
        },
      });
      expect(v.latestVersion, '1.6.0');
      expect(v.releaseNotes, 'Nova versão.');
      expect(v.platforms.keys, ['android', 'windows']);
      expect(v.platforms['android']!.url, 'https://x/o.apk');
      expect(v.platforms['android']!.portableUrl, isNull);
      expect(v.platforms['windows']!.portableUrl, 'https://x/o.zip');
    });

    test('mínimo (servidor sem updates.json) e tipos estranhos', () {
      final v = AppVersionInfo.fromJson({'latest_version': '0.0.0'});
      expect(v.latestVersion, '0.0.0');
      expect(v.releaseNotes, isNull);
      expect(v.platforms, isEmpty);

      final odd = AppVersionInfo.fromJson({
        'latest_version': 2,
        'platforms': {'macos': 'nada', 'android': null},
      });
      expect(odd.latestVersion, '2');
      expect(odd.platforms['macos']!.url, isNull);
      expect(AppVersionInfo.fromJson({}).latestVersion, '0.0.0');
    });
  });

  group('PlaybackRepository', () {
    late FakeAdapter adapter;
    late PlaybackRepository repo;

    void useResponse(Object? body, {int status = 200}) {
      adapter = FakeAdapter((_) => jsonBody(body, status: status));
      repo = PlaybackRepository(ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => 'tok',
        dio: dioWith(adapter),
      ));
    }

    test('logHistory', () async {
      useResponse({'status': 'logged'});
      final r = await repo.logHistory(const HistoryRequest(
          filename: 'a/b.flac', durationListened: 30.5, catalogTitle: 'T'));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/users/me/history');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(req.data, {'filename': 'a/b.flac', 'duration_listened': 30.5, 'catalog_title': 'T'});
      expect(r.logged, isTrue);
    });

    test('logHistory devolve status error sem lançar', () async {
      useResponse({'status': 'error', 'message': 'Track não encontrada'});
      final r = await repo.logHistory(const HistoryRequest(filename: 'x', durationListened: 1));
      expect(r.logged, isFalse);
      expect(r.message, 'Track não encontrada');
    });

    test('smartDownload', () async {
      useResponse({
        'status': 'Download started',
        'file': 'Tidal/Band/Song_55.flac',
        'source': 'Tidal',
        'tidalId': 55,
      });
      final r = await repo.smartDownload(
          const SmartDownloadRequest(artist: 'Band', track: 'Song', tidalId: 55));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/download/smart');
      expect(req.data, {'artist': 'Band', 'track': 'Song', 'tidalId': 55});
      expect(r.status, SmartDownloadStatus.started);
      expect(r.tidalId, 55);
    });

    test('getDownloadStatus manda filename na query', () async {
      useResponse({'state': 'Downloading', 'raw_state': 'InProgress', 'percent': 10.0, 'speed': 5});
      final s = await repo.getDownloadStatus('Tidal/Band/Song & Co_55.flac');
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/download/status');
      expect(req.queryParameters, {'filename': 'Tidal/Band/Song & Co_55.flac'});
      expect(req.uri.queryParameters['filename'], 'Tidal/Band/Song & Co_55.flac');
      expect(s.state, DownloadState.downloading);
      expect(s.progress, 10);
    });

    test('getSyncedLyrics: só os obrigatórios', () async {
      useResponse({
        'source': 'lrclib',
        'syncType': 'line',
        'plainText': 'a',
        'language': null,
        'lines': [
          {'text': 'a', 'startTime': 1.0, 'endTime': 2.0, 'segments': []},
        ],
      });
      final l = await repo.getSyncedLyrics(track: 'Song', artist: 'Band');
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/lyrics/synced');
      expect(req.queryParameters, {'track': 'Song', 'artist': 'Band'});
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(l.lines.single.text, 'a');
    });

    test('getSyncedLyrics: todos os parâmetros (apple_music_id em snake_case)', () async {
      useResponse({'source': 'apple_music', 'syncType': 'syllable', 'plainText': '', 'lines': []});
      await repo.getSyncedLyrics(
        track: 'Song',
        artist: 'Band',
        album: 'Record',
        duration: 215,
        isrc: 'USABC1234567',
        appleMusicId: '998877',
      );
      expect(adapter.requests.single.queryParameters, {
        'track': 'Song',
        'artist': 'Band',
        'album': 'Record',
        'duration': 215,
        'isrc': 'USABC1234567',
        'apple_music_id': '998877',
      });
    });

    test('getPlainLyrics', () async {
      useResponse({'id': 1, 'trackName': 'Song', 'plainLyrics': 'la la', 'syncedLyrics': null});
      final l = await repo.getPlainLyrics('Band/Record/Song.flac');
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/lyrics/plain');
      expect(req.queryParameters, {'filename': 'Band/Record/Song.flac'});
      expect(l.plainLyrics, 'la la');
    });

    test('getLatestVersion', () async {
      useResponse({
        'latest_version': '1.6.0',
        'platforms': {
          'android': {'url': 'https://x/o.apk'},
        },
      });
      final v = await repo.getLatestVersion();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.path, '/app/latest_version');
      expect(v.latestVersion, '1.6.0');
      expect(v.platforms['android']!.url, 'https://x/o.apk');
    });

    test('letra não encontrada vira ApiException 404', () async {
      useResponse({'detail': 'Letras não encontradas'}, status: 404);
      await expectLater(
        repo.getSyncedLyrics(track: 'x', artist: 'y'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNotFound, 'isNotFound', true)
            .having((e) => e.message, 'message', 'Letras não encontradas')),
      );
    });

    test('download sem fonte vira ApiException 404', () async {
      useResponse({'detail': 'Nenhum ficheiro encontrado.'}, status: 404);
      await expectLater(
        repo.smartDownload(const SmartDownloadRequest(artist: 'a', track: 'b')),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('401 no histórico', () async {
      useResponse({'detail': 'Token inválido'}, status: 401);
      await expectLater(
        repo.logHistory(const HistoryRequest(filename: 'x', durationListened: 1)),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
      );
    });
  });
}
