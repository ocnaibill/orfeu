import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../providers.dart';
import '../services/audio_service.dart';

class LyricLine {
  final Duration startTime;
  Duration duration;
  final String text;
  LyricLine(this.startTime, this.text,
      {this.duration = const Duration(seconds: 5)});
}

class PlayerScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>>? queue;
  final int initialIndex;
  final bool shuffle;

  const PlayerScreen({
    super.key,
    this.item,
    this.queue,
    this.initialIndex = 0,
    this.shuffle = false,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showLyrics = false;
  List<LyricLine> _lyrics = [];
  bool _loadingLyrics = false;
  String? _plainLyrics;
  int _currentLyricIndex = -1;
  final ScrollController _lyricsScrollController = ScrollController();

  String? _lastLyricsFilename;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPlayback();
    });
  }

  void _initPlayback() {
    final playerNotifier = ref.read(playerProvider.notifier);

    List<Map<String, dynamic>> targetQueue = [];
    if (widget.queue != null && widget.queue!.isNotEmpty) {
      targetQueue = widget.queue!;
    } else if (widget.item != null) {
      targetQueue = [widget.item!];
    }

    if (targetQueue.isNotEmpty) {
      // Chama o playContext. A correção no service garante que a UI atualize.
      playerNotifier.playContext(
          queue: targetQueue,
          initialIndex: widget.initialIndex,
          shuffle: widget.shuffle);
    }
  }

  void _checkLyrics(Map<String, dynamic>? currentTrack) {
    if (currentTrack == null) return;
    final filename = currentTrack['filename'];

    if (filename != null && filename != _lastLyricsFilename) {
      _lastLyricsFilename = filename;
      _lyrics = [];
      _plainLyrics = null;
      _currentLyricIndex = -1;
      _fetchLyrics(filename);
    }
  }

  Future<void> _fetchLyrics(String filename) async {
    if (!mounted) return;
    setState(() => _loadingLyrics = true);

    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final encoded = Uri.encodeComponent(filename);
      final resp = await dio.get('/lyrics?filename=$encoded');
      final synced = resp.data['syncedLyrics'];
      final plain = resp.data['plainLyrics'];

      if (mounted) {
        if (synced != null && synced.toString().isNotEmpty) {
          _parseLrc(synced);
        } else {
          setState(() =>
              _plainLyrics = plain ?? "Letra não disponível sincronizada.");
        }
      }
    } catch (e) {
      if (mounted) setState(() => _plainLyrics = "Letra não encontrada.");
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
              text));
        }
      }
    }
    for (int i = 0; i < parsed.length; i++) {
      if (i < parsed.length - 1) {
        parsed[i].duration = parsed[i + 1].startTime - parsed[i].startTime;
      }
    }
    setState(() => _lyrics = parsed);
  }

  void _syncLyrics(Duration position) {
    if (!_showLyrics || _lyrics.isEmpty) return;

    int index = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].startTime <= position) {
        if (i == _lyrics.length - 1 || position < _lyrics[i + 1].startTime) {
          index = i;
          break;
        }
      }
    }
    if (index != _currentLyricIndex && index != -1) {
      setState(() => _currentLyricIndex = index);
      _scrollToCurrentLine();
    }
  }

  void _scrollToCurrentLine() {
    if (!_lyricsScrollController.hasClients || _currentLyricIndex == -1) return;
    double screenHeight = MediaQuery.of(context).size.height;
    double offset = (_currentLyricIndex * 80.0) - (screenHeight * 0.3);
    if (offset < 0) offset = 0;

    _lyricsScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
  }

  // --- UI DO SELETOR DE QUALIDADE ---
  String _getQualityLabel(String q) {
    switch (q) {
      case 'low':
        return 'Baixa';
      case 'medium':
        return 'Média';
      case 'high':
        return 'Alta';
      case 'lossless':
        return 'Lossless';
      default:
        return 'Desconhecido';
    }
  }

  String _getQualityDescription(String q) {
    switch (q) {
      case 'low':
        return 'MP3 128kbps';
      case 'medium':
        return 'MP3 192kbps';
      case 'high':
        return 'MP3 320kbps';
      case 'lossless':
        return 'Original / FLAC';
      default:
        return '';
    }
  }

  void _showQualitySelector() {
    final notifier = ref.read(playerProvider.notifier);
    final currentQ = notifier.currentQuality;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Qualidade do Áudio",
                    style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 20),
                ...['low', 'medium', 'high', 'lossless'].map((q) {
                  final isSelected = currentQ == q;
                  return ListTile(
                    leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected
                            ? const Color(0xFFD4AF37)
                            : Colors.white24),
                    title: Text(_getQualityLabel(q),
                        style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFD4AF37)
                                : Colors.white)),
                    subtitle: Text(_getQualityDescription(q),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12)),
                    onTap: () {
                      notifier.changeQuality(q);
                      Navigator.pop(context);
                    },
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
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final currentTrack = playerState.currentTrack;

    _checkLyrics(currentTrack);
    _syncLyrics(playerState.position);

    if (currentTrack == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
      );
    }

    String coverUrl =
        currentTrack['imageUrl'] ?? currentTrack['artworkUrl'] ?? '';
    if (coverUrl.isEmpty && currentTrack['filename'] != null) {
      final encoded = Uri.encodeComponent(currentTrack['filename']);
      coverUrl = '$baseUrl/cover?filename=$encoded';
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_showLyrics ? "Letra" : "Tocando Agora",
            style: GoogleFonts.outfit(
                fontSize: 14, letterSpacing: 2, color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showLyrics ? Icons.music_note : Icons.lyrics,
                color: _showLyrics ? const Color(0xFFD4AF37) : Colors.white),
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A1A), Colors.black])),
        child: Column(
          children: [
            Expanded(
                child: _showLyrics
                    ? _buildLyricsView(
                        coverUrl, currentTrack, playerState.position)
                    : _buildCoverView(coverUrl, currentTrack, notifier)),
            _buildPlayerControls(playerState, notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverView(String coverUrl, Map<String, dynamic> track,
      AudioPlayerNotifier notifier) {
    // CORREÇÃO DE NOMENCLATURA:
    // Adiciona fallback para display_name, que é comum no seu backend
    final title = track['title'] ??
        track['display_name'] ??
        track['trackName'] ??
        'Desconhecido';
    final artist =
        track['artist'] ?? track['artistName'] ?? 'Artista Desconhecido';

    final favorites = ref.watch(favoriteTracksProvider);
    final isFavorite =
        track['filename'] != null && favorites.contains(track['filename']);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          height: 300,
          width: 300,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black45, blurRadius: 20, spreadRadius: 5)
              ],
              image: DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
              )),
        ),
        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(artist,
                        style: GoogleFonts.outfit(
                            fontSize: 18, color: Colors.white54),
                        maxLines: 1),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                    color:
                        isFavorite ? const Color(0xFFD4AF37) : Colors.white54,
                    size: 32),
                onPressed: () {
                  ref.read(libraryControllerProvider).toggleFavorite(track);
                },
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        // BOTÃO DE QUALIDADE (Restaurado)
        GestureDetector(
          onTap: _showQualitySelector,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.3))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 14, color: Color(0xFFD4AF37)),
                const SizedBox(width: 8),
                Text(
                  notifier.currentQuality.toUpperCase(),
                  style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildPlayerControls(PlayerState state, AudioPlayerNotifier notifier) {
    final pos = state.position;
    final dur = state.duration;

    return Container(
      padding: const EdgeInsets.only(bottom: 40, left: 24, right: 24, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFD4AF37),
                thumbColor: const Color(0xFFD4AF37),
                inactiveTrackColor: Colors.white10),
            child: Slider(
              value:
                  pos.inSeconds.toDouble().clamp(0, dur.inSeconds.toDouble()),
              max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1,
              onChanged: (v) => notifier.seek(Duration(seconds: v.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(pos),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                Text(_formatDuration(dur),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      size: 36, color: Colors.white),
                  onPressed: notifier.previous),
              const SizedBox(width: 20),
              CircleAvatar(
                radius: 35,
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 40),
                  onPressed: notifier.togglePlay,
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      size: 36, color: Colors.white),
                  onPressed: notifier.next),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLyricsView(
      String coverUrl, Map<String, dynamic> track, Duration position) {
    // Nomenclatura corrigida também aqui
    final title =
        track['title'] ?? track['display_name'] ?? track['trackName'] ?? '...';

    return Column(
      children: [
        SafeArea(
            bottom: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Row(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(coverUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: Colors.white10, width: 60, height: 60))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(track['artist'] ?? '...',
                            style: GoogleFonts.outfit(
                                fontSize: 14, color: Colors.white54)),
                      ]))
                ]))),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: _loadingLyrics
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : _lyrics.isNotEmpty
                  ? ListView.builder(
                      controller: _lyricsScrollController,
                      padding: EdgeInsets.symmetric(
                          vertical: MediaQuery.of(context).size.height * 0.4,
                          horizontal: 24),
                      itemCount: _lyrics.length,
                      itemBuilder: (context, index) {
                        final line = _lyrics[index];
                        final isActive = index == _currentLyricIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: isActive ? 1.0 : 0.4,
                            child: Text(
                              line.text,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  fontSize: isActive ? 26 : 22,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: Colors.white),
                            ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Text(_plainLyrics ?? "Letra não encontrada",
                          style: const TextStyle(color: Colors.white54)),
                    ),
        )
      ],
    );
  }

  String _formatDuration(Duration d) =>
      "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
