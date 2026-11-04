import 'package:flutter/foundation.dart';

import '../models/json.dart';

/// Modelos do catálogo (busca, artista, álbum).
///
/// O servidor monta estes dicts a partir de duas fontes: Tidal (ids numéricos,
/// `tidalId`) e YT Music (ids alfanuméricos, `videoId`). Chaves que só uma fonte
/// emite são anuláveis. Todo id é normalizado para `String`, exceto [CatalogSong.tidalId],
/// que o download (`SmartDownloadRequest.tidalId`) espera como inteiro.

/// Um resultado da busca (`GET /search/catalog`): música, álbum ou artista.
sealed class SearchItem {
  const SearchItem();

  /// Interpreta um item pelo campo `type` (`song`, `album`/`single`, `artist`).
  /// Sem `type`, deduz pelas chaves presentes. Devolve null se não der para saber.
  static SearchItem? tryParse(Json json) {
    final type = asString(json['type']);
    switch (type) {
      case 'song':
        return CatalogSong.fromJson(json);
      case 'album':
      case 'single':
        return CatalogAlbum.fromJson(json);
      case 'artist':
        return CatalogArtist.fromJson(json);
    }
    if (type != null) return null;
    if (json.containsKey('trackName')) return CatalogSong.fromJson(json);
    if (json.containsKey('collectionId')) return CatalogAlbum.fromJson(json);
    if (json.containsKey('artistId')) return CatalogArtist.fromJson(json);
    return null;
  }

  /// `Tidal`, `YTMusic` ou `LastFM`.
  String? get source;
  String? get artworkUrl;
}

/// Música. Aparece na busca, nas faixas de um álbum e nas top tracks de um artista.
@immutable
class CatalogSong extends SearchItem {
  const CatalogSong({
    required this.trackName,
    required this.artistName,
    this.collectionName,
    this.collectionId,
    this.artworkUrl,
    this.tidalId,
    this.videoId,
    this.durationMs,
    this.year,
    this.releaseDate,
    this.isLossless = false,
    this.source,
    this.trackNumber,
    this.isDownloaded = false,
    this.filename,
    this.genre,
  });

  factory CatalogSong.fromJson(Json json) => CatalogSong(
        trackName: asString(json['trackName']) ?? '',
        artistName: asString(json['artistName']) ?? '',
        collectionName: asString(json['collectionName']),
        collectionId: asString(json['collectionId']),
        artworkUrl: asString(json['artworkUrl']),
        tidalId: asInt(json['tidalId']),
        videoId: asString(json['videoId']),
        durationMs: asInt(json['durationMs']),
        year: asString(json['year']),
        releaseDate: asString(json['releaseDate']),
        isLossless: asBool(json['isLossless']),
        source: asString(json['source']),
        trackNumber: asInt(json['trackNumber']),
        isDownloaded: asBool(json['isDownloaded']),
        filename: asString(json['filename']),
        genre: asString(json['genre']),
      );

  final String trackName;
  final String artistName;

  /// Nome do álbum; o servidor usa `Single` quando não há álbum.
  final String? collectionName;
  final String? collectionId;
  @override
  final String? artworkUrl;

  /// Id da faixa no Tidal (só fonte Tidal, ou YT Music já casado com o Tidal).
  final int? tidalId;

  /// Id do vídeo no YT Music (só fonte YT Music, ou Tidal casado na busca).
  final String? videoId;
  final int? durationMs;
  final String? year;
  final String? releaseDate;
  final bool isLossless;
  @override
  final String? source;

  /// Só nas faixas de um álbum.
  final int? trackNumber;

  /// Só preenchido pela busca: o servidor já achou o arquivo na biblioteca local.
  final bool isDownloaded;
  final String? filename;
  final String? genre;

  Duration? get duration => durationMs == null ? null : Duration(milliseconds: durationMs!);
}

/// Álbum, EP ou single (quando [isSingle]).
@immutable
class CatalogAlbum extends SearchItem {
  const CatalogAlbum({
    required this.collectionId,
    required this.collectionName,
    required this.artistName,
    this.artistId,
    this.artworkUrl,
    this.year,
    this.releaseDate,
    this.trackCount,
    this.source,
    this.isSingle = false,
  });

  factory CatalogAlbum.fromJson(Json json) => CatalogAlbum(
        collectionId: asString(json['collectionId']) ?? '',
        collectionName: asString(json['collectionName']) ?? '',
        artistName: asString(json['artistName']) ?? '',
        artistId: asString(json['artistId']),
        artworkUrl: asString(json['artworkUrl']),
        year: asString(json['year']),
        releaseDate: asString(json['releaseDate']),
        trackCount: asInt(json['trackCount']),
        source: asString(json['source']),
        isSingle: asString(json['type']) == 'single',
      );

  /// Vazio só se o servidor mandar um álbum sem id (não deveria acontecer).
  final String collectionId;
  final String collectionName;
  final String artistName;

  /// Só nos álbuns listados dentro de um artista.
  final String? artistId;
  @override
  final String? artworkUrl;
  final String? year;
  final String? releaseDate;

  /// O YT Music não informa (vem 0 na busca, ausente na discografia).
  final int? trackCount;
  @override
  final String? source;
  final bool isSingle;
}

