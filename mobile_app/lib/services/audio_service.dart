import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers.dart';
import 'discord_service.dart';
import 'background_audio_handler.dart';

// --- MODO DE LOOP ---
enum LoopMode { off, one, all }

// --- ESTADO DO PLAYER ---
class PlayerState {
  final bool isPlaying;
  final Map<String, dynamic>? currentTrack;
  final Duration position;
  final Duration duration;
  final bool isBuffering;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final List<Map<String, dynamic>> queue;
  final int currentIndex;

  PlayerState({
    this.isPlaying = false,
    this.currentTrack,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isBuffering = false,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.off,
    this.queue = const [],
    this.currentIndex = 0,
  });

  PlayerState copyWith({
    bool? isPlaying,
    Map<String, dynamic>? currentTrack,
    Duration? position,
    Duration? duration,
    bool? isBuffering,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    List<Map<String, dynamic>>? queue,
    int? currentIndex,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isBuffering: isBuffering ?? this.isBuffering,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  bool get hasNext => currentIndex < queue.length - 1;
  bool get hasPrevious => currentIndex > 0;
}

// --- NOTIFIER DO PLAYER ---
class AudioPlayerNotifier extends StateNotifier<PlayerState> {
  final Ref ref;
  final DiscordService _discord = DiscordService();

  // Fila original (sem shuffle) para restaurar ordem
  List<Map<String, dynamic>> _originalQueue = [];

  // Tracking para histórico de reprodução
  String? _lastTrackedFilename;
  int _currentTrackPlayedSeconds = 0;
  bool _historyLoggedForCurrentTrack = false;
  static const int _historyThresholdSeconds =
      30; // Registra após 30s de reprodução

  StreamSubscription? _playbackSubscription;
  StreamSubscription? _mediaItemSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  Timer? _historyTrackingTimer;

  AudioPlayerNotifier(this.ref) : super(PlayerState()) {
    _init();
  }

  void _init() {
    _discord.init();
    _startHistoryTracking();
    
    // Configura o ref no audioHandler para permitir downloads sob demanda
    audioHandler.setRef(ref);

    // Escuta mudanças do estado de playback
    _playbackSubscription = audioHandler.playbackState.listen((playbackState) {
      final isPlaying = playbackState.playing;
      final processingState = playbackState.processingState;

      state = state.copyWith(
        isPlaying: isPlaying,
        isBuffering: processingState == AudioProcessingState.buffering ||
            processingState == AudioProcessingState.loading,
        position: playbackState.position,
        currentIndex: playbackState.queueIndex ?? state.currentIndex,
      );

      _updateDiscord();
    });

    // Escuta mudanças do item de mídia atual
    _mediaItemSubscription = audioHandler.mediaItem.listen((mediaItem) {
      if (mediaItem != null) {
        final trackData = audioHandler.getCurrentTrackData();
        if (trackData != null) {
          state = state.copyWith(
            currentTrack: trackData,
            duration: mediaItem.duration ?? Duration.zero,
          );
          _updateDiscord();
        }
      }
    });

    // Escuta posição via stream do player interno
    // Importante: Assume que audioHandler expõe 'player' (JustAudio player) publicamente
    _positionSubscription = audioHandler.player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    // Escuta duração
    _durationSubscription = audioHandler.player.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });
  }

  // --- AÇÕES PÚBLICAS ---

  /// Toca uma fila de músicas
  Future<void> playContext({
    required List<Map<String, dynamic>> queue,
    required int initialIndex,
    bool shuffle = false,
  }) async {
    // Verifica se já está tocando a mesma música
    if (_originalQueue.isNotEmpty &&
        initialIndex < queue.length &&
        state.currentTrack != null &&
        state.currentIndex < _originalQueue.length &&
        _originalQueue[state.currentIndex]['filename'] ==
            queue[initialIndex]['filename'] &&
        state.isPlaying) {
      return;
    }

    // Guarda fila original
    _originalQueue = List.from(queue);

    List<Map<String, dynamic>> playQueue;
    int playIndex = initialIndex;

    if (shuffle) {
      // Embaralha mantendo a música selecionada no início
      playQueue = _shuffleWithFirst(queue, initialIndex);
      playIndex = 0;
    } else {
      playQueue = List.from(queue);
    }

    // --- CORREÇÃO OTIMISTA ---
    // Define os metadados e duração IMEDIATAMENTE para a UI não ficar zerada
    final targetTrack = playQueue[playIndex];
    Duration initialDuration = Duration.zero;

    // Tenta extrair duração dos metadados
    final rawDur = targetTrack['durationMs'] ??
        targetTrack['duration'] ??
        targetTrack['duration_ms'];
    if (rawDur != null) {
      if (rawDur is int) {
        // Verifica se está em ms ou segundos (heurística)
        initialDuration = (rawDur < 30000)
            ? Duration(seconds: rawDur)
            : Duration(milliseconds: rawDur);
      } else if (rawDur is double) {
        initialDuration = Duration(milliseconds: rawDur.toInt());
      } else if (rawDur is String) {
        initialDuration = Duration(milliseconds: int.tryParse(rawDur) ?? 0);
      }
    }

    // Atualiza estado local imediatamente
    state = state.copyWith(
      currentTrack: targetTrack,
      duration: initialDuration, // Seta duração inicial
      queue: playQueue,
      currentIndex: playIndex,
      isShuffleEnabled: shuffle,
      isBuffering: true,
      position: Duration.zero,
    );
    _updateDiscord(); // Atualiza Discord com os novos dados

    // Envia para o audio handler (Background)
    await audioHandler.playQueue(
      tracks: playQueue,
      initialIndex: playIndex,
      shuffle: false, // Já embaralhamos manualmente
    );
  }

