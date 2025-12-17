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
    try {
      // Escuta mudanças de estado do player
      _player.playbackEventStream.listen(
        _broadcastState,
        onError: (e) => print('❌ Erro no playbackEventStream: $e'),
      );
      
      // Escuta mudanças de posição
      _player.positionStream.listen(
        (position) {
          playbackState.add(playbackState.value.copyWith(
            updatePosition: position,
          ));
        },
        onError: (e) => print('❌ Erro no positionStream: $e'),
      );
      
      // Escuta quando a música atual muda
      _player.currentIndexStream.listen(
        (index) {
          if (index != null && index < _mediaQueue.length) {
            _logSessionAndReset();
            _currentIndex = index;
            mediaItem.add(_mediaQueue[index]);
          }
        },
        onError: (e) => print('❌ Erro no currentIndexStream: $e'),
      );
      
      // Escuta quando termina uma música
      _player.processingStateStream.listen(
        (state) {
          if (state == ProcessingState.completed) {
            print('✅ Música completou. Index: $_currentIndex, Total: ${_mediaQueue.length}');
            // Verifica se há próxima usando nossa própria lógica
            if (_currentIndex < _mediaQueue.length - 1) {
              print('▶️ Avançando para próxima música...');
              skipToNext();
            } else {
              print('🎵 Fim da fila');
              // Fim da fila - pode parar ou fazer loop
              final loopMode = _player.loopMode;
              if (loopMode == LoopMode.all && _mediaQueue.isNotEmpty) {
                // Loop de toda a fila: volta para o início
                skipToQueueItem(0);
                play();
              } else {
                stop();
              }
            }
          }
        },
        onError: (e) => print('❌ Erro no processingStateStream: $e'),
      );
      
      print('✅ OrfeuAudioHandler._init() completo');
    } catch (e, stack) {
      print('❌ Erro em _init(): $e');
      print('Stack: $stack');
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    
    // Controla timer de sessão
    if (playing) {
      _sessionTimer.start();
    } else {
      _sessionTimer.stop();
    }
    
    // Verifica se pode ir para próxima/anterior
    final hasNext = _currentIndex < _mediaQueue.length - 1;
    final hasPrevious = _currentIndex > 0;
    
    playbackState.add(playbackState.value.copyWith(
      controls: [
        // Controles na notificação expandida
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      // Índices dos botões na notificação compacta: [prev, play/pause, next]
      androidCompactActionIndices: const [0, 1, 2],
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
    print('🎵 skipToNext chamado. Index atual: $_currentIndex, Total: ${_mediaQueue.length}');
    if (_currentIndex < _mediaQueue.length - 1) {
      _currentIndex++;
      try {
        // Para o player para garantir reset do estado
        await _player.pause();
        // Seek para o novo índice
        await _player.seek(Duration.zero, index: _currentIndex);
        // Atualiza o mediaItem
        mediaItem.add(_mediaQueue[_currentIndex]);
        // Emite novo estado
        _broadcastState(_player.playbackEvent);
        // Retoma a reprodução
        await _player.play();
        print('⏭️ Skip para: ${_mediaQueue[_currentIndex].title} (index: $_currentIndex)');
      } catch (e) {
        print('❌ Erro no skipToNext: $e');
      }
    } else {
      print('⚠️ Já está na última música da fila');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    print('🎵 skipToPrevious chamado. Index atual: $_currentIndex, Posição: ${_player.position.inSeconds}s');
    // Se está no começo da música (< 3s), volta para anterior
    // Senão, volta ao início da música atual
    if (_player.position.inSeconds < 3 && _currentIndex > 0) {
      _currentIndex--;
      try {
        await _player.pause();
        await _player.seek(Duration.zero, index: _currentIndex);
        mediaItem.add(_mediaQueue[_currentIndex]);
        _broadcastState(_player.playbackEvent);
        await _player.play();
        print('⏮️ Skip para: ${_mediaQueue[_currentIndex].title} (index: $_currentIndex)');
      } catch (e) {
        print('❌ Erro no skipToPrevious: $e');
      }
    } else {
      await _player.seek(Duration.zero);
      print('🔄 Voltou ao início da música atual');
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    print('🎵 skipToQueueItem: $index (total: ${_mediaQueue.length})');
    if (index < 0 || index >= _mediaQueue.length) {
      print('⚠️ Índice inválido para skipToQueueItem');
      return;
    }
    _currentIndex = index;
    try {
      await _player.pause();
      await _player.seek(Duration.zero, index: index);
      mediaItem.add(_mediaQueue[index]);
      _broadcastState(_player.playbackEvent);
      await _player.play();
      print('✅ Pulou para: ${_mediaQueue[index].title}');
    } catch (e) {
      print('❌ Erro em skipToQueueItem: $e');
    }
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
    try {
      // Filtra tracks válidas
      final validTracks = tracks.where((t) => t['filename'] != null).toList();
      if (validTracks.isEmpty) {
        print('⚠️ playQueue: Nenhuma track válida');
        return;
      }

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
      
      // Extrai duração em milissegundos (se disponível)
      Duration? duration;
      final durationValue = track['duration'] ?? track['durationSeconds'];
      if (durationValue != null) {
        if (durationValue is int) {
          duration = Duration(seconds: durationValue);
        } else if (durationValue is double) {
          duration = Duration(seconds: durationValue.toInt());
        }
      }
      
      return MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: artUri != null ? Uri.parse(artUri) : null,
        extras: {'filename': filename, 'tidalId': track['tidalId']},
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
    } catch (e, stack) {
      print('❌ Erro em playQueue: $e');
      print('Stack: $stack');
    }
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
      final albumId = trackData?['collectionId']?.toString() ?? trackData?['album_id']?.toString();
      final genre = trackData?['genre']?.toString();
      
      if (filename != null && _ref != null) {
        _ref!.read(libraryControllerProvider).logPlay(
          filename, 
          seconds,
          albumId: albumId,
          genre: genre,
        );
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
  try {
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
  } catch (e, stack) {
    print('❌ Erro ao inicializar AudioService.init: $e');
    print('Stack: $stack');
    // Cria um handler básico sem configuração avançada
    _audioHandler = OrfeuAudioHandler(ref: ref);
    return _audioHandler!;
  }
}
