import 'package:flutter/foundation.dart';

import '../models/json.dart';

// ---------------------------------------------------------------------------
// Histórico de escuta
// ---------------------------------------------------------------------------

/// Corpo de `POST /users/me/history` (schema `HistoryRequest`).
///
/// [durationListened] é em segundos. Os campos `catalog*` têm prioridade sobre
/// as tags do arquivo no servidor.
@immutable
class HistoryRequest {
  const HistoryRequest({
    required this.filename,
    required this.durationListened,
    this.albumId,
    this.genre,
    this.catalogTitle,
    this.catalogArtist,
    this.catalogAlbum,
  });

  final String filename;
  final double durationListened;
  final String? albumId;
  final String? genre;
  final String? catalogTitle;
  final String? catalogArtist;
  final String? catalogAlbum;

  Json toJson() => {
        'filename': filename,
        'duration_listened': durationListened,
        if (albumId != null) 'album_id': albumId,
        if (genre != null) 'genre': genre,
        if (catalogTitle != null) 'catalog_title': catalogTitle,
        if (catalogArtist != null) 'catalog_artist': catalogArtist,
        if (catalogAlbum != null) 'catalog_album': catalogAlbum,
      };
}

/// Resposta de `POST /users/me/history`: `{"status": "logged"}`. Se a faixa
/// não existir, o servidor responde 200 com `{"status": "error", "message": ...}`.
@immutable
class HistoryResult {
  const HistoryResult({required this.status, this.message});

  factory HistoryResult.fromJson(Json json) => HistoryResult(
        status: asString(json['status']) ?? '',
        message: asString(json['message']),
      );

  final String status;
  final String? message;

  bool get logged => status == 'logged';
}

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

/// Corpo de `POST /download/smart` (schema `SmartDownloadRequest`).
@immutable
class SmartDownloadRequest {
  const SmartDownloadRequest({
    required this.artist,
    required this.track,
    this.album,
    this.tidalId,
    this.artworkUrl,
  });

  final String artist;
  final String track;
  final String? album;
  final int? tidalId;
  final String? artworkUrl;

  Json toJson() => {
        'artist': artist,
        'track': track,
        if (album != null) 'album': album,
        if (tidalId != null) 'tidalId': tidalId,
        if (artworkUrl != null) 'artworkUrl': artworkUrl,
      };
}

/// O que aconteceu com o pedido de download inteligente.
enum SmartDownloadStatus {
  /// "Download started": baixando do Tidal em segundo plano.
  started,

  /// "Already downloaded": já está na biblioteca.
  alreadyDownloaded,

  /// "Download queued": enfileirado no Soulseek (slskd).
  queued,
  unknown;

  static SmartDownloadStatus parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'download started':
        return started;
      case 'already downloaded':
        return alreadyDownloaded;
      case 'download queued':
        return queued;
      default:
        return unknown;
    }
  }
}

/// Resposta de `POST /download/smart`. Os campos variam por caso:
/// - `started`: [file], [source] (`"Tidal"`), [tidalId];
/// - `alreadyDownloaded`: [file], [displayName] (só quando veio do cache local);
/// - `queued`: [file] (nome remoto no Soulseek).
@immutable
class SmartDownloadResult {
  const SmartDownloadResult({
    required this.status,
    this.rawStatus = '',
    this.file,
    this.source,
    this.tidalId,
    this.displayName,
  });

  factory SmartDownloadResult.fromJson(Json json) {
    final raw = asString(json['status']);
    return SmartDownloadResult(
      status: SmartDownloadStatus.parse(raw),
      rawStatus: raw ?? '',
      file: asString(json['file']),
      source: asString(json['source']),
      tidalId: asInt(json['tidalId']),
      displayName: asString(json['display_name']),
    );
  }

  final SmartDownloadStatus status;

  /// Texto original de `status`.
  final String rawStatus;

  /// Caminho relativo na biblioteca (ou nome remoto, quando [status] é `queued`).
  final String? file;
  final String? source;
  final int? tidalId;
  final String? displayName;

  bool get isAlreadyDownloaded => status == SmartDownloadStatus.alreadyDownloaded;
}