  /// Toca uma música específica (cria fila de 1 item)
  Future<void> playSingle(Map<String, dynamic> track) async {
    await playContext(queue: [track], initialIndex: 0);
  }

  void togglePlay() {
    if (state.isPlaying) {
      audioHandler.pause();
    } else {
      audioHandler.play();
    }
  }

  void pause() => audioHandler.pause();
  void play() => audioHandler.play();

  void next() {
    if (state.loopMode == LoopMode.one) {
      // No modo loop one, next vai para próxima mesmo assim
      audioHandler.skipToNext();
    } else if (state.hasNext) {
      audioHandler.skipToNext();
    } else if (state.loopMode == LoopMode.all && state.queue.isNotEmpty) {
      // Volta ao início da fila
      audioHandler.skipToQueueItem(0);
    }
  }

  void previous() {
    // Se está no começo da música (< 3s), volta para anterior
    if (state.position.inSeconds < 3 && state.hasPrevious) {
      audioHandler.skipToPrevious();
    } else if (state.position.inSeconds < 3 && state.loopMode == LoopMode.all) {
      // Vai para última música se loop all
      audioHandler.skipToQueueItem(state.queue.length - 1);
    } else {
      // Volta ao início da música atual
      seek(Duration.zero);
    }
  }

  void seek(Duration pos) => audioHandler.seek(pos);

  /// Pula para uma música específica na fila
  void skipToIndex(int index) {
    if (index >= 0 && index < state.queue.length) {
      audioHandler.skipToQueueItem(index);
      state = state.copyWith(currentIndex: index);
    }
  }

  /// Alterna shuffle
  void toggleShuffle() {
    final newShuffleState = !state.isShuffleEnabled;

    if (newShuffleState) {
      // Ativa shuffle - embaralha a fila mantendo a atual no início
      final currentTrack = state.currentTrack;
      final currentIndex = state.queue
          .indexWhere((t) => t['filename'] == currentTrack?['filename']);

      if (currentIndex >= 0) {
        final shuffled = _shuffleWithFirst(state.queue, currentIndex);
        state = state.copyWith(
          queue: shuffled,
          currentIndex: 0,
          isShuffleEnabled: true,
        );
        // Recarrega a fila no handler
        audioHandler.playQueue(tracks: shuffled, initialIndex: 0);
      }
    } else {
      // Desativa shuffle - restaura ordem original
      final currentTrack = state.currentTrack;
      final originalIndex = _originalQueue
          .indexWhere((t) => t['filename'] == currentTrack?['filename']);

      state = state.copyWith(
        queue: List.from(_originalQueue),
        currentIndex: originalIndex >= 0 ? originalIndex : 0,
        isShuffleEnabled: false,
      );
      // Recarrega a fila no handler
      audioHandler.playQueue(
        tracks: _originalQueue,
        initialIndex: originalIndex >= 0 ? originalIndex : 0,
      );
    }
  }

  /// Alterna modo de loop
  void toggleLoop() {
    final modes = LoopMode.values;
    final currentIdx = modes.indexOf(state.loopMode);
    final nextMode = modes[(currentIdx + 1) % modes.length];

    state = state.copyWith(loopMode: nextMode);

    // Configura no audio handler
    final audioServiceMode = {
      LoopMode.off: AudioServiceRepeatMode.none,
      LoopMode.one: AudioServiceRepeatMode.one,
      LoopMode.all: AudioServiceRepeatMode.all,
    }[nextMode]!;

    audioHandler.setRepeatMode(audioServiceMode);
  }

  /// Adiciona uma música à fila
  void addToQueue(Map<String, dynamic> track) {
    final newQueue = [...state.queue, track];
    _originalQueue.add(track);
    state = state.copyWith(queue: newQueue);
  }

  /// Remove uma música da fila
  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return; // Não remove a atual

    final newQueue = List<Map<String, dynamic>>.from(state.queue);
    newQueue.removeAt(index);

