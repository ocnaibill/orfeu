// As fixtures são mapas JSON passados direto a `fromJson`; `const` em cada um só poluiria.
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';
import 'package:orfeu/data/home/genres_repository.dart';
import 'package:orfeu/data/home/home_models.dart';
import 'package:orfeu/data/home/home_repository.dart';

import 'fake_adapter.dart';

void main() {
  group('HomeCard.fromJson', () {
    test('continue-listening com album_id', () {
      final c = HomeCard.fromJson({
        'type': 'album',
        'id': 'a1b2',
        'title': 'Fantasma',
        'artist': 'Silva',
        'imageUrl': 'https://orfeu.test/c/xyz',
        'played_at': '2026-10-01T12:30:00',
      });
      expect(c.type, 'album');
      expect(c.isAlbum, isTrue);
      expect(c.id, 'a1b2');
      expect(c.title, 'Fantasma');
      expect(c.playedAt, DateTime(2026, 10, 1, 12, 30));
      expect(c.tags, isEmpty);
      expect(c.searchQuery, isNull);
    });

    test('continue-listening album_search não tem id', () {
      final c = HomeCard.fromJson({
        'type': 'album_search',
        'title': 'Brisa',
        'artist': 'Ana',
        'imageUrl': 'u',
        'search_query': 'Ana Brisa',
        'played_at': '2026-10-01T12:30:00',
      });
      expect(c.isAlbumSearch, isTrue);
      expect(c.id, isNull);
      expect(c.searchQuery, 'Ana Brisa');
    });

    test('trajectory: id numérico vira texto', () {
      final c = HomeCard.fromJson({
        'id': 7,
        'title': 'Retrospectiva 9/2026',
        'artist': 'Orfeu Rewind',
        'imageUrl': 'https://ui-avatars.com/api/?name=Retrospectiva%209%2F2026',
        'type': 'playlist',
      });
      expect(c.id, '7');
      expect(c.isPlaylist, isTrue);
    });

    test('discover (Last.fm) com matchScore e reason', () {
      final c = HomeCard.fromJson({
        'title': 'Album X',
        'artist': 'Banda',
        'imageUrl': '',
        'type': 'album',
        'id': 123456,
        'reason': 'Porque você curte Y',
        'matchScore': 0.87,
      });
      expect(c.id, '123456');
      expect(c.imageUrl, isNull); // "" vira null
      expect(c.matchScore, 0.87);
      expect(c.reason, 'Porque você curte Y');
    });

    test('recommendations: year pode ser número ou ""', () {
      expect(HomeCard.fromJson({'title': 'a', 'year': 2021}).year, '2021');
      expect(HomeCard.fromJson({'title': 'a', 'year': ''}).year, isNull);
    });

    test('new-releases completo com cor e tags', () {
      final c = HomeCard.fromJson({
        'title': 'Bewitched',
        'artist': 'Laufey',
        'imageUrl': 'https://img/1.jpg',
        'type': 'album',
        'id': 'MPREb_1',
        'vibrantColorHex': '#4A00E0',
        'tags': ['Global', 'Novo'],
      });
      expect(c.tags, ['Global', 'Novo']);
      expect(c.vibrantColor, 0xFF4A00E0);
    });

    test('mínimo: só o que for indispensável', () {
      final c = HomeCard.fromJson({});
      expect(c.type, 'album');
      expect(c.title, '');
      expect(c.id, isNull);
      expect(c.artist, isNull);
      expect(c.tags, isEmpty);
      expect(c.vibrantColor, isNull);
    });

    test('campos com tipos estranhos não lançam', () {
      final c = HomeCard.fromJson({
        'type': 5,
        'id': 1.5,
        'title': null,
        'tags': 'não é lista',
        'matchScore': '0.5',
        'played_at': 123,
        'vibrantColorHex': 'zzzzzz',
      });
      expect(c.type, '5');
      expect(c.id, '1.5');
      expect(c.title, '');
      expect(c.tags, isEmpty);
      expect(c.matchScore, 0.5);
      expect(c.playedAt, isNull);
      expect(c.vibrantColor, isNull);
    });

    test('vibrantColor aceita hex sem #', () {
      expect(HomeCard.fromJson({'vibrantColorHex': 'd4af37'}).vibrantColor, 0xFFD4AF37);
      expect(HomeCard.fromJson({'vibrantColorHex': '#fff'}).vibrantColor, isNull);
    });

    test('listFrom ignora itens inválidos e não-listas', () {
      expect(HomeCard.listFrom([
        {'title': 'a'},
        'lixo',
        null,
        {'title': 'b'}
      ]).map((c) => c.title), ['a', 'b']);
      expect(HomeCard.listFrom({'detail': 'x'}), isEmpty);
      expect(HomeCard.listFrom(null), isEmpty);
    });
  });

  group('analytics models', () {
    test('AnalyticsSummary completo', () {
      final s = AnalyticsSummary.fromJson({
        'period_days': 7,
        'total_minutes': 340,
        'total_plays': 90,
        'top_artist': 'Silva',
        'top_artist_plays': 25,
        'unique_artists': 12,
        'unique_genres': 5,
        'top_artist_image': 'https://img/silva.jpg',
      });
      expect(s.periodDays, 7);
      expect(s.totalMinutes, 340);
      expect(s.totalPlays, 90);
      expect(s.topArtist, 'Silva');
      expect(s.hasTopArtist, isTrue);
      expect(s.topArtistPlays, 25);
      expect(s.uniqueArtists, 12);
      expect(s.uniqueGenres, 5);
      expect(s.topArtistImage, 'https://img/silva.jpg');
    });

    test('AnalyticsSummary sem histórico (Nenhum e imagem vazia)', () {
      final s = AnalyticsSummary.fromJson({
        'period_days': 30,
        'total_minutes': 0,
        'total_plays': 0,
        'top_artist': 'Nenhum',
        'top_artist_plays': 0,
        'unique_artists': 0,
        'unique_genres': 0,
        'top_artist_image': '',
      });
      expect(s.hasTopArtist, isFalse);
      expect(s.topArtistImage, isNull);
    });

    test('AnalyticsSummary mínimo e tipos estranhos', () {
      final empty = AnalyticsSummary.fromJson({});
      expect(empty.periodDays, 30);
      expect(empty.totalPlays, 0);
      expect(empty.topArtist, isNull);
      expect(empty.hasTopArtist, isFalse);

      final odd = AnalyticsSummary.fromJson({
        'total_minutes': '120',
        'total_plays': 3.0,
        'top_artist': 42,
        'unique_artists': null,
      });
      expect(odd.totalMinutes, 120);
      expect(odd.totalPlays, 3);
      expect(odd.topArtist, '42');
      expect(odd.uniqueArtists, 0);
    });

    test('TopTrack completo, mínimo e estranho', () {
      final t = TopTrack.fromJson({
        'filename': 'Silva/Fantasma/01.flac',
        'display_name': 'Fantasma',
        'artist': 'Silva',
        'plays': 14,
        'coverProxyUrl': 'https://orfeu.test/c/abc',
      });
      expect(t.filename, 'Silva/Fantasma/01.flac');
      expect(t.displayName, 'Fantasma');
      expect(t.plays, 14);
      expect(t.coverProxyUrl, 'https://orfeu.test/c/abc');

      final min = TopTrack.fromJson({
        'filename': 'a.flac',
        'display_name': null,
        'artist': null,
        'plays': 1,
        'coverProxyUrl': null,
      });
      expect(min.displayName, isNull);
      expect(min.artist, isNull);
      expect(min.coverProxyUrl, isNull);

      final odd = TopTrack.fromJson({'filename': 9, 'plays': '4'});
      expect(odd.filename, '9');
      expect(odd.plays, 4);
    });

    test('GlobalRankings completo, mínimo e estranho', () {
      final r = GlobalRankings.fromJson({
        'most_active_users': [
          {'username': 'bia', 'minutes': 900},
          {'username': 'leo', 'minutes': '450'},
        ]
      });
      expect(r.mostActiveUsers.map((e) => e.username), ['bia', 'leo']);
      expect(r.mostActiveUsers.map((e) => e.minutes), [900, 450]);
      expect(GlobalRankings.fromJson({}).mostActiveUsers, isEmpty);
      expect(GlobalRankings.fromJson({'most_active_users': 'x'}).mostActiveUsers, isEmpty);
      expect(RankingEntry.fromJson({}).username, '');
    });

    test('GeneratedPlaylist', () {
      final p = GeneratedPlaylist.fromJson(
          {'status': 'created', 'playlist_id': 42, 'name': 'Retrospectiva 9/2026'});
      expect(p.playlistId, '42');
      expect(p.name, 'Retrospectiva 9/2026');
      expect(p.status, 'created');
      final min = GeneratedPlaylist.fromJson({});
      expect(min.playlistId, '');
      expect(min.status, isNull);
      expect(GeneratedPlaylist.fromJson({'playlist_id': 'abc', 'name': 5}).name, '5');
    });
  });

  group('genre models', () {
    test('Genre completo, mínimo e estranho', () {
      final g = Genre.fromJson({
        'name': 'Hip Hop',
        'color': 0xFFFFC107,
        'search_query': 'hip hop rap',
        'playlist_id': 'a4c53f62',
      });
      expect(g.name, 'Hip Hop');
      expect(g.color, 0xFFFFC107);
      expect(g.searchQuery, 'hip hop rap');
      expect(g.playlistId, 'a4c53f62');

      final min = Genre.fromJson({'name': 'Jazz', 'playlist_id': null});
      expect(min.color, defaultGenreColor);
      expect(min.searchQuery, 'Jazz');
      expect(min.playlistId, isNull);

      final odd = Genre.fromJson({'name': 7, 'color': '4294951175'});
      expect(odd.name, '7');
      expect(odd.color, 4294951175);
    });

    test('GenreStats', () {
      final s = GenreStats.fromJson({
        'genres': [
          {'name': 'Pop', 'count': 30, 'color': 0xFFE91E63, 'search_query': 'pop hits'},
          {'name': 'Rock', 'count': '5'},
          'lixo',
        ],
        'total_tracks': 35,
      });
      expect(s.totalTracks, 35);
      expect(s.genres, hasLength(2));
      expect(s.genres.first.count, 30);
      expect(s.genres.first.searchQuery, 'pop hits');
      expect(s.genres.last.count, 5);
      expect(s.genres.last.color, defaultGenreColor);
      expect(s.genres.last.searchQuery, 'Rock');

      final empty = GenreStats.fromJson({'genres': [], 'total_tracks': 0});
      expect(empty.genres, isEmpty);
      expect(GenreStats.fromJson({}).totalTracks, 0);
    });

    test('FavoriteGenre', () {
      final f = FavoriteGenre.fromJson({
        'name': 'Jazz',
        'total_minutes': 120,
        'play_count': 40,
        'color': 0xFF9C27B0,
        'search_query': 'jazz',
        'playlist_id': 'uuid-1',
      });
      expect(f.name, 'Jazz');
      expect(f.totalMinutes, 120);
      expect(f.playCount, 40);
      expect(f.playlistId, 'uuid-1');

      final min = FavoriteGenre.fromJson({'name': 'Lo-fi', 'playlist_id': null});
      expect(min.totalMinutes, 0);
      expect(min.color, defaultGenreColor);
      expect(min.searchQuery, 'Lo-fi');
      expect(min.playlistId, isNull);

      final odd = FavoriteGenre.fromJson({'name': 'x', 'total_minutes': '9', 'play_count': 2.0});
      expect(odd.totalMinutes, 9);
      expect(odd.playCount, 2);
    });

    test('GenreTrack completo, mínimo e estranho', () {
      final t = GenreTrack.fromJson({
        'trackName': 'Song',
        'artistName': 'Artist',
        'collectionName': 'Album',
        'artworkUrl': 'https://img/1',
        'videoId': 'dQw4w9WgXcQ',
        'duration': '3:45',
        'durationMs': 225000,
        'source': 'YTMusic',
        'genre': 'Pop',
      });
      expect(t.trackName, 'Song');
      expect(t.videoId, 'dQw4w9WgXcQ');
      expect(t.durationMs, 225000);
      expect(t.source, 'YTMusic');

      final min = GenreTrack.fromJson({'trackName': 'S', 'videoId': null, 'artworkUrl': ''});
      expect(min.videoId, isNull);
      expect(min.artworkUrl, isNull);
      expect(min.durationMs, 0);

      final odd = GenreTrack.fromJson({'trackName': 5, 'durationMs': '1000', 'videoId': 12});
      expect(odd.trackName, '5');
      expect(odd.durationMs, 1000);
      expect(odd.videoId, '12');
    });

    test('GenreTracksResult: cache, ao vivo e erro', () {
      final cached = GenreTracksResult.fromJson({
        'genre': 'pop',
        'source': 'cache',
        'cached': true,
        'updated_at': '2026-11-01T03:00:00',
        'tracks': [
          {'trackName': 'A'},
          {'trackName': 'B'}
        ],
      });
      expect(cached.cached, isTrue);
      expect(cached.updatedAt, DateTime(2026, 11, 1, 3));
      expect(cached.tracks.map((t) => t.trackName), ['A', 'B']);
      expect(cached.isError, isFalse);

      final live = GenreTracksResult.fromJson(
          {'genre': 'rock', 'source': 'ytmusic', 'cached': false, 'tracks': []});
      expect(live.updatedAt, isNull);
      expect(live.tracks, isEmpty);

      final err = GenreTracksResult.fromJson(
          {'genre': 'x', 'source': 'error', 'cached': false, 'tracks': []});
      expect(err.isError, isTrue);

      final odd = GenreTracksResult.fromJson({'genre': 'x', 'cached': 'true', 'tracks': null});
      expect(odd.cached, isTrue);
      expect(odd.tracks, isEmpty);
      expect(GenreTracksResult.fromJson({}).genre, '');
    });

    test('RefreshCacheResult', () {
      final ok = RefreshCacheResult.fromJson(
          {'status': 'success', 'message': "Cache de 'pop' atualizado"});
      expect(ok.status, 'success');
      expect(ok.isError, isFalse);
      expect(RefreshCacheResult.fromJson({'status': 'error'}).isError, isTrue);
      expect(RefreshCacheResult.fromJson({'status': 'started'}).message, isNull);
      expect(RefreshCacheResult.fromJson({}).status, '');
    });

    test('GenreCacheStatus', () {
      final s = GenreCacheStatus.fromJson({
        'total_cached': 2,
        'total_supported': 40,
        'memory_cache_size': 2,
        'genres': [
          {'genre': 'pop', 'track_count': 80, 'updated_at': '2026-11-01T03:00:00'},
          {'genre': 'rock', 'track_count': '60', 'updated_at': null},
        ],
      });
      expect(s.totalCached, 2);
      expect(s.totalSupported, 40);
      expect(s.memoryCacheSize, 2);
      expect(s.genres.first.updatedAt, DateTime(2026, 11, 1, 3));
      expect(s.genres.last.trackCount, 60);
      expect(s.genres.last.updatedAt, isNull);
      final empty = GenreCacheStatus.fromJson({});
      expect(empty.totalCached, 0);
      expect(empty.genres, isEmpty);
    });
  });

  group('HomeRepository', () {
    late FakeAdapter adapter;

    HomeRepository repo() => HomeRepository(ApiClient(
          baseUrl: 'https://orfeu.test',
          tokenProvider: () => 'tok',
          dio: dioWith(adapter),
        ));

    test('continueListening', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {'type': 'album', 'id': 'a1', 'title': 'T', 'artist': 'A', 'imageUrl': 'u'},
            {'type': 'album_search', 'title': 'S', 'artist': 'B', 'search_query': 'B S'},
          ]));
      final r = await repo().continueListening(limit: 5);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/home/continue-listening');
      expect(req.uri.queryParameters, {'limit': '5'});
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(r.map((c) => c.type), ['album', 'album_search']);
      expect(r.last.searchQuery, 'B S');
    });

    test('continueListening usa limit 10 por padrão', () async {
      adapter = FakeAdapter((_) => jsonBody([]));
      expect(await repo().continueListening(), isEmpty);
      expect(adapter.requests.single.uri.queryParameters, {'limit': '10'});
    });

    test('trajectory (sem limit)', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {'id': 3, 'title': 'Retrospectiva 1/2026', 'artist': 'Orfeu Rewind', 'type': 'playlist'}
          ]));
      final r = await repo().trajectory();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/home/trajectory');
      expect(req.uri.queryParameters, isEmpty);
      expect(r.single.id, '3');
      expect(r.single.isPlaylist, isTrue);
    });

    test('discover', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {'title': 'X', 'artist': 'Y', 'type': 'album', 'id': 99, 'reason': 'Popular em Pop'}
          ]));
      final r = await repo().discover(limit: 4);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/home/discover');
      expect(req.uri.queryParameters, {'limit': '4'});
      expect(r.single.id, '99');
      expect(r.single.reason, 'Popular em Pop');
    });

    test('recommendations', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {'title': 'X', 'artist': 'Y', 'type': 'album', 'id': 1, 'year': 2020, 'reason': 'Mais de Y'}
          ]));
      final r = await repo().recommendations(limit: 8);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/home/recommendations');
      expect(req.uri.queryParameters, {'limit': '8'});
      expect(r.single.year, '2020');
    });

    test('newReleases', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {
              'title': 'N',
              'artist': 'L',
              'imageUrl': 'u',
              'type': 'album',
              'id': 'MPREb_9',
              'vibrantColorHex': '#D4AF37',
              'tags': ['Popular'],
            }
          ]));
      final r = await repo().newReleases(limit: 3);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/home/new-releases');
      expect(req.uri.queryParameters, {'limit': '3'});
      expect(r.single.tags, ['Popular']);
      expect(r.single.vibrantColor, 0xFFD4AF37);
    });

    test('feeds devolvem [] quando o servidor cai no fallback vazio', () async {
      adapter = FakeAdapter((_) => jsonBody([]));
      expect(await repo().discover(), isEmpty);
      expect(await repo().recommendations(), isEmpty);
      expect(await repo().newReleases(), isEmpty);
    });

    test('analyticsSummary', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'period_days': 7,
            'total_minutes': 10,
            'total_plays': 3,
            'top_artist': 'Silva',
            'top_artist_plays': 2,
            'unique_artists': 2,
            'unique_genres': 1,
            'top_artist_image': '',
          }));
      final s = await repo().analyticsSummary(days: 7);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/users/me/analytics/summary');
      expect(req.uri.queryParameters, {'days': '7'});
      expect(s.topArtist, 'Silva');
      expect(s.topArtistImage, isNull);
    });

    test('analyticsSummary usa 30 dias por padrão', () async {
      adapter = FakeAdapter((_) => jsonBody({}));
      final s = await repo().analyticsSummary();
      expect(adapter.requests.single.uri.queryParameters, {'days': '30'});
      expect(s.periodDays, 30);
    });

    test('topTracks', () async {
      adapter = FakeAdapter((_) => jsonBody([
            {
              'filename': 'a/b.flac',
              'display_name': 'B',
              'artist': 'A',
              'plays': 5,
              'coverProxyUrl': 'https://orfeu.test/c/1',
            }
          ]));
      final r = await repo().topTracks(limit: 3, days: 14);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/users/me/analytics/top-tracks');
      expect(req.uri.queryParameters, {'limit': '3', 'days': '14'});
      expect(r.single.plays, 5);
      expect(r.single.displayName, 'B');
    });

    test('rankings', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'most_active_users': [
              {'username': 'bia', 'minutes': 100}
            ]
          }));
      final r = await repo().rankings();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/analytics/rankings');
      expect(r.mostActiveUsers.single.username, 'bia');
    });

    test('generateRetroPlaylist', () async {
      adapter = FakeAdapter((_) =>
          jsonBody({'status': 'created', 'playlist_id': 12, 'name': 'Retrospectiva 9/2026'}));
      final r = await repo().generateRetroPlaylist(month: 9, year: 2026);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/users/me/analytics/generate-playlist');
      expect(req.uri.queryParameters, {'month': '9', 'year': '2026'});
      expect(r.playlistId, '12');
      expect(r.name, 'Retrospectiva 9/2026');
    });

    test('400 sem dados suficientes vira ApiException', () async {
      adapter = FakeAdapter((_) => jsonBody(
          {'detail': 'Não há dados suficientes para gerar playlist.'},
          status: 400));
      await expectLater(
          repo().generateRetroPlaylist(month: 1, year: 2020),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('dados suficientes'))));
    });

    test('401 no feed vira ApiException', () async {
      adapter = FakeAdapter((_) => jsonBody({'detail': 'Token inválido'}, status: 401));
      await expectLater(repo().continueListening(),
          throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)));
    });
  });

  group('GenresRepository', () {
    late FakeAdapter adapter;

    GenresRepository repo() => GenresRepository(ApiClient(
          baseUrl: 'https://orfeu.test',
          tokenProvider: () => 'tok',
          dio: dioWith(adapter),
        ));

    test('genres', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'genres': [
              {
                'name': 'Pop',
                'color': 0xFFE91E63,
                'search_query': 'pop hits',
                'playlist_id': '84974059'
              },
              {'name': 'Jazz', 'color': 0xFF9C27B0, 'search_query': 'jazz', 'playlist_id': null},
            ]
          }));
      final r = await repo().genres();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/genres');
      expect(r.map((g) => g.name), ['Pop', 'Jazz']);
      expect(r.last.playlistId, isNull);
    });

    test('featured', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'genres': [
              {'name': 'Pop', 'color': 1, 'search_query': 'pop hits', 'playlist_id': null}
            ]
          }));
      final r = await repo().featured(limit: 5);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/genres/featured');
      expect(req.uri.queryParameters, {'limit': '5'});
      expect(r.single.name, 'Pop');
    });

    test('stats', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'genres': [
              {'name': 'Rock', 'count': 4, 'color': 0xFFF44336, 'search_query': 'rock'}
            ],
            'total_tracks': 4,
          }));
      final r = await repo().stats();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/genres/stats');
      expect(r.totalTracks, 4);
      expect(r.genres.single.count, 4);
    });

    test('favorites', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'favorites': [
              {
                'name': 'Jazz',
                'total_minutes': 60,
                'play_count': 12,
                'color': 0xFF9C27B0,
                'search_query': 'jazz',
                'playlist_id': null,
              }
            ]
          }));
      final r = await repo().favorites(limit: 3, days: 30);
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/users/me/genres/favorites');
      expect(req.uri.queryParameters, {'limit': '3', 'days': '30'});
      expect(r.single.totalMinutes, 60);
    });

    test('favorites usa 6 itens e 90 dias por padrão', () async {
      adapter = FakeAdapter((_) => jsonBody({'favorites': []}));
      expect(await repo().favorites(), isEmpty);
      expect(adapter.requests.single.uri.queryParameters, {'limit': '6', 'days': '90'});
    });

    test('tracks codifica espaço e & no path', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'genre': 'hip hop',
            'source': 'cache',
            'cached': true,
            'updated_at': '2026-11-01T03:00:00',
            'tracks': [
              {'trackName': 'A', 'artistName': 'B', 'videoId': 'v1', 'durationMs': 1000}
            ],
          }));
      final r = await repo().tracks('hip hop', limit: 20);
      var req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/genres/hip%20hop/tracks');
      expect(req.uri.queryParameters, {'limit': '20'});
      expect(r.genre, 'hip hop');
      expect(r.cached, isTrue);
      expect(r.tracks.single.videoId, 'v1');

      await repo().tracks('r&b');
      req = adapter.requests.last;
      expect(req.uri.path, '/genres/r%26b/tracks');
      expect(req.uri.queryParameters, {'limit': '100'});
    });

    test('tracks com forceRefresh e envelope de erro', () async {
      adapter = FakeAdapter((_) => jsonBody(
          {'genre': 'pop', 'source': 'error', 'cached': false, 'tracks': []}));
      final r = await repo().tracks('pop', forceRefresh: true);
      expect(adapter.requests.single.uri.queryParameters,
          {'limit': '100', 'force_refresh': 'true'});
      expect(r.isError, isTrue);
      expect(r.tracks, isEmpty);
    });

    test('refreshCache de um gênero', () async {
      adapter = FakeAdapter(
          (_) => jsonBody({'status': 'success', 'message': "Cache de 'r&b' atualizado"}));
      final r = await repo().refreshCache(genre: 'r&b');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/genres/refresh-cache');
      expect(req.uri.queryParameters, {'genre': 'r&b'});
      expect(r.status, 'success');
    });

    test('refreshCache de todos', () async {
      adapter = FakeAdapter((_) => jsonBody(
          {'status': 'started', 'message': 'Atualização de 40 gêneros iniciada em background'}));
      final r = await repo().refreshCache();
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/genres/refresh-cache');
      expect(req.uri.queryParameters, isEmpty);
      expect(r.status, 'started');
    });

    test('cacheStatus', () async {
      adapter = FakeAdapter((_) => jsonBody({
            'total_cached': 1,
            'total_supported': 40,
            'memory_cache_size': 1,
            'genres': [
              {'genre': 'pop', 'track_count': 80, 'updated_at': '2026-11-01T03:00:00'}
            ],
          }));
      final r = await repo().cacheStatus();
      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/genres/cache-status');
      expect(r.totalSupported, 40);
      expect(r.genres.single.trackCount, 80);
    });

    test('403/401 em refresh vira ApiException', () async {
      adapter = FakeAdapter((_) => jsonBody({'detail': 'Not authenticated'}, status: 401));
      await expectLater(
          repo().refreshCache(),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Not authenticated')));
    });

    test('erro de servidor em genres vira ApiException', () async {
      adapter = FakeAdapter((_) => jsonBody({'detail': 'boom'}, status: 500));
      await expectLater(repo().genres(),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)));
    });
  });
}
