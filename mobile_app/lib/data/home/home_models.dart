import 'package:flutter/foundation.dart';

import '../models/json.dart';

/// Card genérico dos carrosséis da home.
///
/// Os endpoints `/home/continue-listening`, `/home/trajectory`, `/home/discover`,
/// `/home/recommendations` e `/home/new-releases` devolvem listas de objetos com
/// um núcleo comum (`type`, `id`, `title`, `artist`, `imageUrl`) e extras que só
/// aparecem em alguns deles:
///
/// * continue-listening: `played_at` e, quando o álbum não tem `album_id`,
///   `type: "album_search"` com `search_query` e SEM `id`.
/// * trajectory: `type: "playlist"`, `id` numérico, `artist: "Orfeu Rewind"`.
/// * discover: `reason`, `matchScore` (só no caminho do Last.fm).
/// * recommendations: `reason` e `year` (pode vir `""` ou número).
/// * new-releases: `vibrantColorHex` e `tags`.
@immutable
class HomeCard {
  const HomeCard({
    required this.type,
    required this.title,
    this.id,
    this.artist,
    this.imageUrl,
    this.vibrantColorHex,
    this.tags = const [],
    this.reason,
    this.matchScore,
    this.year,
    this.playedAt,
    this.searchQuery,
  });

  /// `album`, `album_search`, `playlist`... Se faltar, assume `album`.
  final String type;

  /// Sempre texto, mesmo quando o servidor manda número. Nulo em `album_search`.
  final String? id;
  final String title;
  final String? artist;
  final String? imageUrl;

  /// `#RRGGBB` (new-releases).
  final String? vibrantColorHex;
  final List<String> tags;

  /// "Porque você curte X" (discover/recommendations).
  final String? reason;
  final double? matchScore;
  final String? year;

  /// Quando o álbum foi tocado por último (continue-listening).
  final DateTime? playedAt;

  /// Termo para buscar o álbum quando não há `id` (`album_search`).
  final String? searchQuery;

  factory HomeCard.fromJson(Json json) => HomeCard(
        type: asString(json['type']) ?? 'album',
        id: asString(json['id']),
        title: asString(json['title']) ?? '',
        artist: asString(json['artist']),
        imageUrl: asString(json['imageUrl']),
        vibrantColorHex: asString(json['vibrantColorHex']),
        tags: asStringList(json['tags']),
        reason: asString(json['reason']),
        matchScore: asDouble(json['matchScore']),
        year: asString(json['year']),
        playedAt: asDate(json['played_at']),
        searchQuery: asString(json['search_query']),
      );

  /// Lista de cards; qualquer coisa que não seja lista vira `[]`.
  static List<HomeCard> listFrom(Object? data) => parseList(data, HomeCard.fromJson);

  bool get isAlbum => type == 'album';
  bool get isAlbumSearch => type == 'album_search';
  bool get isPlaylist => type == 'playlist';

  /// `vibrantColorHex` como ARGB opaco (`0xFFRRGGBB`), ou null se inválido.
  int? get vibrantColor {
    var hex = vibrantColorHex;
    if (hex == null) return null;
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length != 6) return null;
    final rgb = int.tryParse(hex, radix: 16);
    return rgb == null ? null : 0xFF000000 | rgb;
  }
}

/// Resposta de `GET /users/me/analytics/summary`.
@immutable
class AnalyticsSummary {
  const AnalyticsSummary({
    this.periodDays = 30,
    this.totalMinutes = 0,
    this.totalPlays = 0,
    this.topArtist,
    this.topArtistPlays = 0,
    this.uniqueArtists = 0,
    this.uniqueGenres = 0,
    this.topArtistImage,
  });

  /// Valor que o servidor usa em `top_artist` quando não há histórico.
  static const noTopArtist = 'Nenhum';

  final int periodDays;
  final int totalMinutes;
  final int totalPlays;
  final String? topArtist;
  final int topArtistPlays;
  final int uniqueArtists;
  final int uniqueGenres;

  /// Vazia (null) quando não há artista ou a busca da imagem falhou.
  final String? topArtistImage;

  bool get hasTopArtist => topArtist != null && topArtist != noTopArtist;

  factory AnalyticsSummary.fromJson(Json json) => AnalyticsSummary(
        periodDays: asInt(json['period_days']) ?? 30,
        totalMinutes: asInt(json['total_minutes']) ?? 0,
        totalPlays: asInt(json['total_plays']) ?? 0,
        topArtist: asString(json['top_artist']),
        topArtistPlays: asInt(json['top_artist_plays']) ?? 0,
        uniqueArtists: asInt(json['unique_artists']) ?? 0,
        uniqueGenres: asInt(json['unique_genres']) ?? 0,
        topArtistImage: asString(json['top_artist_image']),
      );
}

