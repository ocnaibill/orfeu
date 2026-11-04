import 'package:flutter/foundation.dart';

import '../models/json.dart';

// Modelos da coleção do usuário (favoritos, álbuns/artistas salvos) e das
// playlists. Os campos vêm de backend/app/routers/collection.py e playlists.py.
//
// IDs: ids de catálogo (álbum/artista) são sempre `String`. Ids de banco de
// dados (playlist, item de playlist, linha de álbum salvo) são `int`, porque o
// backend os usa como inteiros nos paths (`/playlists/{playlist_id: int}`).

// ---------------------------------------------------------------- Favoritos

/// Corpo de `POST /users/me/favorites` (`FavoriteRequest`).
@immutable
class FavoriteRequest {
  const FavoriteRequest({
    required this.filename,
    required this.title,
    required this.artist,
    this.album,
  });

  final String filename;
  final String title;
  final String artist;
  final String? album;

  Json toJson() => {
        'filename': filename,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
      };
}

/// Resposta do toggle de favorito: `{"status": "added"|"removed", "track": titulo}`.
@immutable
class FavoriteToggleResult {
  const FavoriteToggleResult({required this.isFavorite, this.track});

  /// `true` quando o servidor respondeu `added`.
  final bool isFavorite;
  final String? track;

  factory FavoriteToggleResult.fromJson(Json json) => FavoriteToggleResult(
        isFavorite: asString(json['status']) == 'added',
        track: asString(json['track']),
      );
}

/// Faixa devolvida por `GET /users/me/favorites`.
@immutable
class FavoriteTrack {
  const FavoriteTrack({
    required this.filename,
    required this.displayName,
    required this.artist,
    this.album,
    this.duration,
    this.format,
    this.coverUrl,
    this.isFavorite = true,
    this.tidalId,
  });

  final String filename;

  /// Título (`display_name` no servidor).
  final String displayName;
  final String artist;
  final String? album;

  /// Em segundos.
  final double? duration;
  final String? format;

  /// `coverProxyUrl`: URL curta de capa; precisa do token de mídia.
  final String? coverUrl;
  final bool isFavorite;
  final String? tidalId;

  factory FavoriteTrack.fromJson(Json json) => FavoriteTrack(
        filename: asString(json['filename']) ?? '',
        displayName: asString(json['display_name']) ?? '',
        artist: asString(json['artist']) ?? '',
        album: asString(json['album']),
        duration: asDouble(json['duration']),
        format: asString(json['format']),
        coverUrl: asString(json['coverProxyUrl']),
        isFavorite: asBool(json['isFavorite'], fallback: true),
        tidalId: asString(json['tidalId']),
      );
}

// ------------------------------------------------------------ Álbuns salvos

/// Corpo de `POST /users/me/albums` (`SaveAlbumRequest`).
@immutable
class SaveAlbumRequest {
  const SaveAlbumRequest({
    required this.albumId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
  });

  final String albumId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? year;

  Json toJson() => {
        'album_id': albumId,
        'title': title,
        'artist': artist,
        if (artworkUrl != null) 'artwork_url': artworkUrl,
        if (year != null) 'year': year,
      };
}

/// Álbum salvo na biblioteca (`GET /users/me/albums`).
@immutable
class SavedAlbum {
  const SavedAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
    this.isPinned = false,
    this.savedAt,
  });

  /// ID do álbum no catálogo (Tidal/YT Music), o mesmo usado em
  /// `DELETE /users/me/albums/{album_id}`.
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? year;
  final bool isPinned;
  final DateTime? savedAt;

  factory SavedAlbum.fromJson(Json json) => SavedAlbum(
        id: asString(json['id']) ?? '',
        title: asString(json['title']) ?? '',
        artist: asString(json['artist']) ?? '',
        artworkUrl: asString(json['artworkUrl']),
        year: asInt(json['year']),
        isPinned: asBool(json['isPinned']),
        savedAt: asDate(json['savedAt']),
      );
}

// ----------------------------------------------------------- Artistas salvos

/// Corpo de `POST /users/me/artists` (`SaveArtistRequest`).
@immutable
class SaveArtistRequest {
  const SaveArtistRequest({
    required this.artistId,
    required this.name,
    this.imageUrl,
  });

  final String artistId;
  final String name;
  final String? imageUrl;

  Json toJson() => {
        'artist_id': artistId,
        'name': name,
        if (imageUrl != null) 'image_url': imageUrl,
      };
}

/// Artista salvo na biblioteca (`GET /users/me/artists`).
@immutable
class SavedArtist {
  const SavedArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.isPinned = false,
    this.savedAt,
  });

  /// ID do artista no catálogo.
  final String id;
  final String name;
  final String? imageUrl;
  final bool isPinned;
  final DateTime? savedAt;

  factory SavedArtist.fromJson(Json json) => SavedArtist(
        id: asString(json['id']) ?? '',
        name: asString(json['name']) ?? '',
        imageUrl: asString(json['imageUrl']),
        isPinned: asBool(json['isPinned']),
        savedAt: asDate(json['savedAt']),
      );
}

