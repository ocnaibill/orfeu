import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/json.dart';

/// Gênero mais ouvido (`stats.top_genres[]` de `GET /users/me`).
@immutable
class TopGenre {
  const TopGenre({required this.genre, required this.plays});

  factory TopGenre.fromJson(Json json) => TopGenre(
        genre: asString(json['genre']) ?? '',
        plays: asInt(json['plays']) ?? 0,
      );

  final String genre;
  final int plays;
}

/// Estatísticas de escuta do usuário (`stats` de `GET /users/me`).
@immutable
class ProfileStats {
  const ProfileStats({
    this.hoursListened = 0,
    this.minutesListened = 0,
    this.topGenres = const [],
    this.playlistCount = 0,
    this.favoritesCount = 0,
  });

  factory ProfileStats.fromJson(Json json) => ProfileStats(
        hoursListened: asDouble(json['hours_listened']) ?? 0,
        minutesListened: asInt(json['minutes_listened']) ?? 0,
        topGenres: parseList(json['top_genres'], TopGenre.fromJson),
        playlistCount: asInt(json['playlist_count']) ?? 0,
        favoritesCount: asInt(json['favorites_count']) ?? 0,
      );

  final double hoursListened;
  final int minutesListened;
  final List<TopGenre> topGenres;
  final int playlistCount;
  final int favoritesCount;
}

/// Perfil do usuário logado (`GET /users/me`).
@immutable
class UserProfile {
  const UserProfile({
    required this.username,
    this.fullName,
    this.email,
    this.profileImageUrl,
    this.stats = const ProfileStats(),
    this.createdAt,
  });

  factory UserProfile.fromJson(Json json) => UserProfile(
        username: asString(json['username']) ?? '',
        fullName: asString(json['full_name']),
        email: asString(json['email']),
        profileImageUrl: asString(json['profile_image_url']),
        stats: ProfileStats.fromJson(asJson(json['stats'])),
        createdAt: asDate(json['created_at']),
      );

  final String username;
  final String? fullName;
  final String? email;
  final String? profileImageUrl;
  final ProfileStats stats;
  final DateTime? createdAt;
}

/// Corpo de `PUT /users/me` (schema `ProfileUpdate`). Campos nulos não vão no
/// JSON, e o servidor ignora o que não vier. Para trocar a senha, mande
/// [newPassword] junto com [currentPassword] (obrigatória nesse caso).
@immutable
class ProfileUpdate {
  const ProfileUpdate({
    this.fullName,
    this.email,
    this.profileImageUrl,
    this.currentPassword,
    this.newPassword,
  });

  final String? fullName;
  final String? email;
  final String? profileImageUrl;
  final String? currentPassword;
  final String? newPassword;

  Json toJson() => {
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
        if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
        if (currentPassword != null) 'current_password': currentPassword,
        if (newPassword != null) 'new_password': newPassword,
      };
}

/// Resposta de `PUT /users/me`: `{"status": "updated", "username": ...}`.
@immutable
class ProfileUpdateResult {
  const ProfileUpdateResult({required this.status, this.username});

  factory ProfileUpdateResult.fromJson(Json json) => ProfileUpdateResult(
        status: asString(json['status']) ?? '',
        username: asString(json['username']),
      );

  final String status;
  final String? username;

  bool get updated => status == 'updated';
}

/// Corpo de `POST /users/me/profile-image` (schema `ProfileImageUpload`).
/// O servidor aceita `image/png`, `image/jpeg`, `image/jpg`, `image/gif` e
/// `image/webp`, até 10 MB.
@immutable
class ProfileImageUpload {
  const ProfileImageUpload({required this.imageData, this.contentType = 'image/png'});

  /// Codifica os bytes da imagem em base64.
  factory ProfileImageUpload.fromBytes(Uint8List bytes,
          {String contentType = 'image/png'}) =>
      ProfileImageUpload(imageData: base64Encode(bytes), contentType: contentType);

  /// Imagem em base64.
  final String imageData;
  final String contentType;

  Json toJson() => {'image_data': imageData, 'content_type': contentType};
}

/// Resposta do upload: `{"status": "uploaded", "url": ...}`.
@immutable
class ProfileImageResult {
  const ProfileImageResult({required this.status, this.url});

