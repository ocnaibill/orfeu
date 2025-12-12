import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart'; // Importa a URL base

class PlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const PlayerScreen({super.key, required this.item});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  String _currentQuality = 'lossless';
  Map<String, dynamic>? _metadata;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initPlayer();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      final filename = Uri.encodeComponent(widget.item['filename']);
      final resp = await dio.get('/metadata?filename=$filename');
      if (mounted) {
        setState(() => _metadata = resp.data);
      }
    } catch (e) {
      print("Erro metadados: $e");
    }
  }

  Future<void> _initPlayer() async {
    try {
      final filename = Uri.encodeComponent(widget.item['filename']);
      final url = '$baseUrl/stream?filename=$filename&quality=$_currentQuality';
      await _audioPlayer.setUrl(url);
      _audioPlayer.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      print("Erro player: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao tocar: $e')),
        );
      }
    }
  }

  void _changeQuality(String quality) {
    setState(() {
      _currentQuality = quality;
      _isPlaying = false;
    });
    _initPlayer();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filenameEncoded = Uri.encodeComponent(widget.item['filename']);
    final coverUrl = '$baseUrl/cover?filename=$filenameEncoded';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF1A1A1A), Colors.black],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Capa
              Container(
                height: 300,
                width: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black45, blurRadius: 20, spreadRadius: 5)
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: Colors.white10,
                      child: const Icon(Icons.music_note,
                          size: 80, color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 40),

              // Textos
              Text(
                _metadata?['title'] ?? widget.item['display_name'],
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Text(
                _metadata?['artist'] ?? "Artista Desconhecido",
                style: GoogleFonts.outfit(fontSize: 18, color: Colors.white54),
              ),

              const SizedBox(height: 10),
              // Badge Qualidade
              if (_metadata != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFD4AF37).withOpacity(0.3)),
                  ),
                  child: Text(_metadata!['tech_label'] ?? "Hi-Res",
                      style: const TextStyle(
                          color: Color(0xFFD4AF37), fontSize: 10)),
                ),

              const Spacer(),

              // Slider
              StreamBuilder<Duration>(
                stream: _audioPlayer.positionStream,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final dur = _audioPlayer.duration ?? Duration.zero;
                  return Column(
                    children: [
                      Slider(
                        value: pos.inSeconds
                            .toDouble()
                            .clamp(0, dur.inSeconds.toDouble()),
                        max: dur.inSeconds.toDouble() > 0
                            ? dur.inSeconds.toDouble()
                            : 1,
                        activeColor: const Color(0xFFD4AF37),
                        inactiveColor: Colors.white10,
                        onChanged: (v) =>
                            _audioPlayer.seek(Duration(seconds: v.toInt())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(pos),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12)),
                            Text(_formatDuration(dur),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      )
                    ],
                  );
                },
              ),

              // Controles
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      icon: const Icon(Icons.skip_previous_rounded,
                          size: 36, color: Colors.white),
                      onPressed: () {}),
                  const SizedBox(width: 20),
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 40),
                      onPressed: () {
                        if (_isPlaying)
                          _audioPlayer.pause();
                        else
                          _audioPlayer.play();
                        setState(() => _isPlaying = !_isPlaying);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                      icon: const Icon(Icons.skip_next_rounded,
                          size: 36, color: Colors.white),
                      onPressed: () {}),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) =>
      "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
