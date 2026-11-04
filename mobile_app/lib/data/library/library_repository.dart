import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'library_models.dart';

/// Coleção do usuário: favoritos, álbuns e artistas salvos.
/// Os erros do servidor chegam como `ApiException`.
class LibraryRepository {
  LibraryRepository(this._api);

  final ApiClient _api;

  // Favoritos

  /// Liga/desliga o favorito. O servidor cria a faixa se ela ainda não existir.
  Future<FavoriteToggleResult> toggleFavorite(FavoriteRequest request) async =>
      FavoriteToggleResult.fromJson(asJson(
          await _api.postJson('/users/me/favorites', body: request.toJson())));

  Future<List<FavoriteTrack>> favorites() async => parseList(
      await _api.getJson('/users/me/favorites'), FavoriteTrack.fromJson);

  // Álbuns

  Future<List<SavedAlbum>> savedAlbums() async =>
      parseList(await _api.getJson('/users/me/albums'), SavedAlbum.fromJson);

  Future<SaveResult> saveAlbum(SaveAlbumRequest request) async =>
      SaveResult.fromJson(asJson(
          await _api.postJson('/users/me/albums', body: request.toJson())));

  Future<void> removeAlbum(String albumId) async {
    await _api.deleteJson('/users/me/albums/${Uri.encodeComponent(albumId)}');
  }

  /// Alterna o fixado e devolve o novo estado (`isPinned`).
  Future<bool> toggleAlbumPin(String albumId) async {
    final data = asJson(await _api
        .patchJson('/users/me/albums/${Uri.encodeComponent(albumId)}/pin'));
    return asBool(data['isPinned']);
  }

  // Artistas

  Future<List<SavedArtist>> savedArtists() async =>
      parseList(await _api.getJson('/users/me/artists'), SavedArtist.fromJson);

  Future<SaveResult> saveArtist(SaveArtistRequest request) async =>
      SaveResult.fromJson(asJson(
          await _api.postJson('/users/me/artists', body: request.toJson())));

  Future<void> removeArtist(String artistId) async {
    await _api.deleteJson('/users/me/artists/${Uri.encodeComponent(artistId)}');
  }
}

final libraryRepositoryProvider =
    Provider<LibraryRepository>((ref) => LibraryRepository(ref.watch(apiClientProvider)));
