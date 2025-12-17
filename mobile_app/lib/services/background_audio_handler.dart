import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

/// Handler de áudio para reprodução em segundo plano.
/// Integra just_audio com audio_service para controles de mídia do sistema.
class OrfeuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final Ref? _ref;
  
  // Estado da fila
  List<MediaItem> _mediaQueue = [];
  int _currentIndex = 0;
  String _currentQuality = 'lossless';
  
  // Timer para log de sessão
  final Stopwatch _sessionTimer = Stopwatch();
  
  // Mapa para guardar dados extras das tracks (filename, tidalId, etc.)
  final Map<String, Map<String, dynamic>> _trackDataMap = {};

  OrfeuAudioHandler({Ref? ref}) : _ref = ref {
    _init();
  }

  void _init() {
    // Escuta mudanças de estado do player
    _player.playbackEventStream.listen(_broadcastState);
    
    // Escuta mudanças de posição
    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    });
    
    // Escuta quando a música atual muda
    _player.currentIndexStream.listen((index) {
      if (index != null && index < _mediaQueue.length) {
        _logSessionAndReset();
        _currentIndex = index;
        mediaItem.add(_mediaQueue[index]);
      }
    });
    
    // Escuta quando termina uma música
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_player.hasNext) {
          skipToNext();
        } else {
          // Fim da fila
          stop();
        }
      }
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    
    // Controla timer de sessão
    if (playing) {
      _sessionTimer.start();
    } else {
      _sessionTimer.stop();
    }
    
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
  }

  // ============ AÇÕES DE CONTROLE ============

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _logSessionAndReset();
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    // Se está no começo da música (< 3s), volta para anterior
    // Senão, volta ao início da música atual
    if (_player.position.inSeconds < 3 && _player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _mediaQueue.length) return;
    _currentIndex = index;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = {
      AudioServiceRepeatMode.none: LoopMode.off,
      AudioServiceRepeatMode.one: LoopMode.one,
      AudioServiceRepeatMode.all: LoopMode.all,
      AudioServiceRepeatMode.group: LoopMode.all,
    }[repeatMode]!;
    
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  // ============ MÉTODOS CUSTOMIZADOS ============

  /// Carrega uma nova fila de músicas e começa a tocar
  Future<void> playQueue({
    required List<Map<String, dynamic>> tracks,
    required int initialIndex,
    bool shuffle = false,
  }) async {
    // Filtra tracks válidas
    final validTracks = tracks.where((t) => t['filename'] != null).toList();
    if (validTracks.isEmpty) return;

    // Converte para MediaItem
    _mediaQueue = validTracks.map((track) {
      final filename = track['filename'] as String;
      final id = track['tidalId']?.toString() ?? filename;
      
      // Guarda dados extras
      _trackDataMap[id] = track;
      
      final title = track['title'] ?? 
                    track['display_name'] ?? 
                    track['trackName'] ?? 
                    'Música';
      final artist = track['artist'] ?? 
                     track['artistName'] ?? 
                     'Artista';
      final album = track['album'] ?? 
                    track['collectionName'] ?? 
                    'Álbum';
      
      String? artUri = track['imageUrl'] ?? track['artworkUrl'];
      if ((artUri == null || artUri.isEmpty) && track['filename'] != null) {
        final encoded = Uri.encodeComponent(track['filename']);
        artUri = '$baseUrl/cover?filename=$encoded';
      }
      
      return MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artUri: artUri != null ? Uri.parse(artUri) : null,
        extras: {'filename': filename},
      );
    }).toList();

    // Atualiza a fila no audio_service
    queue.add(_mediaQueue);
    
    // Prepara a playlist no just_audio
    final playlist = ConcatenatingAudioSource(
      children: validTracks.map((track) {
        final filename = Uri.encodeComponent(track['filename'] ?? '');
        final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
        return AudioSource.uri(Uri.parse(url));
      }).toList(),
    );

    await _player.setAudioSource(playlist, initialIndex: initialIndex);
    _currentIndex = initialIndex;
    
    if (shuffle) {
      await _player.setShuffleModeEnabled(true);
      playbackState.add(playbackState.value.copyWith(
        shuffleMode: AudioServiceShuffleMode.all,
      ));
    }

    // Emite o item atual
    if (_mediaQueue.isNotEmpty) {
      mediaItem.add(_mediaQueue[initialIndex]);
    }

    play();
  }

  /// Obtém dados extras da track atual (para integração com UI)
  Map<String, dynamic>? getCurrentTrackData() {
    final current = mediaItem.value;
    if (current == null) return null;
    return _trackDataMap[current.id];
  }

  /// Obtém a fila atual como lista de Maps
  List<Map<String, dynamic>> getQueueData() {
    return _mediaQueue.map((item) {
      return _trackDataMap[item.id] ?? {
        'title': item.title,
        'artist': item.artist,
        'album': item.album,
      };
    }).toList();
  }

  /// Altera a qualidade do stream
  Future<void> changeQuality(String quality) async {
    if (_currentQuality == quality) return;
    _currentQuality = quality;
    
    final currentPos = _player.position;
    final tracks = getQueueData();
    
    if (tracks.isNotEmpty) {
      await playQueue(tracks: tracks, initialIndex: _currentIndex);
      await seek(currentPos);
    }
  }

  String get currentQuality => _currentQuality;
  int get currentIndex => _currentIndex;
  List<MediaItem> get currentQueue => _mediaQueue;
  AudioPlayer get player => _player;

  /// Log da sessão de escuta
  void _logSessionAndReset() {
    final current = mediaItem.value;
    if (current != null && _sessionTimer.elapsed.inSeconds > 10) {
      final trackData = _trackDataMap[current.id];
      final filename = trackData?['filename'] ?? current.extras?['filename'];
      final seconds = _sessionTimer.elapsed.inSeconds;
      
      if (filename != null && _ref != null) {
        _ref!.read(libraryControllerProvider).logPlay(filename, seconds);
      }
    }
    _sessionTimer.reset();
    if (_player.playing) _sessionTimer.start();
  }
}

// Singleton do handler (inicializado no main.dart)
OrfeuAudioHandler? _audioHandler;

OrfeuAudioHandler get audioHandler {
  if (_audioHandler == null) {
    throw StateError('AudioHandler não foi inicializado. Chame initAudioService() primeiro.');
  }
  return _audioHandler!;
}

/// Inicializa o serviço de áudio (chamar no main.dart)
Future<OrfeuAudioHandler> initAudioService({Ref? ref}) async {
  _audioHandler = await AudioService.init(
    builder: () => OrfeuAudioHandler(ref: ref),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.ocnaibill.orfeu.audio',
      androidNotificationChannelName: 'Orfeu Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
      // Mostra controles na tela de bloqueio
      androidShowNotificationBadge: true,
      // Metadados para controles do sistema
      artDownscaleWidth: 300,
      artDownscaleHeight: 300,
    ),
  );
  return _audioHandler!;
}
