import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers.dart';
import '../services/audio_service.dart';
import '../screens/player_screen.dart';

/// Widget reutilizável que contém o MiniPlayer + Navbar
/// Pode ser usado em qualquer tela para manter a navegação consistente
class BottomNavArea extends ConsumerStatefulWidget {
  final int selectedIndex;
  final Function(int)? onNavTap;

  const BottomNavArea({
    super.key,
    this.selectedIndex = 0,
    this.onNavTap,
  });

  @override
  ConsumerState<BottomNavArea> createState() => _BottomNavAreaState();
}

class _BottomNavAreaState extends ConsumerState<BottomNavArea> {
  Color _dynamicColor = Colors.black;
  String? _lastProcessedImageUrl;

  void _updateColorLogic(Map<String, dynamic>? currentTrack) {
    if (currentTrack == null) {
      if (_dynamicColor != Colors.black) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _dynamicColor = Colors.black);
        });
      }
      _lastProcessedImageUrl = null;
      return;
    }

    String coverUrl =
        currentTrack['imageUrl'] ?? currentTrack['artworkUrl'] ?? '';
    if (coverUrl.isEmpty && currentTrack['filename'] != null) {
      final encoded = Uri.encodeComponent(currentTrack['filename']);
      coverUrl = '$baseUrl/cover?filename=$encoded';
    }

    if (coverUrl.isEmpty) return;

    if (coverUrl != _lastProcessedImageUrl) {
      _lastProcessedImageUrl = coverUrl;
      _extractPalette(coverUrl);
    }
  }

  Future<void> _extractPalette(String url) async {
    try {
      final provider = NetworkImage(url);
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 20,
      );

      if (mounted && _lastProcessedImageUrl == url) {
        setState(() {
          _dynamicColor = palette.vibrantColor?.color ??
              palette.dominantColor?.color ??
              palette.darkVibrantColor?.color ??
              Colors.black;
        });
      }
    } catch (e) {
      print("Erro ao extrair cor da capa: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final currentTrack = playerState.currentTrack;

    _updateColorLogic(currentTrack);

    final uiColor = currentTrack != null ? _dynamicColor : Colors.black;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentTrack != null)
          _buildMiniPlayer(context, ref, playerState, uiColor),
        _buildCustomNavbar(context, uiColor),
      ],
    );
  }

  Widget _buildMiniPlayer(BuildContext context, WidgetRef ref,
      PlayerState playerState, Color backgroundColor) {
    final track = playerState.currentTrack!;
    final isPlaying = playerState.isPlaying;

    final title = track['title'] ??
        track['display_name'] ??
        track['trackName'] ??
        'Desconhecido';
    final artist =
        track['artist'] ?? track['artistName'] ?? 'Artista Desconhecido';

    String coverUrl = track['imageUrl'] ?? track['artworkUrl'] ?? '';
    if (coverUrl.isEmpty && track['filename'] != null) {
      final encoded = Uri.encodeComponent(track['filename']);
      coverUrl = '$baseUrl/cover?filename=$encoded';
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PlayerScreen(),
            fullscreenDialog: true,
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        width: double.infinity,
        height: 78,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15), topRight: Radius.circular(15)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 33,
              top: 9,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: coverUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(coverUrl), fit: BoxFit.cover)
                      : null,
                  color: Colors.grey[800],
                ),
              ),
            ),
            Positioned(
              left: 102,
              top: 9,
              height: 60,
              right: 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.0)),
                  const SizedBox(height: 3),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withOpacity(0.7),
                          height: 1.0)),
                ],
              ),
            ),
            Positioned(
              right: 21,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white, size: 28),
                    onPressed: () =>
                        ref.read(playerProvider.notifier).previous(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32),
                    onPressed: () =>
                        ref.read(playerProvider.notifier).togglePlay(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white, size: 28),
                    onPressed: () => ref.read(playerProvider.notifier).next(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomNavbar(BuildContext context, Color backgroundColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      width: double.infinity,
      color: backgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 59,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, "Início", Icons.home_filled, 25, 28),
              _buildNavItem(1, "Buscar", Icons.search, 25, 25),
              _buildNavItem(2, "Biblioteca", Icons.library_music, 23, 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, String label, IconData iconData, double width, double height) {
    final isSelected = widget.selectedIndex == index;
    return GestureDetector(
      onTap: () {
        if (widget.onNavTap != null) {
          widget.onNavTap!(index);
        } else {
          // Se não houver callback, volta para HomeShell e seleciona a tab
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 100,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Container(
                width: 100,
                height: 50,
                decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9).withOpacity(0.19),
                    borderRadius: BorderRadius.circular(8)),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: width,
                    height: height,
                    child: FittedBox(
                        fit: BoxFit.contain,
                        child: Icon(iconData, color: Colors.white))),
                const SizedBox(height: 1),
                Text(label,
                    style: GoogleFonts.firaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Calcula a altura do bottom area baseado no estado do player
double getBottomNavAreaHeight(WidgetRef ref) {
  final playerState = ref.watch(playerProvider);
  final hasTrack = playerState.currentTrack != null;
  return 59.0 + (hasTrack ? 78.0 : 0.0);
}