/// Item de `GET /users/me/analytics/top-tracks`.
@immutable
class TopTrack {
  const TopTrack({
    this.filename,
    this.displayName,
    this.artist,
    this.plays = 0,
    this.coverProxyUrl,
  });

  final String? filename;
  final String? displayName;
  final String? artist;
  final int plays;

  /// URL curta e pública da capa (carrega sem header de autorização).
  final String? coverProxyUrl;

  factory TopTrack.fromJson(Json json) => TopTrack(
        filename: asString(json['filename']),
        displayName: asString(json['display_name']),
        artist: asString(json['artist']),
        plays: asInt(json['plays']) ?? 0,
        coverProxyUrl: asString(json['coverProxyUrl']),
      );
}

/// Usuário no ranking global.
@immutable
class RankingEntry {
  const RankingEntry({required this.username, this.minutes = 0});

  final String username;
  final int minutes;

  factory RankingEntry.fromJson(Json json) => RankingEntry(
        username: asString(json['username']) ?? '',
        minutes: asInt(json['minutes']) ?? 0,
      );
}

/// Resposta de `GET /analytics/rankings`.
@immutable
class GlobalRankings {
  const GlobalRankings({this.mostActiveUsers = const []});

  final List<RankingEntry> mostActiveUsers;

  factory GlobalRankings.fromJson(Json json) => GlobalRankings(
        mostActiveUsers: parseList(json['most_active_users'], RankingEntry.fromJson),
      );
}

/// Resposta de `POST /users/me/analytics/generate-playlist`.
@immutable
class GeneratedPlaylist {
  const GeneratedPlaylist({required this.playlistId, required this.name, this.status});

  /// Sempre texto (o servidor manda o id inteiro da playlist).
  final String playlistId;
  final String name;

  /// `created`.
  final String? status;

  factory GeneratedPlaylist.fromJson(Json json) => GeneratedPlaylist(
        playlistId: asString(json['playlist_id']) ?? '',
        name: asString(json['name']) ?? '',
        status: asString(json['status']),
      );
}

// ---------------------------------------------------------------------------
// Gêneros
// ---------------------------------------------------------------------------

/// Cor ARGB que o servidor usa quando o gênero não tem uma configurada.
const int defaultGenreColor = 0xFF9E9E9E;

/// Gênero de `GET /genres` e `GET /genres/featured` (vem de genre_config.py).
@immutable
class Genre {
  const Genre({
    required this.name,
    this.color = defaultGenreColor,
    this.searchQuery,
    this.playlistId,
  });

  final String name;

  /// ARGB (`0xAARRGGBB`), pronto para `Color(value)`.
  final int color;

  /// Termo de busca do gênero; cai no próprio nome.
  final String? searchQuery;

  /// UUID de playlist do Tidal, quando configurado.
  final String? playlistId;

  factory Genre.fromJson(Json json) {
    final name = asString(json['name']) ?? '';
    return Genre(
      name: name,
      color: asInt(json['color']) ?? defaultGenreColor,
      searchQuery: asString(json['search_query']) ?? name,
      playlistId: asString(json['playlist_id']),
    );
  }
}

/// Gênero da biblioteca em `GET /genres/stats`.
@immutable
class GenreStat {
  const GenreStat({
    required this.name,
    this.count = 0,
    this.color = defaultGenreColor,
    this.searchQuery,
  });

  final String name;

  /// Quantidade de faixas da biblioteca nesse gênero.
  final int count;
  final int color;
  final String? searchQuery;

  factory GenreStat.fromJson(Json json) {
    final name = asString(json['name']) ?? '';
    return GenreStat(
      name: name,
      count: asInt(json['count']) ?? 0,
      color: asInt(json['color']) ?? defaultGenreColor,
      searchQuery: asString(json['search_query']) ?? name,
    );
  }
}

/// Resposta de `GET /genres/stats`.
@immutable
class GenreStats {
  const GenreStats({this.genres = const [], this.totalTracks = 0});

  final List<GenreStat> genres;
  final int totalTracks;

  factory GenreStats.fromJson(Json json) => GenreStats(
        genres: parseList(json['genres'], GenreStat.fromJson),
        totalTracks: asInt(json['total_tracks']) ?? 0,
      );
}

/// Gênero favorito do usuário em `GET /users/me/genres/favorites`.
@immutable
class FavoriteGenre {
  const FavoriteGenre({
    required this.name,
    this.totalMinutes = 0,
    this.playCount = 0,
    this.color = defaultGenreColor,
    this.searchQuery,
    this.playlistId,
  });

