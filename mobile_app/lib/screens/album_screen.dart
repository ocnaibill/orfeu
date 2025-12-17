import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:ui';
import '../providers.dart';
import '../services/audio_service.dart';
import '../widgets/bottom_nav_area.dart'; // <--- Import restaurado

// Provider para carregar os detalhes do álbum
final albumDetailsProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(searchControllerProvider).getAlbumDetails(id);
});

class AlbumScreen extends ConsumerStatefulWidget {
  final String collectionId;
  final String heroTag;

  const AlbumScreen({
    super.key,
    required this.collectionId,
    this.heroTag = 'album_cover',
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with SingleTickerProviderStateMixin {
  Color _vibrantColor = Colors.white;
  bool _colorCalculated = false;
  bool? _isLibraryAdded; // null = não verificado ainda
  
  @override
  void initState() {
    super.initState();
    // Verifica se o álbum já está na biblioteca
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfAlbumSaved();
    });
  }
  
  void _checkIfAlbumSaved() {
    final isSaved = ref.read(libraryControllerProvider).isAlbumSaved(widget.collectionId);
    if (mounted) {
      setState(() {
        _isLibraryAdded = isSaved;
      });
    }
  }
  
  Future<void> _toggleLibrary(Map<String, dynamic> albumData) async {
    final controller = ref.read(libraryControllerProvider);
    
    if (_isLibraryAdded == true) {
      // Remove da biblioteca
      final success = await controller.removeAlbum(widget.collectionId);
      if (success && mounted) {
        setState(() => _isLibraryAdded = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Álbum removido da biblioteca')),
        );
      }
    } else {
      // Adiciona à biblioteca
      final success = await controller.saveAlbum({
        'id': widget.collectionId,
        'title': albumData['collectionName'],
        'artist': albumData['artistName'],
        'artworkUrl': albumData['artworkUrl'],
        'year': albumData['year'],
      });
      if (success && mounted) {
        setState(() => _isLibraryAdded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Álbum adicionado à biblioteca')),
        );
      }
    }
  }

  Future<void> _extractColor(String url) async {
    if (_colorCalculated) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          _vibrantColor = palette.vibrantColor?.color ??
              palette.lightVibrantColor?.color ??
              palette.dominantColor?.color ??
              Colors.white;
          _colorCalculated = true;
        });
      }
    } catch (e) {
      // Falha silenciosa
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumAsync = ref.watch(albumDetailsProvider(widget.collectionId));

    // Observa o player
    final playerState = ref.watch(playerProvider);
    final currentTrack = playerState.currentTrack;
    final isPlaying = playerState.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const BottomNavArea(), // <--- Widget restaurado
      body: albumAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        error: (err, stack) => Center(
            child: Text("Erro: $err",
                style: const TextStyle(color: Colors.white))),
        data: (albumData) {
          final artworkUrl = albumData['artworkUrl'] ?? '';
          final tracks = List<Map<String, dynamic>>.from(albumData['tracks']);

          if (artworkUrl.isNotEmpty && !_colorCalculated) {
            _extractColor(artworkUrl);
          }

          return Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 45),

                    // --- 1. HEADER ---
                    SizedBox(
                      height: 50,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 45,
                            top: 0,
                            child: _buildGlassButton(
                              icon: Icons.arrow_back,
                              color: Colors.white,
                              onTap: () => Navigator.pop(context),
                            ),
                          ),
                          Positioned(
                            right: 35,
                            top: 0,
                            child: _buildGlassButton(
                              icon: Icons.more_horiz,
                              color: _vibrantColor,
                              isVibrantBackground: true,
                              onTap: () {},
                            ),
                          ),
                          Positioned(
                            right: 100,
                            top: 0,
                            child: _buildGlassButton(
                              icon: _isLibraryAdded == true ? Icons.check : Icons.add,
                              color: Colors.white,
                              isVibrantBackground: true,
                              onTap: () => _toggleLibrary(albumData),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- 2. CAPA E INFO ---
                    Center(
                      child: Hero(
                        tag: widget.heroTag,
                        child: Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: _vibrantColor.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: -10,
                                  offset: const Offset(0, 20))
                            ],
                            image: artworkUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(artworkUrl),
                                    fit: BoxFit.cover)
                                : null,
                            color: Colors.grey[900],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: 234,
                      child: Text(
                        albumData['collectionName'] ?? 'Álbum',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.firaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      "${albumData['artistName']} - ${albumData['year']}",
                      style: GoogleFonts.firaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          color: _vibrantColor),
                    ),

                    if (albumData['genre'] != null && albumData['genre'].toString().isNotEmpty)
                      Text(
                        albumData['genre'],
                        style: GoogleFonts.firaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                            color: _vibrantColor),
                      ),

                    const SizedBox(height: 10),

                    // --- 3. AÇÕES ---
                    SizedBox(
                      height: 60,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 54,
                            child: _buildAcrylicActionButton(
                              label: "Reproduzir",
                              icon: Icons.play_arrow,
                              onTap: () => _playAlbum(context, ref, tracks, 0,
                                  shuffle: false, albumCover: artworkUrl),
                            ),
                          ),
                          Positioned(
                            right: 54,
                            child: _buildAcrylicActionButton(
                              label: "Aleatório",
                              icon: Icons.shuffle,
                              onTap: () => _playAlbum(context, ref, tracks, 0,
                                  shuffle: true, albumCover: artworkUrl),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- 4. LISTA DE FAIXAS ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 33),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];

                          // Lógica de Comparação Robusta
                          final currentTitle = currentTrack?['trackName'] ??
                              currentTrack?['title'];
                          final thisTitle = track['trackName'];

                          final isPlayingThis = currentTitle != null &&
                              thisTitle != null &&
                              currentTitle == thisTitle;

                          final itemColor =
                              isPlayingThis ? _vibrantColor : Colors.white;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 15),
                            child: InkWell(
                              onTap: () => _playAlbum(
                                  context, ref, tracks, index,
                                  shuffle: false, albumCover: artworkUrl),
                              child: SizedBox(
                                height: 50,
                                child: Row(
                                  children: [
                                    // Ícone Animado ou Número
                                    SizedBox(
                                      width: 25,
                                      child: isPlayingThis
                                          ? EqualizerAnimation(
                                              color: _vibrantColor,
                                              isAnimating: isPlaying)
                                          : Text(
                                              "${index + 1}",
                                              style: GoogleFonts.firaSans(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.normal,
                                                  color: Colors.white54),
                                            ),
                                    ),
                                    const SizedBox(width: 15),

                                    // Info da Faixa
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            track['trackName'],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.firaSans(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w400,
                                              color: itemColor,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(
                                                track['durationMs'] ?? 0),
                                            style: GoogleFonts.firaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: itemColor.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Botão Download
                                    Padding(
                                      padding: const EdgeInsets.only(right: 20),
                                      child: Icon(Icons.download_rounded,
                                          color: _vibrantColor, size: 24),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildGlassButton(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap,
      bool isVibrantBackground = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: isVibrantBackground
              ? _vibrantColor.withOpacity(0.2)
              : Colors.transparent,
          shape: BoxShape.circle,
          borderRadius: null,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildAcrylicActionButton(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 130,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9).withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _vibrantColor, size: 20),
                const SizedBox(width: 5),
                Text(label,
                    style: GoogleFonts.firaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _vibrantColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playAlbum(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> tracks, int startIndex,
      {required bool shuffle, required String albumCover}) async {
    if (tracks.isEmpty) return;

    // Feedback visual
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Preparando música...",
              style: TextStyle(color: Colors.black)),
          backgroundColor: Color(0xFFD9D9D9),
          duration: Duration(milliseconds: 1000)),
    );

    try {
      final targetTrack = Map<String, dynamic>.from(tracks[startIndex]);

      // Garante metadados essenciais
      if (targetTrack['artworkUrl'] == null ||
          targetTrack['artworkUrl'].toString().isEmpty) {
        targetTrack['artworkUrl'] = albumCover;
      }

      // Resolve o arquivo (Smart Download)
      final filename =
          await ref.read(searchControllerProvider).smartDownload(targetTrack);

      if (filename != null) {
        targetTrack['filename'] = filename;

        // Toca a música resolvida
        // Nota: O AudioService filtra itens sem filename.
        // Para uma experiência completa de álbum, o ideal seria resolver o próximo em background.
        // Aqui tocamos o que foi clicado.
        ref.read(playerProvider.notifier).playContext(
          queue: [targetTrack],
          initialIndex: 0,
          shuffle: shuffle,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao reproduzir: $e"),
          backgroundColor: Colors.red));
    }
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    return "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
  }
}

// --- ANIMAÇÃO DE EQUALIZADOR SIMPLES ---
class EqualizerAnimation extends StatefulWidget {
  final Color color;
  final bool isAnimating;
  const EqualizerAnimation(
      {super.key, required this.color, required this.isAnimating});

  @override
  State<EqualizerAnimation> createState() => _EqualizerAnimationState();
}

class _EqualizerAnimationState extends State<EqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimating) {
      return Icon(Icons.graphic_eq, color: widget.color, size: 20);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(0.6),
            const SizedBox(width: 2),
            _bar(1.0),
            const SizedBox(width: 2),
            _bar(0.4),
          ],
        );
      },
    );
  }

  Widget _bar(double scaleMax) {
    final height = 12.0 * (0.3 + (scaleMax * _controller.value * 0.7));
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
