import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../core_providers.dart';
import '../models/json.dart';
import 'profile_models.dart';

/// Perfil do usuário e integração com o Last.fm. Deixa [ApiException] propagar.
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  /// `GET /users/me`
  Future<UserProfile> getProfile() async =>
      UserProfile.fromJson(asJson(await _api.getJson('/users/me')));

  /// `PUT /users/me`
  Future<ProfileUpdateResult> updateProfile(ProfileUpdate update) async =>
      ProfileUpdateResult.fromJson(
          asJson(await _api.putJson('/users/me', body: update.toJson())));

  /// `PUT /users/me` só com a troca de senha.
  Future<ProfileUpdateResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      updateProfile(ProfileUpdate(
          currentPassword: currentPassword, newPassword: newPassword));

  /// `POST /users/me/profile-image`
  Future<ProfileImageResult> uploadProfileImage(ProfileImageUpload upload) async =>
      ProfileImageResult.fromJson(asJson(
          await _api.postJson('/users/me/profile-image', body: upload.toJson())));

  /// `GET /users/me/lastfm`
  Future<LastfmStatus> getLastfmStatus() async =>
      LastfmStatus.fromJson(asJson(await _api.getJson('/users/me/lastfm')));

  /// `POST /lastfm/auth`. Credenciais erradas viram `ApiException` (401).
  Future<LastfmAuthResult> connectLastfm(String username, String password) async =>
      LastfmAuthResult.fromJson(asJson(await _api.postJson('/lastfm/auth',
          body: LastfmAuthRequest(username: username, password: password).toJson())));

  /// `DELETE /lastfm/auth`
  Future<LastfmActionResult> disconnectLastfm() async =>
      LastfmActionResult.fromJson(asJson(await _api.deleteJson('/lastfm/auth')));

  /// `POST /lastfm/scrobble`
  Future<LastfmActionResult> scrobble(LastfmScrobbleRequest request) async =>
      LastfmActionResult.fromJson(
          asJson(await _api.postJson('/lastfm/scrobble', body: request.toJson())));

  /// `POST /lastfm/now-playing`
  Future<LastfmActionResult> updateNowPlaying(LastfmScrobbleRequest request) async =>
      LastfmActionResult.fromJson(asJson(
          await _api.postJson('/lastfm/now-playing', body: request.toJson())));
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));
