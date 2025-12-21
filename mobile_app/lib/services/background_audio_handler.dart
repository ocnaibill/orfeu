import 'dart:async';
import 'dart:io' show Platform, File;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers.dart';

/// Handler de áudio para reprodução em segundo plano.
/// Integra just_audio com audio_service para controles de mídia do sistema.
class OrfeuAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  Ref? _ref;  // Mutável para permitir setRef() após inicialização
  
  // Estado da fila
  List<MediaItem> _mediaQueue = [];
  int _currentIndex = 0;
  String _currentQuality = 'lossless';
  
  // Fila virtual completa (inclui tracks sem filename)
  List<Map<String, dynamic>> _fullQueue = [];
  
  // Mapeamento: índice na _mediaQueue -> índice na playlist do just_audio
  // Se uma track não tem filename, seu valor será -1
  List<int> _playerIndexMap = [];
  
  // Timer para log de sessão
  final Stopwatch _sessionTimer = Stopwatch();
  
  // Mapa para guardar dados extras das tracks (filename, tidalId, etc.)
  final Map<String, Map<String, dynamic>> _trackDataMap = {};
  
  // Workaround para bug do just_audio_windows
  // Evita auto-advance indesejado e problemas de threading
  bool _isWindows = false;
  bool _isPlayerReady = false;
  DateTime? _lastSkipTime;
  static const _minSkipInterval = Duration(milliseconds: 500);

  OrfeuAudioHandler({Ref? ref}) : _ref = ref {
    // Detecta se é Windows para aplicar workarounds
    if (!kIsWeb) {
      try {
        _isWindows = Platform.isWindows;
      } catch (_) {
        _isWindows = false;
      }
    }
    _init();
  }
  
  /// Define o Ref para permitir downloads sob demanda
  void setRef(Ref ref) {
    _ref = ref;
    print('✅ Ref configurado no AudioHandler');
  }

  void _init() {
    try {
      if (_isWindows) {
        print('🪟 Windows detectado - aplicando workarounds para just_audio_windows');
      }
      
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
      
      // Escuta quando a música atual muda no player
      // Nota: o índice aqui é do player (just_audio), não da nossa _mediaQueue
      _player.currentIndexStream.listen(
        (playerIndex) {
          if (playerIndex != null) {
            _logSessionAndReset();
            // Encontra o índice correspondente na _mediaQueue
            final mediaIndex = _playerIndexMap.indexOf(playerIndex);
            if (mediaIndex >= 0 && mediaIndex < _mediaQueue.length) {
              _currentIndex = mediaIndex;
              mediaItem.add(_mediaQueue[mediaIndex]);
              // Pré-carrega a próxima música
              _preloadNextTrack();
            }
          }
        },
        onError: (e) => print('❌ Erro no currentIndexStream: $e'),
      );
      
      // Escuta quando termina uma música
      _player.processingStateStream.listen(
        (state) {
          // Marca quando o player está pronto para aceitar comandos
          if (state == ProcessingState.ready) {
            _isPlayerReady = true;
          } else if (state == ProcessingState.loading || state == ProcessingState.buffering) {
            _isPlayerReady = false;
          }
          
          if (state == ProcessingState.completed) {
            print('✅ Música completou. Index: $_currentIndex, Total: ${_mediaQueue.length}');
            
            // Workaround Windows: Verifica se não é um skip acidental
            if (_isWindows && _lastSkipTime != null) {
              final elapsed = DateTime.now().difference(_lastSkipTime!);
              if (elapsed < _minSkipInterval) {
                print('⚠️ Windows: Ignorando completed rápido demais (${elapsed.inMilliseconds}ms)');
                return;
              }
            }
            
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
  Future<void> play() async {
    if (_isWindows) {
      // Workaround Windows: Aguarda o player estar pronto antes de dar play
      if (!_isPlayerReady && _player.processingState == ProcessingState.loading) {
        print('🪟 Windows: Aguardando player ficar pronto...');
        // Aguarda até 3 segundos pelo player ficar pronto
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isPlayerReady || _player.processingState == ProcessingState.ready) {
            break;
          }
        }
      }
    }
    return _player.play();
  }

  @override
  Future<void> pause() async {
    if (_isWindows) {
      // Workaround Windows: Pequeno delay para evitar race conditions
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return _player.pause();
  }

  @override
  Future<void> stop() async {
    _logSessionAndReset();
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isWindows) {
      // Workaround Windows: Aguarda player estar pronto antes de seek
      if (_player.processingState == ProcessingState.loading) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    print('🎵 skipToNext chamado. Index atual: $_currentIndex, Total: ${_mediaQueue.length}');
    
    // Workaround Windows: Evita skips muito rápidos
    if (_isWindows) {
      final now = DateTime.now();
      if (_lastSkipTime != null && now.difference(_lastSkipTime!) < _minSkipInterval) {
        print('⚠️ Windows: Skip ignorado (muito rápido)');
        return;
      }
      _lastSkipTime = now;
    }
    
    if (_currentIndex >= _mediaQueue.length - 1) {
      print('⚠️ Já está na última música da fila');
      return;
    }
    
    final nextIndex = _currentIndex + 1;
    
    // Verifica se a próxima track tem filename
    if (_playerIndexMap[nextIndex] < 0) {
      // Não tem filename - precisa fazer download
      print('📥 Próxima track sem filename, iniciando download...');
      await _downloadAndPlayTrack(nextIndex);
      return;
    }
    
    // Tem filename - toca normalmente
    _currentIndex = nextIndex;
    final playerIndex = _playerIndexMap[nextIndex];
    
    try {
      await _player.pause();
      
      // Workaround Windows: Pequeno delay antes do seek
      if (_isWindows) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      await _player.seek(Duration.zero, index: playerIndex);
      mediaItem.add(_mediaQueue[_currentIndex]);
      _broadcastState(_player.playbackEvent);
      
      // Workaround Windows: Aguarda player estar pronto
      if (_isWindows) {
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_player.processingState == ProcessingState.ready) {
            break;
          }
        }
      }
      
      await _player.play();
      print('⏭️ Skip para: ${_mediaQueue[_currentIndex].title} (index: $_currentIndex, playerIndex: $playerIndex)');
      
      // Pré-carrega a próxima
      _preloadNextTrack();
    } catch (e) {
      print('❌ Erro no skipToNext: $e');
    }
  }
  
  /// Faz download de uma track e a reproduz
  Future<void> _downloadAndPlayTrack(int index) async {
    if (index < 0 || index >= _fullQueue.length) return;
    
    final track = _fullQueue[index];
    final trackKey = _getTrackKey(track);
    final trackName = track['trackName'] ?? track['title'] ?? 'Música';
    final artistName = track['artistName'] ?? track['artist'] ?? 'Artista';
    
    print('📥 Baixando: $trackName - $artistName (key: $trackKey)');
    
    // Verifica se já está em download
    if (_downloadsInProgress.contains(trackKey)) {
      print('⏳ Track já está sendo baixada, aguardando...');
      // Aguarda o download terminar em vez de iniciar outro
      while (_downloadsInProgress.contains(trackKey)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      // Verifica se o download foi bem sucedido
      final currentIndex = _findTrackIndexByKey(trackKey);
      if (currentIndex >= 0 && _fullQueue[currentIndex]['filename'] != null) {
        await _rebuildPlaylistAndPlay(currentIndex);
        return;
      }
    }
    
    // Atualiza UI para mostrar que está carregando
    _currentIndex = index;
    mediaItem.add(_mediaQueue[index]);
    
    // Emite estado de buffering
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      queueIndex: index,
    ));
    
    _downloadsInProgress.add(trackKey);
    
    try {
      // Usa o SearchController para fazer o download
      if (_ref != null) {
        final searchCtrl = _ref!.read(searchControllerProvider);
        final filename = await searchCtrl.smartDownload(track);
        
        if (filename != null) {
          print('✅ Download concluído: $filename');
          
          // IMPORTANTE: Encontra o índice atual da track pelo seu ID único
          final currentTrackIndex = _findTrackIndexByKey(trackKey);
          
          if (currentTrackIndex >= 0) {
            // Atualiza o filename na fila usando o índice correto
            _fullQueue[currentTrackIndex]['filename'] = filename;
            
            // Reconstrói a playlist com a nova track
            await _rebuildPlaylistAndPlay(currentTrackIndex);
          } else {
            print('⚠️ Track não encontrada na fila após download');
          }
        } else {
          print('❌ Download falhou, tentando próxima...');
          // Tenta a próxima música
          if (index + 1 < _mediaQueue.length) {
            await _downloadAndPlayTrack(index + 1);
          } else {
            // Sem mais músicas, para
            playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.idle,
            ));
          }
        }
      }
    } catch (e) {
      print('❌ Erro no download: $e');
      // Tenta a próxima música
      if (index + 1 < _mediaQueue.length) {
        await _downloadAndPlayTrack(index + 1);
      }
    } finally {
      _downloadsInProgress.remove(trackKey);
    }
  }
  
  /// Reconstrói a playlist do player e toca a música especificada
  Future<void> _rebuildPlaylistAndPlay(int targetIndex) async {
    // Recria o mapeamento de índices
    _playerIndexMap = [];
    int playerIdx = 0;
    for (int i = 0; i < _fullQueue.length; i++) {
      if (_fullQueue[i]['filename'] != null) {
        _playerIndexMap.add(playerIdx);
        playerIdx++;
      } else {
        _playerIndexMap.add(-1);
      }
    }
    
    // Filtra tracks com filename
    final validTracks = _fullQueue.where((t) => t['filename'] != null).toList();
    
    if (validTracks.isEmpty) {
      print('⚠️ Nenhuma track válida para reproduzir');
      return;
    }
    
    // Prepara nova playlist - prefere arquivos locais para modo offline
    final playlist = ConcatenatingAudioSource(
      children: validTracks.map((track) {
        final localPath = track['localPath'] as String?;
        
        // Verifica se existe arquivo local baixado
        if (localPath != null && File(localPath).existsSync()) {
          print('📂 Usando arquivo local: $localPath');
          return AudioSource.file(localPath);
        }
        
        // Fallback para stream remoto
        final filename = Uri.encodeComponent(track['filename'] ?? '');
        final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
        return AudioSource.uri(Uri.parse(url));
      }).toList(),
    );
    
    // Calcula índice no player para a track alvo
    final targetPlayerIndex = _playerIndexMap[targetIndex];
    
    if (targetPlayerIndex < 0) {
      print('⚠️ Track alvo ainda não tem filename válido');
      return;
    }
    
    // Workaround Windows: Para o player antes de setar nova source
    if (_isWindows && _player.playing) {
      await _player.stop();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _isPlayerReady = false;
    await _player.setAudioSource(playlist, initialIndex: targetPlayerIndex);
    _currentIndex = targetIndex;
    
    // Atualiza MediaItem
    _mediaQueue = _fullQueue.map((track) => _createMediaItem(track)).toList();
    queue.add(_mediaQueue);
    mediaItem.add(_mediaQueue[targetIndex]);
    
    // Workaround Windows: Aguarda player estar pronto
    if (_isWindows) {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_player.processingState == ProcessingState.ready) {
          _isPlayerReady = true;
          break;
        }
      }
    }
    
    // Toca
    await _player.play();
    _broadcastState(_player.playbackEvent);
    
    print('▶️ Tocando: ${_mediaQueue[targetIndex].title}');
    
    // Pré-carrega a próxima
    _preloadNextTrack();
  }
  
  // Flag para evitar múltiplos downloads simultâneos
  bool _isPreloading = false;
  
  // Set de downloads em andamento (por trackKey)
  final Set<String> _downloadsInProgress = {};
  
  /// Gera uma chave única para identificar uma track
  String _getTrackKey(Map<String, dynamic> track) {
    final tidalId = track['tidalId']?.toString() ?? '';
    final ytmusicId = track['ytmusicId']?.toString() ?? '';
    final trackName = track['trackName'] ?? track['title'] ?? '';
    final artistName = track['artistName'] ?? track['artist'] ?? '';
    
    if (tidalId.isNotEmpty) return 'tidal:$tidalId';
    if (ytmusicId.isNotEmpty) return 'ytmusic:$ytmusicId';
    return 'name:$artistName-$trackName';
  }
  
  /// Encontra o índice de uma track pela sua chave única
  int _findTrackIndexByKey(String trackKey) {
    for (int i = 0; i < _fullQueue.length; i++) {
      if (_getTrackKey(_fullQueue[i]) == trackKey) {
        return i;
      }
    }
    return -1;
  }
  
  /// Pré-carrega a próxima música da fila em background
  Future<void> _preloadNextTrack() async {
    // Evita múltiplos downloads simultâneos
    if (_isPreloading) return;
    
    final nextIndex = _currentIndex + 1;
    
    // Verifica se há próxima música
    if (nextIndex >= _fullQueue.length) {
      print('📋 Fim da fila, nada para pré-carregar');
      return;
    }
    
    final track = _fullQueue[nextIndex];
    final trackKey = _getTrackKey(track);
    
    // Verifica se já tem filename
    if (track['filename'] != null) {
      print('✅ Próxima música já está baixada');
      return;
    }
    
    // Verifica se já está em download
    if (_downloadsInProgress.contains(trackKey)) {
      print('⏳ Próxima música já está sendo baixada');
      return;
    }
    
    // Verifica se temos o ref para fazer download
    if (_ref == null) {
      print('⚠️ Ref não disponível para pré-carregamento');
      return;
    }
    
    _isPreloading = true;
    _downloadsInProgress.add(trackKey);
    
    final trackName = track['trackName'] ?? track['title'] ?? 'Música';
    final artistName = track['artistName'] ?? track['artist'] ?? 'Artista';
    
    print('📥 Pré-carregando próxima: $trackName - $artistName (key: $trackKey)');
    
    try {
      final searchCtrl = _ref!.read(searchControllerProvider);
      final filename = await searchCtrl.smartDownload(track);
      
      if (filename != null) {
        print('✅ Pré-carregamento concluído: $filename');
        
        // IMPORTANTE: Encontra o índice atual da track pelo seu ID único
        // (o índice pode ter mudado durante o download)
        final currentTrackIndex = _findTrackIndexByKey(trackKey);
        
        if (currentTrackIndex >= 0) {
          // Atualiza o filename na fila usando o índice correto
          _fullQueue[currentTrackIndex]['filename'] = filename;
          
          // Atualiza o mapeamento de índices
          _updatePlayerIndexMap();
          
          // Adiciona à playlist do player sem interromper a reprodução atual
          await _addTrackToPlaylist(currentTrackIndex, filename);
        } else {
          print('⚠️ Track não encontrada na fila após download: $trackKey');
        }
      }
    } catch (e) {
      print('⚠️ Erro no pré-carregamento: $e');
    } finally {
      _isPreloading = false;
      _downloadsInProgress.remove(trackKey);
    }
  }
  
  /// Atualiza o mapeamento de índices após download
  void _updatePlayerIndexMap() {
    _playerIndexMap = [];
    int playerIdx = 0;
    for (int i = 0; i < _fullQueue.length; i++) {
      if (_fullQueue[i]['filename'] != null) {
        _playerIndexMap.add(playerIdx);
        playerIdx++;
      } else {
        _playerIndexMap.add(-1);
      }
    }
  }
  
  /// Adiciona uma track à playlist do player em tempo real
  Future<void> _addTrackToPlaylist(int queueIndex, String filename) async {
    try {
      final audioSource = _player.audioSource;
      if (audioSource is ConcatenatingAudioSource) {
        final track = _fullQueue[queueIndex];
        final localPath = track['localPath'] as String?;
        
        AudioSource source;
        if (localPath != null && File(localPath).existsSync()) {
          print('📂 Adicionando arquivo local: $localPath');
          source = AudioSource.file(localPath);
        } else {
          final encodedFilename = Uri.encodeComponent(filename);
          final url = '$baseUrl/stream?filename=$encodedFilename&quality=$_currentQuality';
          source = AudioSource.uri(Uri.parse(url));
        }
        
        // Encontra a posição correta na playlist
        // (após todas as tracks com índice menor que já estão na playlist)
        int insertPosition = 0;
        for (int i = 0; i < queueIndex; i++) {
          if (_playerIndexMap[i] >= 0) {
            insertPosition++;
          }
        }
        
        await audioSource.insert(insertPosition, source);
        
        // Atualiza o mapeamento (precisa recalcular após inserção)
        _updatePlayerIndexMap();
        
        print('✅ Track adicionada à playlist na posição $insertPosition');
      }
    } catch (e) {
      print('⚠️ Erro ao adicionar track à playlist: $e');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    print('🎵 skipToPrevious chamado. Index atual: $_currentIndex, Posição: ${_player.position.inSeconds}s');
    
    // Se está no começo da música (< 3s), volta para anterior
    if (_player.position.inSeconds >= 3) {
      await _player.seek(Duration.zero);
      print('🔄 Voltou ao início da música atual');
      return;
    }
    
    if (_currentIndex <= 0) {
      await _player.seek(Duration.zero);
      print('🔄 Já na primeira música, voltou ao início');
      return;
    }
    
    final prevIndex = _currentIndex - 1;
    
    // Verifica se a track anterior tem filename
    if (_playerIndexMap[prevIndex] < 0) {
      // Não tem filename - precisa fazer download
      print('📥 Track anterior sem filename, iniciando download...');
      await _downloadAndPlayTrack(prevIndex);
      return;
    }
    
    // Tem filename - toca normalmente
    _currentIndex = prevIndex;
    final playerIndex = _playerIndexMap[prevIndex];
    
    try {
      await _player.pause();
      
      // Workaround Windows: Pequeno delay antes do seek
      if (_isWindows) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      await _player.seek(Duration.zero, index: playerIndex);
      mediaItem.add(_mediaQueue[_currentIndex]);
      _broadcastState(_player.playbackEvent);
      
      // Workaround Windows: Aguarda player estar pronto
      if (_isWindows) {
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_player.processingState == ProcessingState.ready) {
            break;
          }
        }
      }
      
      await _player.play();
      print('⏮️ Skip para: ${_mediaQueue[_currentIndex].title} (index: $_currentIndex)');
    } catch (e) {
      print('❌ Erro no skipToPrevious: $e');
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    print('🎵 skipToQueueItem: $index (total: ${_mediaQueue.length})');
    if (index < 0 || index >= _mediaQueue.length) {
      print('⚠️ Índice inválido para skipToQueueItem');
      return;
    }
    
    // Verifica se a track tem filename
    if (_playerIndexMap[index] < 0) {
      // Não tem filename - precisa fazer download
      print('📥 Track sem filename, iniciando download...');
      await _downloadAndPlayTrack(index);
      return;
    }
    
    // Tem filename - toca normalmente
    _currentIndex = index;
    final playerIndex = _playerIndexMap[index];
    
    try {
      await _player.pause();
      
      // Workaround Windows: Pequeno delay antes do seek
      if (_isWindows) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      await _player.seek(Duration.zero, index: playerIndex);
      mediaItem.add(_mediaQueue[index]);
      _broadcastState(_player.playbackEvent);
      
      // Workaround Windows: Aguarda player estar pronto
      if (_isWindows) {
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_player.processingState == ProcessingState.ready) {
            break;
          }
        }
      }
      
      await _player.play();
      print('✅ Pulou para: ${_mediaQueue[index].title}');
      
      // Pré-carrega a próxima
      _preloadNextTrack();
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
      print('🎵 playQueue chamado com ${tracks.length} tracks, initialIndex: $initialIndex');
      
      // Guarda a fila completa (com e sem filename)
      _fullQueue = List.from(tracks);
      
      // Converte TODAS as tracks para MediaItem (para UI mostrar a fila completa)
      _mediaQueue = tracks.map((track) => _createMediaItem(track)).toList();
      queue.add(_mediaQueue);
      
      // Cria mapeamento de índices: _mediaQueue index -> playlist index
      // Se não tem filename, valor é -1
      _playerIndexMap = [];
      int playerIdx = 0;
      for (int i = 0; i < tracks.length; i++) {
        if (tracks[i]['filename'] != null) {
          _playerIndexMap.add(playerIdx);
          playerIdx++;
        } else {
          _playerIndexMap.add(-1);
        }
      }
      
      // Filtra tracks com filename para reprodução
      final validTracks = tracks.where((t) => t['filename'] != null).toList();
      print('🎵 Tracks com filename: ${validTracks.length} de ${tracks.length}');
      
      if (validTracks.isEmpty) {
        print('⚠️ playQueue: Nenhuma track com filename ainda');
        if (_mediaQueue.isNotEmpty) {
          _currentIndex = initialIndex;
          mediaItem.add(_mediaQueue[initialIndex]);
        }
        return;
      }
      
      // Prepara a playlist no just_audio (apenas com tracks válidas)
      // Prefere arquivos locais para modo offline
      final playlist = ConcatenatingAudioSource(
        children: validTracks.map((track) {
          final localPath = track['localPath'] as String?;
          
          // Verifica se existe arquivo local baixado
          if (localPath != null && File(localPath).existsSync()) {
            print('📂 Usando arquivo local: $localPath');
            return AudioSource.file(localPath);
          }
          
          // Fallback para stream remoto
          final filename = Uri.encodeComponent(track['filename'] ?? '');
          final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
          return AudioSource.uri(Uri.parse(url));
        }).toList(),
      );

      // Calcula índice real no player
      int playerIndex = _playerIndexMap[initialIndex];
      if (playerIndex < 0) {
        // Track inicial não tem filename, encontra próxima válida
        for (int i = initialIndex; i < _playerIndexMap.length; i++) {
          if (_playerIndexMap[i] >= 0) {
            playerIndex = _playerIndexMap[i];
            break;
          }
        }
        if (playerIndex < 0) playerIndex = 0; // Fallback para primeira
      }

      // Workaround Windows: Para o player antes de setar nova source
      if (_isWindows && _player.playing) {
        await _player.stop();
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      _isPlayerReady = false;
      await _player.setAudioSource(playlist, initialIndex: playerIndex);
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

      // Workaround Windows: Aguarda o player estar pronto antes de dar play
      if (_isWindows) {
        // Aguarda até 3 segundos pelo player ficar pronto
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_player.processingState == ProcessingState.ready) {
            _isPlayerReady = true;
            break;
          }
        }
        print('🪟 Windows: Player pronto, iniciando reprodução...');
      }
      
      play();
      
      // Pré-carrega a próxima música
      _preloadNextTrack();
    } catch (e, stack) {
      print('❌ Erro em playQueue: $e');
      print('Stack: $stack');
    }
  }

  /// Cria MediaItem a partir de dados da track
  MediaItem _createMediaItem(Map<String, dynamic> track) {
    final filename = track['filename'] as String?;
    final id = track['tidalId']?.toString() ?? filename ?? '${track['trackName']}_${track['artistName']}';
    
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
    if ((artUri == null || artUri.isEmpty) && filename != null) {
      final encoded = Uri.encodeComponent(filename);
      artUri = '$baseUrl/cover?filename=$encoded';
    }
    
    // Extrai duração em milissegundos (se disponível)
    Duration? duration;
    final durationValue = track['duration'] ?? track['durationSeconds'] ?? track['durationMs'];
    if (durationValue != null) {
      if (durationValue is int) {
        duration = durationValue > 30000 
            ? Duration(milliseconds: durationValue)
            : Duration(seconds: durationValue);
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
  }

  /// Obtém a fila completa (incluindo tracks sem filename)
  List<Map<String, dynamic>> get fullQueue => _fullQueue;
  
  /// Atualiza o filename de uma track na fila (após download)
  /// e reconstrói a playlist se necessário
  Future<void> updateTrackFilename(int index, String filename) async {
    if (index < 0 || index >= _fullQueue.length) return;
    
    _fullQueue[index]['filename'] = filename;
    print('📥 Filename atualizado para index $index: $filename');
    
    // Reconstrói a playlist se a track estava sem filename
    if (_playerIndexMap[index] < 0) {
      print('🔄 Reconstruindo playlist com nova track...');
      final currentPos = _player.position;
      final wasPlaying = _player.playing;
      
      await playQueue(tracks: _fullQueue, initialIndex: _currentIndex);
      
      // Restaura posição se estava tocando a mesma música
      if (wasPlaying && currentPos.inSeconds > 0) {
        await seek(currentPos);
      }
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