/// Estado unificado de um download.
enum DownloadState {
  completed,
  downloading,
  queued,
  failed,
  unknown;

  /// Aceita os estados que o backend já traduz ("Completed", "Downloading",
  /// "Queued", "Failed", "Unknown") e também os crus do slskd
  /// ("Completed, Succeeded", "InProgress", "Completed, Errored"...).
  static DownloadState parse(String? raw) {
    final s = (raw ?? '').toLowerCase();
    if (s.isEmpty) return unknown;
    if (s.contains('succeeded')) return completed;
    const failures = ['fail', 'rejected', 'cancelled', 'errored', 'timedout', 'aborted'];
    if (failures.any(s.contains)) return failed;
    if (s.contains('inprogress') || s.contains('downloading')) return downloading;
    if (s.contains('queued') || s.contains('requested') || s.contains('initializing')) {
      return queued;
    }
    if (s.contains('completed')) return completed;
    return unknown;
  }
}

/// Resposta de `GET /download/status`. Junta duas formas:
/// - arquivo já na biblioteca: `{state, progress, speed, message}`;
/// - transferência no slskd: `{state, raw_state, bytes_transferred,
///   total_bytes, speed, percent, username}`;
/// - nada encontrado: `{state: "Unknown", progress: 0.0, message: "Iniciando"}`.
@immutable
class DownloadStatus {
  const DownloadStatus({
    required this.state,
    this.rawState,
    this.progress = 0,
    this.speed = 0,
    this.message,
    this.bytesTransferred,
    this.totalBytes,
    this.username,
  });

  factory DownloadStatus.fromJson(Json json) {
    final rawState = asString(json['raw_state']) ?? asString(json['state']);
    return DownloadStatus(
      state: DownloadState.parse(asString(json['state']) ?? rawState),
      rawState: rawState,
      progress: (asDouble(json['progress']) ?? asDouble(json['percent']) ?? 0)
          .clamp(0, 100)
          .toDouble(),
      speed: asDouble(json['speed']) ?? 0,
      message: asString(json['message']),
      bytesTransferred: asInt(json['bytes_transferred']),
      totalBytes: asInt(json['total_bytes']),
      username: asString(json['username']),
    );
  }

  final DownloadState state;

  /// Texto original (`raw_state` do slskd quando existe, senão `state`).
  final String? rawState;

  /// De 0 a 100.
  final double progress;

  /// Bytes por segundo.
  final double speed;
  final String? message;
  final int? bytesTransferred;
  final int? totalBytes;

  /// Usuário do Soulseek de quem se baixa (só no formato slskd).
  final String? username;

  /// Terminou, com sucesso ou não.
  bool get isFinished => state == DownloadState.completed || state == DownloadState.failed;
}

// ---------------------------------------------------------------------------
// Letras
// ---------------------------------------------------------------------------

/// Como a letra está sincronizada.
enum LyricsSyncType {
  /// por sílaba (Apple Music)
  syllable,

  /// por palavra (LRC "enhanced")
  word,

  /// por linha
  line,

  /// sem tempos, só texto
  none,
  unknown;

  static LyricsSyncType parse(String? raw) {
    switch (raw) {
      case 'syllable':
        return syllable;
      case 'word':
        return word;
      case 'line':
        return line;
      case 'none':
        return none;
      default:
        return unknown;
    }
  }
}

/// Palavra ou sílaba de uma linha (tempos em segundos).
@immutable
class LyricSegment {
  const LyricSegment({required this.text, required this.startTime, required this.endTime});

  factory LyricSegment.fromJson(Json json) => LyricSegment(
        text: asString(json['text']) ?? '',
        startTime: asDouble(json['startTime']) ?? 0,
        endTime: asDouble(json['endTime']) ?? 0,
      );

  final String text;
  final double startTime;
  final double endTime;
}

/// Linha da letra (tempos em segundos).
@immutable
class LyricLine {
  const LyricLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.segments = const [],
  });

  factory LyricLine.fromJson(Json json) => LyricLine(
        text: asString(json['text']) ?? '',
        startTime: asDouble(json['startTime']) ?? 0,
        endTime: asDouble(json['endTime']) ?? 0,
        segments: parseList(json['segments'], LyricSegment.fromJson),
      );

  final String text;
  final double startTime;
  final double endTime;

  /// Vazio quando a sincronização é só por linha.
  final List<LyricSegment> segments;

  bool get hasSegments => segments.isNotEmpty;
}

