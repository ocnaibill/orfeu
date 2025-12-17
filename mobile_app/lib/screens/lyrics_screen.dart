import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../providers.dart';
import '../services/audio_service.dart';

/// Modelo para segmento de letra (palavra/sílaba)
class LyricSegment {
  final String text;
  final double startTime;
  final double endTime;

  LyricSegment({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  factory LyricSegment.fromJson(Map<String, dynamic> json) {
    return LyricSegment(
      text: json['text'] ?? '',
      startTime: (json['startTime'] ?? 0).toDouble(),
      endTime: (json['endTime'] ?? 0).toDouble(),
    );
  }
}

/// Modelo para linha de letra
class LyricLine {
  final String text;
  final double startTime;
  final double endTime;
  final List<LyricSegment> segments;

  LyricLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.segments,
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      text: json['text'] ?? '',
      startTime: (json['startTime'] ?? 0).toDouble(),
      endTime: (json['endTime'] ?? 0).toDouble(),
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => LyricSegment.fromJson(s))
              .toList() ??
          [],
    );
  }
}

/// Modelo para letras sincronizadas
class SyncedLyrics {
  final String source;
  final String syncType;
  final String plainText;
  final String? language;
  final List<LyricLine> lines;

  SyncedLyrics({
    required this.source,
    required this.syncType,
    required this.plainText,
    this.language,
    required this.lines,
  });

  factory SyncedLyrics.fromJson(Map<String, dynamic> json) {
    return SyncedLyrics(
      source: json['source'] ?? 'unknown',
      syncType: json['syncType'] ?? 'none',
      plainText: json['plainText'] ?? '',
      language: json['language'],
      lines: (json['lines'] as List<dynamic>?)
              ?.map((l) => LyricLine.fromJson(l))
              .toList() ??
          [],
    );
  }

  bool get hasSyllableSync => syncType == 'syllable';
  bool get hasLineSync => syncType == 'line' || syncType == 'syllable';
}

/// Classe para identificar parâmetros de busca de letras (com igualdade correta)
class LyricsParams {
  final String track;
  final String artist;
  final String? album;

  LyricsParams({required this.track, required this.artist, this.album});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsParams &&
          runtimeType == other.runtimeType &&
          track == other.track &&
          artist == other.artist &&
          album == other.album;

  @override
  int get hashCode => track.hashCode ^ artist.hashCode ^ (album?.hashCode ?? 0);
}

/// Provider para buscar letras
final lyricsProvider = FutureProvider.family<SyncedLyrics?, LyricsParams>(
  (ref, params) async {
    final dio = ref.read(dioProvider);

    print(
        '🎤 Buscando letras: track="${params.track}", artist="${params.artist}", album="${params.album}"');

    try {
      final response = await dio.get('/lyrics/synced', queryParameters: {
        'track': params.track,
        'artist': params.artist,
        if (params.album != null) 'album': params.album,
      });

      print('✅ Letras encontradas: ${response.data['syncType']}');
      return SyncedLyrics.fromJson(response.data);
    } catch (e) {
      print('❌ Erro ao buscar letras: $e');
      return null;
    }
  },
);

