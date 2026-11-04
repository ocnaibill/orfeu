import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'playback_models.dart';

/// Histórico de escuta, downloads, letras e versão do app. Deixa
/// [ApiException] propagar.
class PlaybackRepository {
  PlaybackRepository(this._api);

  final ApiClient _api;

  /// `POST /users/me/history`. Confira [HistoryResult.logged]: faixa
  /// desconhecida volta como 200 com `status: "error"`.
  Future<HistoryResult> logHistory(HistoryRequest request) async =>
      HistoryResult.fromJson(
          asJson(await _api.postJson('/users/me/history', body: request.toJson())));

  /// `POST /download/smart`
  Future<SmartDownloadResult> smartDownload(SmartDownloadRequest request) async =>
      SmartDownloadResult.fromJson(
          asJson(await _api.postJson('/download/smart', body: request.toJson())));

  /// `GET /download/status?filename=`
  Future<DownloadStatus> getDownloadStatus(String filename) async =>
      DownloadStatus.fromJson(asJson(
          await _api.getJson('/download/status', query: {'filename': filename})));

  /// `GET /lyrics/synced`. 404 (letra não encontrada) vira `ApiException`.
  Future<SyncedLyrics> getSyncedLyrics({
    required String track,
    required String artist,
    String? album,
    int? duration,
    String? isrc,
    String? appleMusicId,
  }) async =>
      SyncedLyrics.fromJson(asJson(await _api.getJson('/lyrics/synced', query: {
        'track': track,
        'artist': artist,
        if (album != null) 'album': album,
        if (duration != null) 'duration': duration,
        if (isrc != null) 'isrc': isrc,
        if (appleMusicId != null) 'apple_music_id': appleMusicId,
      })));

  /// `GET /lyrics/plain?filename=`. 404 vira `ApiException`.
  Future<PlainLyrics> getPlainLyrics(String filename) async => PlainLyrics.fromJson(
      asJson(await _api.getJson('/lyrics/plain', query: {'filename': filename})));

  /// `GET /app/latest_version` (o servidor não exige login nessa rota, mas o
  /// token vai junto sem problema).
  Future<AppVersionInfo> getLatestVersion() async =>
      AppVersionInfo.fromJson(asJson(await _api.getJson('/app/latest_version')));
}

final playbackRepositoryProvider =
    Provider<PlaybackRepository>((ref) => PlaybackRepository(ref.watch(apiClientProvider)));
