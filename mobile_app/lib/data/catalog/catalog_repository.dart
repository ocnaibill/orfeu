import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'catalog_models.dart';

/// Tipo de busca aceito por `GET /search/catalog`.
enum CatalogSearchType { song, album, artist }

/// Busca e detalhes do catálogo (Tidal + YT Music). Erros de rede/servidor
/// chegam como `ApiException`.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  /// Busca genérica; o resultado é tipado pelo [type] pedido.
  Future<List<SearchItem>> search(
    String query, {
    CatalogSearchType type = CatalogSearchType.song,
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _api.getJson('/search/catalog', query: {
      'query': query,
      'limit': limit,
      'offset': offset,
      'type': type.name,
    });
    return _parseItems(data, type);
  }

  Future<List<CatalogSong>> searchSongs(String query, {int limit = 20, int offset = 0}) async =>
      (await search(query, limit: limit, offset: offset)).whereType<CatalogSong>().toList();

  Future<List<CatalogAlbum>> searchAlbums(String query, {int limit = 20, int offset = 0}) async =>
      (await search(query, type: CatalogSearchType.album, limit: limit, offset: offset))
          .whereType<CatalogAlbum>()
          .toList();

  Future<List<CatalogArtist>> searchArtists(String query, {int limit = 20, int offset = 0}) async =>
      (await search(query, type: CatalogSearchType.artist, limit: limit, offset: offset))
          .whereType<CatalogArtist>()
          .toList();

  Future<ArtistDetails> artist(String artistId) async {
    final data = await _api.getJson('/catalog/artist/${Uri.encodeComponent(artistId)}');
    return ArtistDetails.fromJson(asJson(data));
  }

  Future<AlbumDetails> album(String collectionId) async {
    final data = await _api.getJson('/catalog/album/${Uri.encodeComponent(collectionId)}');
    return AlbumDetails.fromJson(asJson(data));
  }

  /// Grava o gênero nas faixas do álbum que ainda não têm (exige login).
  Future<UpdateAlbumGenreResult> updateAlbumGenre(String albumId, String genre) async {
    final data = await _api.postJson(
      '/catalog/album/update-genre',
      body: UpdateAlbumGenreRequest(albumId: albumId, genre: genre).toJson(),
    );
    return UpdateAlbumGenreResult.fromJson(asJson(data));
  }

  /// Usa o tipo pedido (e não o `type` do item) para escolher o modelo, então
  /// itens sem `type` também são lidos.
  static List<SearchItem> _parseItems(Object? data, CatalogSearchType type) {
    return switch (type) {
      CatalogSearchType.song => parseList<SearchItem>(data, CatalogSong.fromJson),
      CatalogSearchType.album => parseList<SearchItem>(data, CatalogAlbum.fromJson),
      CatalogSearchType.artist => parseList<SearchItem>(data, CatalogArtist.fromJson),
    };
  }
}

final catalogRepositoryProvider =
    Provider<CatalogRepository>((ref) => CatalogRepository(ref.watch(apiClientProvider)));
