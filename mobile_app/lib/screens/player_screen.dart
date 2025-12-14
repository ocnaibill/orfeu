import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../providers.dart';

class PlayerScreen extends StatefulWidget {
  // Agora aceita uma FILA de músicas
  final List<Map<String, dynamic>> queue;
  final int initialIndex;
  final bool shuffle;

  // Construtor flexível: aceita item único ou lista
  PlayerScreen({
    super.key, 
    Map<String, dynamic>? item, 
    List<Map<String, dynamic>>? queue,
    this.initialIndex = 0,
    this.shuffle = false,
  }) : queue = queue ?? (item != null ? [item] : []);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class LyricLine {
  final Duration startTime;
  Duration duration;
  final String text;
  
  LyricLine(this.startTime, this.text, {this.duration = const Duration(seconds: 5)});
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  String _currentQuality = 'lossless';
  
  // Metadados do item ATUAL
  Map<String, dynamic>? _metadata;
  Map<String, dynamic>? _currentItem;
  
  // Fila Filtrada (Apenas itens baixados/válidos)
  List<Map<String, dynamic>> _validQueue = [];
  
  // Lyrics
  bool _showLyrics = false;
  List<LyricLine> _lyrics = [];
  bool _loadingLyrics = false;
  String? _plainLyrics;
  int _currentLyricIndex = -1;
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    _initializeQueue();
    _initPlayer();
    
    // Listener de estado (Play/Pause)
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    // Listener de mudança de faixa (Avançar/Recuar na playlist)
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index < _validQueue.length) {
        _onTrackChanged(_validQueue[index]);
      }
    });

    // Listener de Lyrics
    _audioPlayer.positionStream.listen((pos) {
      if (_showLyrics && _lyrics.isNotEmpty) {
        _syncLyrics(pos);
      }
    });
  }
  
  void _initializeQueue() {
    // Filtra apenas itens que têm filename (já baixados) para evitar erro 404
    _validQueue = widget.queue.where((item) => 
      item['filename'] != null && item['filename'].toString().isNotEmpty
    ).toList();

    // Se a fila ficou vazia (nada baixado), tenta usar o item único se tiver filename
    if (_validQueue.isEmpty && widget.queue.isNotEmpty) {
       // Se clicou em algo que não tá baixado, não devia ter aberto o player, 
       // mas por segurança não crasha.
       print("⚠️ Aviso: Tentando abrir player com fila sem arquivos locais.");
    }
  }

  // Chamado quando a faixa muda (automática ou manual)
  void _onTrackChanged(Map<String, dynamic> item) {
    if (_currentItem == item) return;
    
    setState(() {
      _currentItem = item;
      _metadata = null; // Limpa metadados anteriores
      _lyrics = []; // Limpa letra anterior
      _plainLyrics = null;
      _currentLyricIndex = -1;
    });
    
    _fetchMetadata(item);
  }

  Future<void> _initPlayer() async {
    if (_validQueue.isEmpty) return;

    try {
      // Monta a Playlist apenas com arquivos válidos
      final playlist = ConcatenatingAudioSource(
        children: _validQueue.map((item) {
          final filename = Uri.encodeComponent(item['filename'] ?? '');
          final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
          
          return AudioSource.uri(
            Uri.parse(url),
            tag: item, 
          );
        }).toList(),
      );

      // Calcula o novo índice inicial na lista filtrada
      int startIndex = 0;
      if (widget.initialIndex < widget.queue.length) {
        final targetItem = widget.queue[widget.initialIndex];
        final foundIndex = _validQueue.indexOf(targetItem);
        if (foundIndex != -1) startIndex = foundIndex;
      }

      await _audioPlayer.setAudioSource(playlist, initialIndex: startIndex);
      
      if (widget.shuffle) {
        await _audioPlayer.setShuffleModeEnabled(true);
      }

      _audioPlayer.play();
    } catch (e) {
      print("Erro player: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao iniciar fila: $e')),
        );
      }
    }
  }

  Future<void> _fetchMetadata(Map<String, dynamic> item) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final filename = Uri.encodeComponent(item['filename'] ?? '');
      
      // Busca metadados técnicos (Bitrate, etc)
      final resp = await dio.get('/metadata?filename=$filename');
      if (mounted) {
        setState(() => _metadata = resp.data);
      }
      
      _fetchLyrics(item);
    } catch (e) {
      print("Erro metadados: $e");
    }
  }

  Future<void> _fetchLyrics(Map<String, dynamic> item) async {
    setState(() => _loadingLyrics = true);
    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final filename = Uri.encodeComponent(item['filename'] ?? '');
      final resp = await dio.get('/lyrics?filename=$filename');
      
      final synced = resp.data['syncedLyrics'];
      final plain = resp.data['plainLyrics'];

      if (synced != null && synced.toString().isNotEmpty) {
        _parseLrc(synced);
      } else {
        setState(() => _plainLyrics = plain ?? "Letra não disponível sincronizada.");
      }
    } catch (e) {
      setState(() => _plainLyrics = "Letra não encontrada.");
    } finally {
      if (mounted) setState(() => _loadingLyrics = false);
    }
  }

  void _parseLrc(String lrc) {
    final lines = lrc.split('\n');
    final List<LyricLine> parsed = [];
    final RegExp regex = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2})\](.*)');

    for (var line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final ms = int.parse(match.group(3)!);
        final text = match.group(4)!.trim();
        
        if (text.isNotEmpty) {
          parsed.add(LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms * 10),
            text
          ));
        }
      }
    }

    // Calcular durações estimadas para o KaraokeText
    for (int i = 0; i < parsed.length; i++) {
      if (i < parsed.length - 1) {
        parsed[i].duration = parsed[i + 1].startTime - parsed[i].startTime;
      } else {
        parsed[i].duration = const Duration(seconds: 5); 
      }
    }

    setState(() => _lyrics = parsed);
  }

  void _syncLyrics(Duration position) {
    int index = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].startTime <= position) {
        // Verifica se ainda está dentro da duração da linha (ou é a última)
        if (i == _lyrics.length - 1 || position < _lyrics[i + 1].startTime) {
          index = i;
          break;
        }
      }
    }

    if (index != _currentLyricIndex && index != -1) {
      setState(() {
        _currentLyricIndex = index;
      });
      _scrollToCurrentLine();
    }
  }

  // --- Scroll Matemático (1/3 da tela) ---
  void _scrollToCurrentLine() {
    if (!_lyricsScrollController.hasClients || _currentLyricIndex == -1) return;
    
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;
    double contentWidth = screenWidth - 48; // Padding horizontal
    
    double listTopPadding = screenHeight * 0.45;

    double accumulatedHeight = 0;
    for (int i = 0; i < _currentLyricIndex; i++) {
      accumulatedHeight += _measureTextHeight(_lyrics[i].text, false, contentWidth);
    }

    double currentItemHeight = _measureTextHeight(_lyrics[_currentLyricIndex].text, true, contentWidth);

    double targetOffset = (listTopPadding + accumulatedHeight + (currentItemHeight / 2)) - (screenHeight / 3) + 20;
    
    if (targetOffset < 0) targetOffset = 0;
    
    _lyricsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic, 
    );
  }

  // Helper para medir altura do texto
  double _measureTextHeight(String text, bool isActive, double maxWidth) {
    final span = TextSpan(
      text: text,
      style: GoogleFonts.outfit(
        fontSize: isActive ? 28 : 22, 
        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
        height: 1.3,
      ),
    );
    
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    tp.layout(maxWidth: maxWidth);
    return tp.height + 32.0; // + Padding
  }

  void _changeQuality(String quality) {
    if (_currentQuality == quality) return;
    setState(() {
      _currentQuality = quality;
      _isPlaying = false; 
    });
    
    // Recarrega
    final currentPos = _audioPlayer.position;
    final currentIndex = _audioPlayer.currentIndex;
    
    _initPlayer().then((_) async {
       // Tenta voltar para onde estava na lista filtrada
       if (currentIndex != null && currentIndex < _validQueue.length) {
         await _audioPlayer.seek(currentPos, index: currentIndex);
       }
    });
    
    if (mounted) Navigator.pop(context);
  }

  String _getQualityLabel(String q) {
    switch (q) {
      case 'low': return 'Baixa';
      case 'medium': return 'Média';
      case 'high': return 'Alta';
      case 'lossless': return 'Lossless';
      default: return 'Desconhecido';
    }
  }
  
  String _getQualityDescription(String q) {
    switch (q) {
      case 'low': return 'MP3 128kbps (Economia de dados)';
      case 'medium': return 'MP3 192kbps (Equilibrado)';
      case 'high': return 'MP3 320kbps (Alta fidelidade)';
      case 'lossless': return 'Arquivo Original (Sem compressão)';
      default: return '';
    }
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true, 
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Qualidade do Áudio", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                if (_metadata != null)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFFD4AF37), size: 20),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Qualidade Atual: ${_getQualityLabel(_currentQuality)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text(_currentQuality == 'lossless' ? "${_metadata!['tech_label']} • Original" : "Convertido de ${_metadata!['tech_label']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                const Divider(color: Colors.white10),
                ...['low', 'medium', 'high', 'lossless'].map((q) {
                  final isSelected = _currentQuality == q;
                  return ListTile(
                    leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? const Color(0xFFD4AF37) : Colors.white24),
                    title: Text(_getQualityLabel(q), style: TextStyle(color: isSelected ? const Color(0xFFD4AF37) : Colors.white)),
                    subtitle: Text(_getQualityDescription(q), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                    onTap: () => _changeQuality(q),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentItem == null && _validQueue.isEmpty) {
        return Scaffold(
            backgroundColor: const Color(0xFF121212), 
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: const Center(child: Text("Fila vazia ou arquivos não encontrados.", style: TextStyle(color: Colors.white54)))
        );
    }
    
    if (_currentItem == null) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));

    final filenameEncoded = Uri.encodeComponent(_currentItem!['filename'] ?? '');
    final coverUrl = '$baseUrl/cover?filename=$filenameEncoded';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => Navigator.pop(context)),
        title: Text(_showLyrics ? "Letra" : "Tocando Agora", style: GoogleFonts.outfit(fontSize: 14, letterSpacing: 2)),
        centerTitle: true,
        actions: [
          IconButton(icon: Icon(_showLyrics ? Icons.music_note : Icons.lyrics, color: _showLyrics ? const Color(0xFFD4AF37) : Colors.white), onPressed: () {
              setState(() => _showLyrics = !_showLyrics);
              if (_showLyrics) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
          })
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A1A1A), Colors.black]),
        ),
        child: Column(
          children: [
            Expanded(child: _showLyrics ? _buildLyricsView(coverUrl) : _buildCoverView(coverUrl)),
            _buildPlayerControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerControls() {
    return Container(
      padding: const EdgeInsets.only(bottom: 40, left: 24, right: 24, top: 20),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Colors.black.withOpacity(0.0)], stops: const [0.5, 1.0])),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _audioPlayer.positionStream,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              final dur = _audioPlayer.duration ?? Duration.zero;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
                    child: Slider(
                      value: pos.inSeconds.toDouble().clamp(0, dur.inSeconds.toDouble()),
                      max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1,
                      activeColor: const Color(0xFFD4AF37),
                      inactiveColor: Colors.white10,
                      onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(pos), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        Text(_formatDuration(dur), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  )
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 36, color: Colors.white), 
                onPressed: _audioPlayer.hasPrevious ? _audioPlayer.seekToPrevious : null
              ),
              const SizedBox(width: 20),
              CircleAvatar(
                radius: 35, backgroundColor: Colors.white,
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 40),
                  onPressed: () { if (_isPlaying) _audioPlayer.pause(); else _audioPlayer.play(); },
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 36, color: Colors.white), 
                onPressed: _audioPlayer.hasNext ? _audioPlayer.seekToNext : null
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ... (Views de Capa e Letra mantidas com _metadata e _currentItem) ...
  // [CÓDIGO REPLICADO PARA COMPLETUDE]
  Widget _buildCoverView(String coverUrl) {
      return LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: SafeArea(top: true, bottom: false, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 20),
                Container(height: 300, width: 300, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, spreadRadius: 5)]), clipBehavior: Clip.antiAlias, child: Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white10))),
                const SizedBox(height: 40),
                Text(_metadata?['title'] ?? _currentItem?['display_name'] ?? 'Carregando...', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center, maxLines: 2),
                const SizedBox(height: 8),
                Text(_metadata?['artist'] ?? _currentItem?['artist'] ?? "Desconhecido", style: GoogleFonts.outfit(fontSize: 18, color: Colors.white54)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _showQualitySelector,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFD4AF37).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune, size: 14, color: Color(0xFFD4AF37)),
                        const SizedBox(width: 8),
                        Text(_getQualityLabel(_currentQuality).toUpperCase(), style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
                if (_metadata != null)
                   Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_metadata!['tech_label'] ?? "", style: const TextStyle(color: Colors.white38, fontSize: 10))),
            ]))),
          );
      });
  }

  Widget _buildLyricsView(String coverUrl) {
      double screenHeight = MediaQuery.of(context).size.height;
      return Column(children: [
          SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 20), child: Row(children: [
             ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(coverUrl, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.white10, width: 60, height: 60))),
             const SizedBox(width: 16),
             Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                 Text(_metadata?['title'] ?? _currentItem?['display_name'] ?? '...', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                 Text(_metadata?['artist'] ?? _currentItem?['artist'] ?? "...", style: GoogleFonts.outfit(fontSize: 14, color: Colors.white54)),
             ]))
          ]))),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: _loadingLyrics
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : _lyrics.isNotEmpty
                  ? ShaderMask(
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                          stops: [0.0, 0.2, 0.8, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: ListView.builder(
                        controller: _lyricsScrollController,
                        padding: EdgeInsets.symmetric(vertical: screenHeight * 0.45, horizontal: 24),
                        itemCount: _lyrics.length,
                        itemBuilder: (context, index) {
                          final line = _lyrics[index];
                          final isActive = index == _currentLyricIndex;
                          return RepaintBoundary(
                            child: GestureDetector(
                              onTap: () {
                                _audioPlayer.seek(line.startTime);
                                setState(() => _currentLyricIndex = index);
                              },
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                                opacity: isActive ? 1.0 : 0.5,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 24.0),
                                  child: isActive
                                      ? KaraokeText(text: line.text, startTime: line.startTime, duration: line.duration, playerStream: _audioPlayer.positionStream)
                                      : Text(line.text, textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Text(_plainLyrics ?? "Letra não encontrada.", style: const TextStyle(color: Colors.white54, fontSize: 16), textAlign: TextAlign.center))),
          ),
      ]);
  }
  
  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

class KaraokeText extends StatelessWidget {
  final String text;
  final Duration startTime;
  final Duration duration;
  final Stream<Duration> playerStream;

  const KaraokeText({super.key, required this.text, required this.startTime, required this.duration, required this.playerStream});

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ');
    return StreamBuilder<Duration>(
      stream: playerStream,
      builder: (context, snapshot) {
        final currentPos = snapshot.data ?? Duration.zero;
        final lineProgress = (currentPos - startTime).inMilliseconds / duration.inMilliseconds;
        final clampedLineProgress = lineProgress.clamp(0.0, 1.0);
        final wordCursor = clampedLineProgress * words.length;

        return RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
            children: List.generate(words.length, (i) {
              double fade = (wordCursor - i).clamp(0.0, 1.0);
              fade = Curves.easeOut.transform(fade);
              final color = Color.lerp(Colors.white30, Colors.white, fade);
              final shadowOpacity = fade * 0.6;
              return TextSpan(
                text: "${words[i]} ",
                style: TextStyle(color: color, shadows: [Shadow(color: const Color(0xFFD4AF37).withOpacity(shadowOpacity), blurRadius: 15 * fade)]),
              );
            }),
          ),
        );
      },
    );
  }
}