/// Resposta de `GET /lyrics/synced`.
@immutable
class SyncedLyrics {
  const SyncedLyrics({
    required this.source,
    required this.syncType,
    this.rawSyncType = '',
    this.plainText = '',
    this.language,
    this.lines = const [],
  });

  factory SyncedLyrics.fromJson(Json json) {
    final raw = asString(json['syncType']);
    return SyncedLyrics(
      source: asString(json['source']) ?? '',
      syncType: LyricsSyncType.parse(raw),
      rawSyncType: raw ?? '',
      plainText: asString(json['plainText']) ?? '',
      language: asString(json['language']),
      lines: parseList(json['lines'], LyricLine.fromJson),
    );
  }

  /// `apple_music`, `lrclib`, `musixmatch_enhanced`, `syncedlyrics`...
  final String source;
  final LyricsSyncType syncType;

  /// Texto original de `syncType`.
  final String rawSyncType;
  final String plainText;
  final String? language;
  final List<LyricLine> lines;

  /// Tem tempos por linha ou por palavra/sílaba.
  bool get isSynced =>
      lines.isNotEmpty &&
      (syncType == LyricsSyncType.line ||
          syncType == LyricsSyncType.word ||
          syncType == LyricsSyncType.syllable);

  /// Índice da linha que está tocando em [seconds], ou -1 antes da primeira.
  /// Assume [lines] em ordem de tempo.
  int lineIndexAt(double seconds) {
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startTime <= seconds) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }
}

/// Resposta de `GET /lyrics/plain`: o objeto do LRCLIB, repassado como veio.
@immutable
class PlainLyrics {
  const PlainLyrics({
    this.id,
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory PlainLyrics.fromJson(Json json) => PlainLyrics(
        id: asInt(json['id']),
        trackName: asString(json['trackName']) ?? asString(json['name']),
        artistName: asString(json['artistName']),
        albumName: asString(json['albumName']),
        duration: asDouble(json['duration']),
        instrumental: asBool(json['instrumental']),
        plainLyrics: asString(json['plainLyrics']),
        syncedLyrics: asString(json['syncedLyrics']),
      );

  final int? id;
  final String? trackName;
  final String? artistName;
  final String? albumName;

  /// Segundos.
  final double? duration;
  final bool instrumental;
  final String? plainLyrics;

  /// Letra em formato LRC (`[mm:ss.xx] texto`), quando o LRCLIB tem.
  final String? syncedLyrics;

  bool get hasText => plainLyrics != null || syncedLyrics != null;
}

// ---------------------------------------------------------------------------
// Versão do app
// ---------------------------------------------------------------------------

/// Link de download de uma plataforma em `/app/latest_version`.
@immutable
class PlatformRelease {
  const PlatformRelease({this.url, this.portableUrl});

  factory PlatformRelease.fromJson(Json json) => PlatformRelease(
        url: asString(json['url']),
        portableUrl: asString(json['portable_url']),
      );

  final String? url;

  /// Só no Windows (zip sem instalador).
  final String? portableUrl;
}

/// Resposta de `GET /app/latest_version` (o conteúdo de `updates.json`).
/// Sem arquivo de configuração, o servidor devolve só `{"latest_version": "0.0.0"}`.
@immutable
class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    this.releaseNotes,
    this.platforms = const {},
  });

  factory AppVersionInfo.fromJson(Json json) {
    final platformsJson = asJson(json['platforms']);
    return AppVersionInfo(
      latestVersion: asString(json['latest_version']) ?? '0.0.0',
      releaseNotes: asString(json['release_notes_pt']),
      platforms: {
        for (final e in platformsJson.entries)
          e.key: PlatformRelease.fromJson(asJson(e.value)),
      },
    );
  }

  final String latestVersion;
  final String? releaseNotes;

  /// Por chave de plataforma: `android`, `windows`, `macos`.
  final Map<String, PlatformRelease> platforms;
}