  final String name;
  final int totalMinutes;
  final int playCount;
  final int color;
  final String? searchQuery;
  final String? playlistId;

  factory FavoriteGenre.fromJson(Json json) {
    final name = asString(json['name']) ?? '';
    return FavoriteGenre(
      name: name,
      totalMinutes: asInt(json['total_minutes']) ?? 0,
      playCount: asInt(json['play_count']) ?? 0,
      color: asInt(json['color']) ?? defaultGenreColor,
      searchQuery: asString(json['search_query']) ?? name,
      playlistId: asString(json['playlist_id']),
    );
  }
}

/// Faixa do cache de gêneros (`fetch_genre_tracks_from_api`, YT Music).
@immutable
class GenreTrack {
  const GenreTrack({
    required this.trackName,
    this.artistName,
    this.collectionName,
    this.artworkUrl,
    this.videoId,
    this.duration,
    this.durationMs = 0,
    this.source,
    this.genre,
  });

  final String trackName;
  final String? artistName;
  final String? collectionName;
  final String? artworkUrl;

  /// Id do vídeo no YT Music; pode faltar.
  final String? videoId;

  /// Duração em texto (`3:45`).
  final String? duration;
  final int durationMs;

  /// Origem da faixa (`YTMusic`), não confundir com [GenreTracksResult.source].
  final String? source;
  final String? genre;

  factory GenreTrack.fromJson(Json json) => GenreTrack(
        trackName: asString(json['trackName']) ?? '',
        artistName: asString(json['artistName']),
        collectionName: asString(json['collectionName']),
        artworkUrl: asString(json['artworkUrl']),
        videoId: asString(json['videoId']),
        duration: asString(json['duration']),
        durationMs: asInt(json['durationMs']) ?? 0,
        source: asString(json['source']),
        genre: asString(json['genre']),
      );
}

/// Envelope de `GET /genres/{genre_name}/tracks`.
@immutable
class GenreTracksResult {
  const GenreTracksResult({
    required this.genre,
    this.source,
    this.cached = false,
    this.updatedAt,
    this.tracks = const [],
  });

  final String genre;

  /// `cache`, `ytmusic` ou `error` (o servidor devolve 200 com lista vazia).
  final String? source;
  final bool cached;

  /// Só vem quando a resposta saiu do cache e o registro tem data.
  final DateTime? updatedAt;
  final List<GenreTrack> tracks;

  bool get isError => source == 'error';

  factory GenreTracksResult.fromJson(Json json) => GenreTracksResult(
        genre: asString(json['genre']) ?? '',
        source: asString(json['source']),
        cached: asBool(json['cached']),
        updatedAt: asDate(json['updated_at']),
        tracks: parseList(json['tracks'], GenreTrack.fromJson),
      );
}

/// Resposta de `POST /genres/refresh-cache`.
@immutable
class RefreshCacheResult {
  const RefreshCacheResult({required this.status, this.message});

  /// `success`, `error` (um gênero) ou `started` (todos, em background).
  final String status;
  final String? message;

  bool get isError => status == 'error';

  factory RefreshCacheResult.fromJson(Json json) => RefreshCacheResult(
        status: asString(json['status']) ?? '',
        message: asString(json['message']),
      );
}

/// Entrada de `GET /genres/cache-status`.
@immutable
class GenreCacheEntry {
  const GenreCacheEntry({required this.genre, this.trackCount = 0, this.updatedAt});

  final String genre;
  final int trackCount;
  final DateTime? updatedAt;

  factory GenreCacheEntry.fromJson(Json json) => GenreCacheEntry(
        genre: asString(json['genre']) ?? '',
        trackCount: asInt(json['track_count']) ?? 0,
        updatedAt: asDate(json['updated_at']),
      );
}

/// Resposta de `GET /genres/cache-status`.
@immutable
class GenreCacheStatus {
  const GenreCacheStatus({
    this.totalCached = 0,
    this.totalSupported = 0,
    this.memoryCacheSize = 0,
    this.genres = const [],
  });

  final int totalCached;
  final int totalSupported;
  final int memoryCacheSize;
  final List<GenreCacheEntry> genres;

  factory GenreCacheStatus.fromJson(Json json) => GenreCacheStatus(
        totalCached: asInt(json['total_cached']) ?? 0,
        totalSupported: asInt(json['total_supported']) ?? 0,
        memoryCacheSize: asInt(json['memory_cache_size']) ?? 0,
        genres: parseList(json['genres'], GenreCacheEntry.fromJson),
      );
}
