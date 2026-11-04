import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'home_models.dart';

/// Feed da home e analytics do usuário. Erros de rede/HTTP chegam como
/// `ApiException`; respostas vazias do servidor (ele devolve `[]` em vez de
/// erro nos feeds) viram listas vazias.
class HomeRepository {
  HomeRepository(this._api);

  final ApiClient _api;

  /// Álbuns tocados recentemente, um por álbum (`album` ou `album_search`).
  Future<List<HomeCard>> continueListening({int limit = 10}) async =>
      HomeCard.listFrom(await _api.getJson('/home/continue-listening',
          query: {'limit': limit}));

  /// Playlists "Retrospectiva" do usuário. O servidor não aceita `limit`.
  Future<List<HomeCard>> trajectory() async =>
      HomeCard.listFrom(await _api.getJson('/home/trajectory'));

  /// Artistas/álbuns novos parecidos com o que o usuário ouve.
  Future<List<HomeCard>> discover({int limit = 10}) async =>
      HomeCard.listFrom(await _api.getJson('/home/discover', query: {'limit': limit}));

  Future<List<HomeCard>> recommendations({int limit = 10}) async =>
      HomeCard.listFrom(
          await _api.getJson('/home/recommendations', query: {'limit': limit}));

  /// Lançamentos dos artistas favoritos (ou populares, sem histórico).
  Future<List<HomeCard>> newReleases({int limit = 10}) async =>
      HomeCard.listFrom(await _api.getJson('/home/new-releases', query: {'limit': limit}));

  Future<AnalyticsSummary> analyticsSummary({int days = 30}) async =>
      AnalyticsSummary.fromJson(asJson(await _api
          .getJson('/users/me/analytics/summary', query: {'days': days})));

  Future<List<TopTrack>> topTracks({int limit = 10, int days = 30}) async =>
      parseList(
          await _api.getJson('/users/me/analytics/top-tracks',
              query: {'limit': limit, 'days': days}),
          TopTrack.fromJson);

  Future<GlobalRankings> rankings() async =>
      GlobalRankings.fromJson(asJson(await _api.getJson('/analytics/rankings')));

  /// Cria (ou devolve, se já existir) a playlist "Retrospectiva mês/ano".
  /// O servidor responde 400 sem histórico suficiente.
  Future<GeneratedPlaylist> generateRetroPlaylist(
          {required int month, required int year}) async =>
      GeneratedPlaylist.fromJson(asJson(await _api.postJson(
          '/users/me/analytics/generate-playlist',
          query: {'month': month, 'year': year})));
}

final homeRepositoryProvider =
    Provider<HomeRepository>((ref) => HomeRepository(ref.watch(apiClientProvider)));