/// Artista. Na busca vem só o básico; em [ArtistDetails.artist] vem também o que
/// o Last.fm acrescenta (`bio`, `tags`, `listeners`, `playcount`).
@immutable
class CatalogArtist extends SearchItem {
  const CatalogArtist({
    required this.artistId,
    required this.artistName,
    this.artworkUrl,
    this.popularity,
    this.source,
    this.bio,
    this.tags = const [],
    this.listeners,
    this.playcount,
  });

  factory CatalogArtist.fromJson(Json json) => CatalogArtist(
        artistId: asString(json['artistId']) ?? '',
        artistName: asString(json['artistName']) ?? asString(json['name']) ?? '',
        artworkUrl: asString(json['artworkUrl']),
        popularity: asInt(json['popularity']),
        source: asString(json['source']),
        bio: asString(json['bio']),
        tags: asStringList(json['tags']),
        listeners: asInt(json['listeners']),
        playcount: asInt(json['playcount']),
      );

  final String artistId;
  final String artistName;
  @override
  final String? artworkUrl;

  /// Só Tidal.
  final int? popularity;
  @override
  final String? source;
  final String? bio;
  final List<String> tags;
  final int? listeners;
  final int? playcount;

  /// A bio do Last.fm vem com HTML (`<a href=...>Read more on Last.fm</a>`);
  /// aqui sem as tags, pronta para um `Text`.
  String? get plainBio {
    final b = bio;
    if (b == null) return null;
    final text = b
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    return text.isEmpty ? null : text;
  }
}

/// Artista similar. Do Last.fm vem com [match] e sem [artistId]; do Tidal, o contrário.
@immutable
class SimilarArtist {
  const SimilarArtist({
    required this.name,
    this.artistId,
    this.image,
    this.match,
    this.source,
  });

  factory SimilarArtist.fromJson(Json json) => SimilarArtist(
        name: asString(json['name']) ?? '',
        artistId: asString(json['artistId']),
        image: asString(json['image']),
        match: asDouble(json['match']),
        source: asString(json['source']),
      );

  final String name;

  /// Null quando vem do Last.fm: não dá para abrir a página do artista direto.
  final String? artistId;
  final String? image;

  /// Similaridade de 0 a 1 (só Last.fm).
  final double? match;
  final String? source;
}

/// `GET /catalog/artist/{id}`.
@immutable
class ArtistDetails {
  const ArtistDetails({
    required this.artist,
    this.albums = const [],
    this.singles = const [],
    this.topTracks = const [],
    this.similarArtists = const [],
  });

  factory ArtistDetails.fromJson(Json json) => ArtistDetails(
        artist: CatalogArtist.fromJson(asJson(json['artist'])),
        albums: parseList(json['albums'], CatalogAlbum.fromJson),
        singles: parseList(json['singles'], CatalogAlbum.fromJson),
        topTracks: parseList(json['topTracks'], CatalogSong.fromJson),
        similarArtists: parseList(json['similarArtists'], SimilarArtist.fromJson),
      );

  final CatalogArtist artist;
  final List<CatalogAlbum> albums;
  final List<CatalogAlbum> singles;
  final List<CatalogSong> topTracks;
  final List<SimilarArtist> similarArtists;
}

/// `GET /catalog/album/{id}`.
@immutable
class AlbumDetails {
  const AlbumDetails({
    required this.collectionId,
    required this.collectionName,
    required this.artistName,
    this.artworkUrl,
    this.year,
    this.releaseDate,
    this.genre,
    this.tracks = const [],
  });

  factory AlbumDetails.fromJson(Json json) => AlbumDetails(
        collectionId: asString(json['collectionId']) ?? '',
        collectionName: asString(json['collectionName']) ?? '',
        artistName: asString(json['artistName']) ?? '',
        artworkUrl: asString(json['artworkUrl']),
        year: asString(json['year']),
        releaseDate: asString(json['releaseDate']),
        genre: asString(json['genre']),
        tracks: parseList(json['tracks'], CatalogSong.fromJson),
      );

  final String collectionId;
  final String collectionName;
  final String artistName;
  final String? artworkUrl;
  final String? year;

  /// Só YT Music (repete o ano).
  final String? releaseDate;

  /// `Desconhecido` quando o servidor não achou; veja [knownGenre].
  final String? genre;
  final List<CatalogSong> tracks;

  /// [genre] sem o marcador `Desconhecido`.
  String? get knownGenre => genre == 'Desconhecido' ? null : genre;
}

/// Corpo de `POST /catalog/album/update-genre`.
@immutable
class UpdateAlbumGenreRequest {
  const UpdateAlbumGenreRequest({required this.albumId, required this.genre});

  final String albumId;
  final String genre;

  Json toJson() => {'album_id': albumId, 'genre': genre};
}

/// Resposta de `POST /catalog/album/update-genre`.
@immutable
class UpdateAlbumGenreResult {
  const UpdateAlbumGenreResult({
    required this.status,
    this.tracksUpdated = 0,
    this.genre,
    this.message,
  });

  factory UpdateAlbumGenreResult.fromJson(Json json) => UpdateAlbumGenreResult(
        status: asString(json['status']) ?? '',
        tracksUpdated: asInt(json['tracks_updated']) ?? 0,
        genre: asString(json['genre']),
        message: asString(json['message']),
      );

  /// `updated` ou `skipped` (gênero vazio ou `Desconhecido`).
  final String status;
  final int tracksUpdated;
  final String? genre;
  final String? message;

  bool get wasUpdated => status == 'updated';
}