    var newCurrentIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newCurrentIndex--;
    }

    state = state.copyWith(queue: newQueue, currentIndex: newCurrentIndex);
  }

  /// Atualiza o filename de uma track na fila após download
  Future<void> updateQueueTrackFilename(int index, String filename) async {
    if (index < 0 || index >= state.queue.length) return;
    
    // Atualiza no estado local
    final newQueue = List<Map<String, dynamic>>.from(state.queue);
    newQueue[index] = Map<String, dynamic>.from(newQueue[index]);
    newQueue[index]['filename'] = filename;
    state = state.copyWith(queue: newQueue);
    
    // Atualiza na fila original também
    if (index < _originalQueue.length) {
      _originalQueue[index] = Map<String, dynamic>.from(_originalQueue[index]);
      _originalQueue[index]['filename'] = filename;
    }
    
    // Atualiza no audio handler (reconstrói playlist se necessário)
    await audioHandler.updateTrackFilename(index, filename);
  }

  Future<void> changeQuality(String quality) async {
    await audioHandler.changeQuality(quality);
  }

  String get currentQuality => audioHandler.currentQuality;

  // --- INTERNOS ---

  /// Embaralha uma lista mantendo um item específico no início
  List<Map<String, dynamic>> _shuffleWithFirst(
    List<Map<String, dynamic>> list,
    int firstIndex,
  ) {
    final result = List<Map<String, dynamic>>.from(list);
    final first = result.removeAt(firstIndex);
    result.shuffle(Random());
    return [first, ...result];
  }

  void _updateDiscord() {
    final track = state.currentTrack;
    if (track == null) return;

    final title = track['title'] ??
        track['display_name'] ??
        track['trackName'] ??
        'Música';
    final artist = track['artist'] ?? track['artistName'] ?? 'Artista';
    final album = track['album'] ?? track['collectionName'] ?? 'Álbum';

    String? coverUrl = track['imageUrl'] ?? track['artworkUrl'];

    if ((coverUrl == null || coverUrl.isEmpty) && track['filename'] != null) {
      final encoded = Uri.encodeComponent(track['filename']);
      coverUrl = '$baseUrl/cover?filename=$encoded';
    }

    _discord.updateActivity(
      track: title,
      artist: artist,
      album: album,
      duration: state.duration,
      position: state.position,
      isPlaying: state.isPlaying,
      coverUrl: coverUrl,
    );
  }

  // --- TRACKING DE HISTÓRICO ---

  void _startHistoryTracking() {
    // Timer que roda a cada segundo enquanto está tocando
    _historyTrackingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _trackPlaybackProgress();
    });
  }

  void _trackPlaybackProgress() {
    final track = state.currentTrack;
    if (track == null) return;

    final currentFilename = track['filename'] as String?;
    if (currentFilename == null) return;

    // Detecta mudança de música
    if (currentFilename != _lastTrackedFilename) {
      _lastTrackedFilename = currentFilename;
      _currentTrackPlayedSeconds = 0;
      _historyLoggedForCurrentTrack = false;
    }

    // Só conta se estiver tocando
    if (state.isPlaying && !_historyLoggedForCurrentTrack) {
      _currentTrackPlayedSeconds++;

      // Registra no histórico após o threshold
      if (_currentTrackPlayedSeconds >= _historyThresholdSeconds) {
        _logToHistory(track, _currentTrackPlayedSeconds);
        _historyLoggedForCurrentTrack = true;
      }
    }
  }

  Future<void> _logToHistory(
      Map<String, dynamic> track, int durationListened) async {
    try {
      final authState = ref.read(authProvider);
      if (authState.token == null) return;
      final token = authState.token;

      final filename = track['filename'] as String?;
      if (filename == null) return;

      // Extrai album_id se disponível (pode ser collectionId, albumId, etc.)
      final albumId = track['collectionId']?.toString() ??
          track['albumId']?.toString() ??
          track['album_id']?.toString();

      // Extrai metadados do catálogo (mais confiáveis que tags do arquivo)
      final catalogTitle = track['title']?.toString() ?? track['trackName']?.toString();
      final catalogArtist = track['artist']?.toString() ?? track['artistName']?.toString();
      final catalogAlbum = track['album']?.toString() ?? track['collectionName']?.toString();
      final genre = track['genre']?.toString();

      final response = await http.post(
        Uri.parse('$baseUrl/users/me/history'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'filename': filename,
          'duration_listened': durationListened,
          if (albumId != null) 'album_id': albumId,
          if (catalogTitle != null) 'catalog_title': catalogTitle,
          if (catalogArtist != null) 'catalog_artist': catalogArtist,
          if (catalogAlbum != null) 'catalog_album': catalogAlbum,
          if (genre != null) 'genre': genre,
        }),
      );

      if (response.statusCode == 200) {
        print(
            '📊 Histórico registrado: ${track['title']} ($durationListened s)');
      }
    } catch (e) {
      print('⚠️ Erro ao registrar histórico: $e');
    }
  }

  @override
  void dispose() {
    _playbackSubscription?.cancel();
    _mediaItemSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _historyTrackingTimer?.cancel();
    _discord.dispose();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<AudioPlayerNotifier, PlayerState>((ref) {
  return AudioPlayerNotifier(ref);
});
