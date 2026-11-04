import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'home_models.dart';

/// Gêneros: catálogo configurado, estatísticas da biblioteca, favoritos do
/// usuário e faixas em cache. Erros HTTP chegam como `ApiException`.
class GenresRepository {
  GenresRepository(this._api);

  final ApiClient _api;

  /// Todos os gêneros configurados no servidor.
  Future<List<Genre>> genres() async => parseList(
      asJson(await _api.getJson('/genres'))['genres'], Genre.fromJson);

  /// Gêneros em destaque ("Conheça mais").
  Future<List<Genre>> featured({int limit = 20}) async => parseList(
      asJson(await _api.getJson('/genres/featured', query: {'limit': limit}))['genres'],
      Genre.fromJson);

  /// Gêneros das faixas já na biblioteca, com contagem.
  Future<GenreStats> stats() async =>
      GenreStats.fromJson(asJson(await _api.getJson('/genres/stats')));

  /// Gêneros mais ouvidos pelo usuário, por tempo de escuta.
  Future<List<FavoriteGenre>> favorites({int limit = 6, int days = 90}) async =>
      parseList(
          asJson(await _api.getJson('/users/me/genres/favorites',
              query: {'limit': limit, 'days': days}))['favorites'],
          FavoriteGenre.fromJson);

  /// Top faixas do gênero. O nome vai codificado no path ("hip hop", "r&b").
  /// Com `forceRefresh` o servidor ignora o cache. Em falha interna o servidor
  /// responde 200 com `source: "error"` e lista vazia (veja
  /// [GenreTracksResult.isError]).
  Future<GenreTracksResult> tracks(String genreName,
      {int limit = 100, bool forceRefresh = false}) async {
    final data = await _api.getJson(
      '/genres/${Uri.encodeComponent(genreName)}/tracks',
      query: {'limit': limit, if (forceRefresh) 'force_refresh': true},
    );
    return GenreTracksResult.fromJson(asJson(data));
  }

  /// Atualiza o cache de um gênero, ou de todos (em background) sem [genre].
  Future<RefreshCacheResult> refreshCache({String? genre}) async =>
      RefreshCacheResult.fromJson(asJson(await _api.postJson('/genres/refresh-cache',
          query: genre == null ? null : {'genre': genre})));

  Future<GenreCacheStatus> cacheStatus() async =>
      GenreCacheStatus.fromJson(asJson(await _api.getJson('/genres/cache-status')));
}

final genresRepositoryProvider =
    Provider<GenresRepository>((ref) => GenresRepository(ref.watch(apiClientProvider)));