/// Resposta de `POST /users/me/albums` e `/artists`:
/// `{"message": ..., "id": <id da linha no banco>}`. O servidor responde 200
/// nos dois casos (novo ou já salvo) e só a `message` diferencia.
@immutable
class SaveResult {
  const SaveResult({this.message, this.rowId});

  final String? message;

  /// Id da linha no banco (não é o id do catálogo).
  final int? rowId;

  factory SaveResult.fromJson(Json json) => SaveResult(
        message: asString(json['message']),
        rowId: asInt(json['id']),
      );
}

// ----------------------------------------------------------------- Playlists

/// Corpo de `POST /users/me/playlists` (`PlaylistCreate`).
@immutable
class PlaylistCreateRequest {
  const PlaylistCreateRequest({required this.name, this.isPublic = false});

  final String name;
  final bool isPublic;

  Json toJson() => {'name': name, 'is_public': isPublic};
}

/// Corpo de `PUT /users/me/playlists/{id}` (`PlaylistUpdateRequest`). Só os
/// campos não nulos são enviados (o servidor ignora os ausentes).
@immutable
class PlaylistUpdateRequest {
  const PlaylistUpdateRequest({this.name, this.coverUrl, this.isPublic});

  final String? name;
  final String? coverUrl;
  final bool? isPublic;

  Json toJson() => {
        if (name != null) 'name': name,
        if (coverUrl != null) 'cover_url': coverUrl,
        if (isPublic != null) 'is_public': isPublic,
      };
}

/// Corpo de `POST /users/me/playlists/{id}/tracks` (`PlaylistItemAdd`).
@immutable
class PlaylistItemAdd {
  const PlaylistItemAdd({
    required this.filename,
    this.title,
    this.artist,
    this.album,
  });

  final String filename;
  final String? title;
  final String? artist;
  final String? album;

  Json toJson() => {
        'filename': filename,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
      };
}

/// Playlist sem faixas: item de `GET /users/me/playlists`, resposta de
/// `POST /users/me/playlists` (o ORM serializado) e `playlist` do PUT.
///
/// `tracksCount` só vem na listagem; `createdAt` não vem no PUT.
@immutable
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    this.coverUrl,
    this.isPublic = false,
    this.createdAt,
    this.tracksCount,
  });

  /// Id de banco (inteiro), usado nos paths.
  final int id;
  final String name;
  final String? coverUrl;
  final bool isPublic;
  final DateTime? createdAt;
  final int? tracksCount;

  factory PlaylistSummary.fromJson(Json json) => PlaylistSummary(
        id: asInt(json['id']) ?? 0,
        name: asString(json['name']) ?? '',
        coverUrl: asString(json['cover_url']),
        isPublic: asBool(json['is_public']),
        createdAt: asDate(json['created_at']),
        tracksCount: asInt(json['tracks_count']),
      );
}

/// Faixa dentro de `GET /users/me/playlists/{id}`.
@immutable
class PlaylistTrack {
  const PlaylistTrack({
    required this.filename,
    required this.displayName,
    required this.artist,
    this.album,
    this.duration,
    this.format,
    this.coverUrl,
    this.trackId,
    this.playlistItemId,
  });

  final String filename;
  final String displayName;
  final String artist;
  final String? album;
  final double? duration;
  final String? format;
  final String? coverUrl;

  /// Id da faixa no banco (`id`).
  final int? trackId;

  /// Id da linha na playlist (`playlist_item_id`).
  final int? playlistItemId;

  factory PlaylistTrack.fromJson(Json json) => PlaylistTrack(
        filename: asString(json['filename']) ?? '',
        displayName: asString(json['display_name']) ?? '',
        artist: asString(json['artist']) ?? '',
        album: asString(json['album']),
        duration: asDouble(json['duration']),
        format: asString(json['format']),
        coverUrl: asString(json['coverProxyUrl']),
        trackId: asInt(json['id']),
        playlistItemId: asInt(json['playlist_item_id']),
      );
}

/// Playlist com faixas (`GET /users/me/playlists/{id}`), já em ordem.
@immutable
class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    this.isPublic = false,
    this.coverUrl,
    this.tracks = const [],
  });

  final int id;
  final String name;
  final bool isPublic;
  final String? coverUrl;
  final List<PlaylistTrack> tracks;

  factory PlaylistDetail.fromJson(Json json) => PlaylistDetail(
        id: asInt(json['id']) ?? 0,
        name: asString(json['name']) ?? '',
        isPublic: asBool(json['is_public']),
        coverUrl: asString(json['cover_url']),
        tracks: parseList(json['tracks'], PlaylistTrack.fromJson),
      );
}

/// Resposta de `POST /users/me/playlists/{id}/cover`:
/// `{"status": "uploaded", "cover_url": url pública}`.
@immutable
class CoverUploadResult {
  const CoverUploadResult({required this.coverUrl});

  final String coverUrl;

  factory CoverUploadResult.fromJson(Json json) =>
      CoverUploadResult(coverUrl: asString(json['cover_url']) ?? '');
}
