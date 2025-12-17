import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io' show Platform;
import 'package:palette_generator/palette_generator.dart'; // <--- OBRIGATÓRIO: flutter pub add palette_generator
import 'search_screen.dart';
import 'library_screen.dart';
import 'home_tab_v2.dart';
import 'player_screen.dart';
import '../services/update_service.dart';
import '../providers.dart';
import '../services/audio_service.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeTabV2(),
    const SearchScreen(),
    const LibraryScreen(),
  ];

  // Estado local para a cor extraída da capa
  Color _dynamicNavbarColor = Colors.black;
  String? _lastProcessedImageUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  void _checkForUpdates() async {
    if (Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isMacOS) {
      final updateService = ref.read(updateServiceProvider);
      final updateInfo = await updateService.checkForUpdate();
      if (updateInfo != null && mounted) {
        // Dialog update...
      }
    }
  }

  /// LÓGICA DE EXTRAÇÃO DE COR (Client-Side)
  /// Pega a cor "na hora" analisando a imagem
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

    // Prioriza URL da capa para extração
    String coverUrl =
        currentTrack['imageUrl'] ?? currentTrack['artworkUrl'] ?? '';
    if (coverUrl.isEmpty && currentTrack['filename'] != null) {
      final encoded = Uri.encodeComponent(currentTrack['filename']);
      coverUrl = '$baseUrl/cover?filename=$encoded';
    }

    if (coverUrl.isEmpty) return;

    // Se a imagem mudou, extrai a nova cor
    if (coverUrl != _lastProcessedImageUrl) {
      _lastProcessedImageUrl = coverUrl;
      _extractPalette(coverUrl);
    }
  }

  Future<void> _extractPalette(String url) async {
    try {
      final provider = NetworkImage(url);
      // Gera a paleta a partir da imagem
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 20, // Otimização
      );

      if (mounted && _lastProcessedImageUrl == url) {
        setState(() {
          // Tenta pegar a cor mais vibrante/destacada.
          // Se não achar, tenta a dominante.
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

    // Dispara a análise de cor
    _updateColorLogic(currentTrack);

    // Usa a cor extraída ou preto
    final uiColor = currentTrack != null ? _dynamicNavbarColor : Colors.black;
    final double bottomAreaHeight = 59.0 + (currentTrack != null ? 78.0 : 0.0);

    return Scaffold(
      backgroundColor: Colors.black,
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

  /// Verifica se uma cor é considerada clara (luminosidade alta)
  bool _isLightColor(Color color) {
    // Usa fórmula de luminância relativa
    // https://www.w3.org/TR/WCAG20/#relativeluminancedef
    final luminance = color.computeLuminance();
    return luminance > 0.5; // Threshold para cores claras
  }

  Widget _buildMiniPlayer(BuildContext context, WidgetRef ref,
      PlayerState playerState, Color backgroundColor) {
    final track = playerState.currentTrack!;
    final isPlaying = playerState.isPlaying;
    
    // Detecta se a cor de fundo é clara para adaptar ícones/texto
    final isLight = _isLightColor(backgroundColor);
    final contentColor = isLight ? Colors.black : Colors.white;
    final secondaryColor = isLight ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.7);

    // Correção: Fallback para display_name para evitar "Desconhecido"
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
        // ATUALIZADO: Usa a rota com transição fluida (Slide Up)
        // Isso combina com o Dismissible (Slide Down) na PlayerScreen
        Navigator.of(context).push(
          PlayerScreen.createRoute(),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700), // Transição suave da cor
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
            // Capa do Álbum
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
            // Informações
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
                          color: contentColor,
                          height: 1.0)),
                  const SizedBox(height: 3),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: secondaryColor,
                          height: 1.0)),
                ],
              ),
            ),
            // Controles
            Positioned(
              right: 21,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.skip_previous_rounded,
                        color: contentColor, size: 28),
                    onPressed: () =>
                        ref.read(playerProvider.notifier).previous(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: contentColor,
                        size: 32),
                    onPressed: () =>
                        ref.read(playerProvider.notifier).togglePlay(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.skip_next_rounded,
                        color: contentColor, size: 28),
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
      duration: const Duration(
          milliseconds: 700), // Mesma duração do miniplayer para sincronia
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