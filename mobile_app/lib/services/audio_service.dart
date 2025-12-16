import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import '../providers.dart';
import 'discord_service.dart';

// --- ESTADO DO PLAYER ---
class PlayerState {
  final bool isPlaying;
  final Map<String, dynamic>? currentTrack;
  final Duration position;
  final Duration duration;
  final bool isBuffering;

  PlayerState({
    this.isPlaying = false,
    this.currentTrack,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isBuffering = false,
  });

  PlayerState copyWith({
    bool? isPlaying,
    Map<String, dynamic>? currentTrack,
    Duration? position,
    Duration? duration,
    bool? isBuffering,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isBuffering: isBuffering ?? this.isBuffering,
    );
  }
}

// --- NOTIFIER DO PLAYER ---
class AudioPlayerNotifier extends StateNotifier<PlayerState> {
  final Ref ref;
  late AudioPlayer _audioPlayer;
  final DiscordService _discord = DiscordService();
  final Stopwatch _sessionTimer = Stopwatch();

  List<Map<String, dynamic>> _queue = [];
  int _currentIndex = 0;
  String _currentQuality = 'lossless';

  AudioPlayerNotifier(this.ref) : super(PlayerState()) {
    _init();
  }

  void _init() {
    _audioPlayer = AudioPlayer();
    _discord.init();

    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      state = state.copyWith(
        isPlaying: isPlaying,
        isBuffering: processingState == ProcessingState.buffering ||
            processingState == ProcessingState.loading,
      );

      if (isPlaying) {
        _sessionTimer.start();
      } else {
        _sessionTimer.stop();
      }

      _updateDiscord();
    });

    _audioPlayer.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    _audioPlayer.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index < _queue.length && _currentIndex != index) {
        _logSessionAndReset();
        _currentIndex = index;
        _updateCurrentTrack();
      }
    });
  }

  // --- AÇÕES ---

  Future<void> playContext({
    required List<Map<String, dynamic>> queue,
    required int initialIndex,
    bool shuffle = false,
  }) async {
    if (_queue.isNotEmpty &&
        _currentIndex < _queue.length &&
        queue.isNotEmpty &&
        initialIndex < queue.length &&
        _queue[_currentIndex]['filename'] == queue[initialIndex]['filename'] &&
        state.isPlaying) {
      return;
    }

    _queue = List.from(queue);
    _currentIndex = initialIndex;

    final validItems = _queue.where((i) => i['filename'] != null).toList();
    if (validItems.isEmpty) return;

    final targetTrack = validItems[initialIndex];
    state = state.copyWith(
      currentTrack: targetTrack,
      isBuffering: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _updateDiscord();

    try {
      final playlist = ConcatenatingAudioSource(
        children: validItems.map((item) {
          final filename = Uri.encodeComponent(item['filename'] ?? '');
          final url =
              '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
          return AudioSource.uri(Uri.parse(url), tag: item);
        }).toList(),
      );

      await _audioPlayer.setAudioSource(playlist, initialIndex: initialIndex);

      if (shuffle) {
        await _audioPlayer.setShuffleModeEnabled(true);
      } else {
        await _audioPlayer.setShuffleModeEnabled(false);
      }

      _audioPlayer.play();
    } catch (e) {
      print("❌ Erro no AudioService: $e");
      state = state.copyWith(isBuffering: false, isPlaying: false);
    }
  }

  void togglePlay() {
    if (state.isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void next() => _audioPlayer.hasNext ? _audioPlayer.seekToNext() : null;
  void previous() =>
      _audioPlayer.hasPrevious ? _audioPlayer.seekToPrevious() : null;
  void seek(Duration pos) => _audioPlayer.seek(pos);

  Future<void> changeQuality(String quality) async {
    if (_currentQuality == quality) return;
    _currentQuality = quality;

    final currentPos = state.position;
    final currentIndex = _audioPlayer.currentIndex ?? 0;

    await playContext(queue: _queue, initialIndex: currentIndex);
    await _audioPlayer.seek(currentPos);
  }

  String get currentQuality => _currentQuality;

  // --- INTERNOS ---

  void _updateCurrentTrack() {
    if (_currentIndex < _queue.length) {
      final track = _queue[_currentIndex];
      state = state.copyWith(currentTrack: track);
      _updateDiscord();
    }
  }

  void _logSessionAndReset() {
    final track = state.currentTrack;
    if (track != null && _sessionTimer.elapsed.inSeconds > 10) {
      final filename = track['filename'];
      final seconds = _sessionTimer.elapsed.inSeconds;
      ref.read(libraryControllerProvider).logPlay(filename, seconds);
    }
    _sessionTimer.reset();
    if (state.isPlaying) _sessionTimer.start();
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

    // CORREÇÃO: Verifica também se a string está vazia, não só null
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

  @override
  void dispose() {
    _logSessionAndReset();
    _discord.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<AudioPlayerNotifier, PlayerState>((ref) {
  return AudioPlayerNotifier(ref);
});