  factory ProfileImageResult.fromJson(Json json) => ProfileImageResult(
        status: asString(json['status']) ?? '',
        url: asString(json['url']),
      );

  final String status;
  final String? url;

  bool get uploaded => status == 'uploaded';
}

/// Situação da conta Last.fm (`GET /users/me/lastfm`).
@immutable
class LastfmStatus {
  const LastfmStatus({required this.connected, this.username});

  factory LastfmStatus.fromJson(Json json) => LastfmStatus(
        connected: asBool(json['connected']),
        username: asString(json['username']),
      );

  final bool connected;
  final String? username;
}

/// Corpo de `POST /lastfm/auth` (schema `LastfmAuthRequest`).
@immutable
class LastfmAuthRequest {
  const LastfmAuthRequest({required this.username, required this.password});

  final String username;
  final String password;

  Json toJson() => {'username': username, 'password': password};
}

/// Resposta de `POST /lastfm/auth` (`status: "connected"`).
@immutable
class LastfmAuthResult {
  const LastfmAuthResult({required this.status, this.lastfmUsername, this.message});

  factory LastfmAuthResult.fromJson(Json json) => LastfmAuthResult(
        status: asString(json['status']) ?? '',
        lastfmUsername: asString(json['lastfm_username']),
        message: asString(json['message']),
      );

  final String status;
  final String? lastfmUsername;
  final String? message;

  bool get connected => status == 'connected';
}

/// Corpo de `POST /lastfm/scrobble` e `POST /lastfm/now-playing`
/// (schema `LastfmScrobbleRequest`). [timestamp] é em segundos unix e
/// [duration] em segundos.
@immutable
class LastfmScrobbleRequest {
  const LastfmScrobbleRequest({
    required this.artist,
    required this.track,
    this.album,
    this.timestamp,
    this.duration,
  });

  final String artist;
  final String track;
  final String? album;
  final int? timestamp;
  final int? duration;

  Json toJson() => {
        'artist': artist,
        'track': track,
        if (album != null) 'album': album,
        if (timestamp != null) 'timestamp': timestamp,
        if (duration != null) 'duration': duration,
      };
}

/// Resultado das ações Last.fm que devolvem só um `status`.
enum LastfmActionStatus {
  /// scrobble aceito
  scrobbled,

  /// now-playing atualizado
  updated,

  /// conta desconectada (`DELETE /lastfm/auth`)
  disconnected,

  /// o usuário não tem Last.fm conectado (o servidor responde 200 com isso)
  skipped,

  /// o Last.fm recusou. O servidor agora responde 502 (vira `ApiException`);
  /// o valor continua aceito no parse por compatibilidade com servidores antigos.
  failed,
  unknown;

  static LastfmActionStatus parse(String? raw) {
    switch (raw) {
      case 'scrobbled':
        return scrobbled;
      case 'updated':
        return updated;
      case 'disconnected':
        return disconnected;
      case 'skipped':
        return skipped;
      case 'failed':
        return failed;
      default:
        return unknown;
    }
  }
}

/// Resposta de scrobble, now-playing e desconexão. Falhas do Last.fm voltam
/// como HTTP 200 com `status: "failed"`/`"skipped"`, então confira [status].
@immutable
class LastfmActionResult {
  const LastfmActionResult({
    required this.status,
    this.rawStatus = '',
    this.reason,
    this.message,
    this.artist,
    this.track,
  });

  factory LastfmActionResult.fromJson(Json json) {
    final raw = asString(json['status']);
    return LastfmActionResult(
      status: LastfmActionStatus.parse(raw),
      rawStatus: raw ?? '',
      reason: asString(json['reason']),
      message: asString(json['message']),
      artist: asString(json['artist']),
      track: asString(json['track']),
    );
  }

  final LastfmActionStatus status;
  final String rawStatus;

  /// Só em `skipped`.
  final String? reason;
  final String? message;

  /// Só em `scrobbled`.
  final String? artist;
  final String? track;

  bool get isOk =>
      status == LastfmActionStatus.scrobbled ||
      status == LastfmActionStatus.updated ||
      status == LastfmActionStatus.disconnected;
}
