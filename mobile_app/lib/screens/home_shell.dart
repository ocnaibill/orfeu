import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'home_tab_v2.dart';
import 'player_screen.dart';
import '../services/update_service.dart';
import '../providers.dart';
import '../services/audio_service.dart';

class HomeShell extends ConsumerStatefulWidget {
  final int initialTab;

  const HomeShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _selectedIndex;

  final List<Widget> _screens = [
    const HomeTabV2(),
    const SearchScreen(),
    const LibraryScreen(),
  ];

  Color _dynamicNavbarColor = Colors.black;
  String? _lastProcessedImageUrl;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      // Carrega os favoritos do usuário na inicialização
      ref.read(libraryControllerProvider).fetchFavorites();
    });
  }

  void _checkForUpdates() async {
    // Na web não verificamos updates de app
    if (kIsWeb) return;
    
    final updateService = ref.read(updateServiceProvider);
    final updateInfo = await updateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      _showUpdateDialog(updateInfo, updateService);
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo, UpdateService updateService) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFFD4AF37), size: 28),
            const SizedBox(width: 12),
            Text(
              'Atualização v${updateInfo.latestVersion}',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              updateInfo.releaseNotes,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFD4AF37), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'O download será aberto no navegador.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Depois',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              updateService.openDownloadPage(updateInfo.downloadUrl);
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Baixar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateColorLogic(Map<String, dynamic>? currentTrack) {
    if (currentTrack == null) {
      if (_dynamicNavbarColor != Colors.black) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _dynamicNavbarColor = Colors.black);
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
          _dynamicNavbarColor = palette.vibrantColor?.color ??
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

    final uiColor = currentTrack != null ? _dynamicNavbarColor : Colors.black;
    final double bottomAreaHeight = 59.0 + (currentTrack != null ? 78.0 : 0.0);

    return Scaffold(
      backgroundColor: Colors.black,
      // FIX CRÍTICO: Impede que o player suba quando o teclado abre na SearchScreen
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Conteúdo Principal
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: bottomAreaHeight,
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),

          // Player + Navbar (Fixados embaixo)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentTrack != null)
                  _buildMiniPlayer(context, ref, playerState, uiColor),
                _buildCustomNavbar(context, uiColor),
              ],
            ),
          ),
        ],
      ),
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
          PlayerScreen.createRoute(),
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
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
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