/// Tela de letras sincronizadas
class LyricsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? track;

  const LyricsScreen({super.key, this.track});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;
  int _currentSegmentIndex = -1;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _startSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateCurrentPosition();
    });
  }

  void _updateCurrentPosition() {
    final playerState = ref.read(playerProvider);
    final position = playerState.position.inMilliseconds / 1000.0;

    final trackName =
        widget.track?['trackName'] ?? widget.track?['title'] ?? '';
    final artistName =
        widget.track?['artistName'] ?? widget.track?['artist'] ?? '';

    final lyricsAsync = ref.read(lyricsProvider(LyricsParams(
      track: trackName,
      artist: artistName,
      album: widget.track?['collectionName'] ?? widget.track?['album'],
    )));

    lyricsAsync.whenData((lyrics) {
      if (lyrics == null || lyrics.lines.isEmpty) return;

      // Encontra linha atual
      int newLineIndex = -1;
      int newSegmentIndex = -1;

      for (int i = 0; i < lyrics.lines.length; i++) {
        final line = lyrics.lines[i];
        if (position >= line.startTime && position < line.endTime) {
          newLineIndex = i;

          // Encontra segmento atual (se tiver sincronização por sílaba)
          if (lyrics.hasSyllableSync) {
            for (int j = 0; j < line.segments.length; j++) {
              final seg = line.segments[j];
              if (position >= seg.startTime && position < seg.endTime) {
                newSegmentIndex = j;
                break;
              }
            }
          }
          break;
        }
      }

      // Atualiza estado se mudou
      final lineChanged = newLineIndex != _currentLineIndex;
      if (lineChanged || newSegmentIndex != _currentSegmentIndex) {
        setState(() {
          _currentLineIndex = newLineIndex;
          _currentSegmentIndex = newSegmentIndex;
        });

        // Scroll para centralizar linha atual (só quando muda de linha)
        if (lineChanged && newLineIndex >= 0) {
          _scrollToLineCenter(newLineIndex);
        }
      }
    });
  }

  void _scrollToLineCenter(int index) {
    if (!_scrollController.hasClients) return;

    // Obtém a altura da tela disponível para letras
    final screenHeight = MediaQuery.of(context).size.height;
    final centerOffset = screenHeight / 2 - 100; // Centro da área de letras

    // Calcula posição aproximada (cada linha ~70px de altura)
    final lineHeight = 70.0;
    final targetOffset = (index * lineHeight) - centerOffset;

    _scrollController.animateTo(
      targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final track = widget.track ?? playerState.currentTrack;

    if (track == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: Text('Nenhuma música tocando',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final trackName = track['trackName'] ?? track['title'] ?? 'Música';
    final artistName = track['artistName'] ?? track['artist'] ?? 'Artista';
    final albumName = track['collectionName'] ?? track['album'];

    final lyricsAsync = ref.watch(lyricsProvider(LyricsParams(
      track: trackName,
      artist: artistName,
      album: albumName,
    )));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFD4AF37).withOpacity(0.2),
                  const Color(0xFF0D0D0D),
                  const Color(0xFF0D0D0D),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white, size: 32),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              trackName,
                              style: GoogleFonts.firaSans(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              artistName,
                              style: GoogleFonts.firaSans(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48), // Balance
                    ],
                  ),
                ),

                // Lyrics content
                Expanded(
                  child: lyricsAsync.when(
                    loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    ),
                    error: (e, _) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lyrics_outlined,
                              color: Colors.white24, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'Letras não encontradas',
                            style: GoogleFonts.firaSans(
                                color: Colors.white54, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$trackName - $artistName',
                            style: GoogleFonts.firaSans(
                                color: Colors.white38, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    data: (lyrics) {
                      if (lyrics == null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lyrics_outlined,
                                  color: Colors.white24, size: 64),
                              const SizedBox(height: 16),
                              Text(
                                'Letras não disponíveis',
                                style: GoogleFonts.firaSans(
                                    color: Colors.white54, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }

                      // Se não tem sincronização, mostra texto plano
                      if (!lyrics.hasLineSync || lyrics.lines.isEmpty) {
                        return _buildPlainLyrics(lyrics.plainText);
                      }

                      // Letras sincronizadas
                      return _buildSyncedLyrics(lyrics);
                    },
                  ),
                ),

                // Footer com info da fonte
                lyricsAsync.whenData((lyrics) {
                      if (lyrics == null) return const SizedBox();

                      String sourceText = '';
                      if (lyrics.source == 'apple_music') {
                        sourceText = 'Apple Music • Sincronizado por sílaba';
                      } else if (lyrics.source == 'lrclib') {
                        sourceText =
                            'LRCLIB • ${lyrics.hasLineSync ? 'Sincronizado por linha' : 'Texto'}';
                      }

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          sourceText,
                          style: GoogleFonts.firaSans(
                              color: Colors.white38, fontSize: 12),
                        ),
                      );
                    }).value ??
                    const SizedBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainLyrics(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: GoogleFonts.firaSans(
          color: Colors.white70,
          fontSize: 20,
          height: 1.8,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSyncedLyrics(SyncedLyrics lyrics) {
    // Padding vertical para permitir centralização da primeira e última linha
    final screenHeight = MediaQuery.of(context).size.height;
    final verticalPadding = screenHeight / 2 - 50;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: verticalPadding),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final isCurrentLine = index == _currentLineIndex;
        final isPastLine = index < _currentLineIndex;

        // Se tem sincronização por sílaba, renderiza palavra por palavra
        if (lyrics.hasSyllableSync && line.segments.isNotEmpty) {
          return _buildSyllableLine(line, index, isCurrentLine, isPastLine);
        }

        // Sincronização por linha
        return _buildLineLyric(line, index, isCurrentLine, isPastLine);
      },
    );
  }

  Widget _buildLineLyric(
      LyricLine line, int index, bool isCurrentLine, bool isPastLine) {
    return GestureDetector(
      onTap: () => _seekToLine(line),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: GoogleFonts.firaSans(
            color: isCurrentLine
                ? const Color(0xFFD4AF37)
                : isPastLine
                    ? Colors.white38
                    : Colors.white70,
            fontSize: isCurrentLine ? 26 : 22,
            fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
            height: 1.4,
          ),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildSyllableLine(
      LyricLine line, int lineIndex, bool isCurrentLine, bool isPastLine) {
    return GestureDetector(
      onTap: () => _seekToLine(line),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: line.segments.asMap().entries.map((entry) {
            final segIndex = entry.key;
            final segment = entry.value;

            final isCurrentSegment =
                isCurrentLine && segIndex == _currentSegmentIndex;
            final isPastSegment = isPastLine ||
                (isCurrentLine && segIndex < _currentSegmentIndex);

            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 100),
              style: GoogleFonts.firaSans(
                color: isCurrentSegment
                    ? const Color(0xFFD4AF37)
                    : isPastSegment
                        ? const Color(0xFFD4AF37).withOpacity(0.5)
                        : isCurrentLine
                            ? Colors.white
                            : isPastLine
                                ? Colors.white38
                                : Colors.white70,
                fontSize: isCurrentLine ? 26 : 22,
                fontWeight:
                    isCurrentSegment ? FontWeight.bold : FontWeight.normal,
                height: 1.4,
              ),
              child: Text(segment.text),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _seekToLine(LyricLine line) {
    ref.read(playerProvider.notifier).seek(
          Duration(milliseconds: (line.startTime * 1000).toInt()),
        );
  }
}
