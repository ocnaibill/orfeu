import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'library_models.dart';

/// Playlists do usuário. O id da playlist é inteiro (id de banco).
/// Os erros do servidor chegam como `ApiException`.
class PlaylistRepository {
  PlaylistRepository(this._api);

  final ApiClient _api;

  static String _path(int id) => '/users/me/playlists/$id';

  Future<PlaylistSummary> create(PlaylistCreateRequest request) async =>
      PlaylistSummary.fromJson(asJson(
          await _api.postJson('/users/me/playlists', body: request.toJson())));

  Future<List<PlaylistSummary>> list() async => parseList(
      await _api.getJson('/users/me/playlists'), PlaylistSummary.fromJson);

  Future<PlaylistDetail> detail(int playlistId) async =>
      PlaylistDetail.fromJson(asJson(await _api.getJson(_path(playlistId))));

  /// Atualiza nome, capa (URL) ou visibilidade; devolve a playlist atualizada.
  Future<PlaylistSummary> update(
      int playlistId, PlaylistUpdateRequest request) async {
    final data = asJson(await _api.putJson(_path(playlistId), body: request.toJson()));
    return PlaylistSummary.fromJson(asJson(data['playlist']));
  }

  /// Adiciona a faixa no fim da playlist.
  Future<void> addTrack(int playlistId, PlaylistItemAdd item) async {
    await _api.postJson('${_path(playlistId)}/tracks', body: item.toJson());
  }

  /// Envia a imagem de capa (campo multipart `file`) e devolve a URL pública.
  /// O servidor exige `Content-Type` de imagem; por isso [contentType] sai
  /// da extensão do [filename] quando não é informado.
  Future<CoverUploadResult> uploadCover(
    int playlistId,
    List<int> bytes,
    String filename, {
    String? contentType,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(contentType ?? _imageType(filename)),
      ),
    });
    try {
      final response = await _api.dio.post<dynamic>(
        '${_path(playlistId)}/cover',
        data: form,
      );
      return CoverUploadResult.fromJson(asJson(response.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static String _imageType(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}

final playlistRepositoryProvider =
    Provider<PlaylistRepository>((ref) => PlaylistRepository(ref.watch(apiClientProvider)));
