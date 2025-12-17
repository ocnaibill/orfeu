import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:ui';
import '../providers.dart';
import '../services/audio_service.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

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

  // Rota com transição fluida (Slide Up)
  static Route createRoute({
    Map<String, dynamic>? item,
    List<Map<String, dynamic>>? queue,
    int initialIndex = 0,
    bool shuffle = false,
  }) {
    return PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => PlayerScreen(
        item: item,
        queue: queue,
        initialIndex: initialIndex,
        shuffle: shuffle,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  List<Color> _gradientColors = [Colors.black, const Color(0xFF1A1A1A)];
  bool _colorsExtracted = false;

  late AnimationController _bgController;
  late Animation<Alignment> _topAlignmentAnim;
  late Animation<Alignment> _bottomAlignmentAnim;

  // Controle local do slider para evitar "pulos" enquanto arrasta
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat(reverse: true);

    _topAlignmentAnim = TweenSequence<Alignment>([
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
          weight: 1),
    ]).animate(_bgController);

    _bottomAlignmentAnim = TweenSequence<Alignment>([
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
          weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
          weight: 1),
    ]).animate(_bgController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPlayback();
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
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
      playerNotifier.playContext(
          queue: targetQueue,
          initialIndex: widget.initialIndex,
          shuffle: widget.shuffle);
    }
  }

  Future<void> _extractColors(String? url) async {
    if (url == null || url.isEmpty || _colorsExtracted) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          final darkVibrant = palette.darkVibrantColor?.color ?? Colors.black;
          final vibrant =
              palette.vibrantColor?.color ?? const Color(0xFF4A00E0);
          final muted = palette.mutedColor?.color ?? const Color(0xFF1A1A1A);

          _gradientColors = [
            darkVibrant.withOpacity(0.8),
            vibrant.withOpacity(0.6),
            muted.withOpacity(0.8),
            Colors.black
          ];
          _colorsExtracted = true;
        });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final currentTrack = playerState.currentTrack;

    if (currentTrack != null) {
      final coverUrl = currentTrack['imageUrl'] ?? currentTrack['artworkUrl'];
      _extractColors(coverUrl);
    }

    if (currentTrack == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
    }

    final coverUrl =
        currentTrack['imageUrl'] ?? currentTrack['artworkUrl'] ?? '';
    final title =
        currentTrack['trackName'] ?? currentTrack['title'] ?? 'Sem Título';
    final artist =
        currentTrack['artistName'] ?? currentTrack['artist'] ?? 'Desconhecido';

    // --- LÓGICA DE DURAÇÃO ROBUSTA ---
    // Se o player ainda não carregou a duração (é 0), tentamos usar o metadado da música
    // Isso conserta o bug de "0:00" e barra travada no início
    Duration duration = playerState.duration;
    if (duration.inMilliseconds == 0) {
      final metaDur = currentTrack['durationMs'] ?? currentTrack['duration'];
      if (metaDur != null) {
        if (metaDur is int)
          duration = Duration(milliseconds: metaDur);
        else if (metaDur is double)
          duration = Duration(milliseconds: metaDur.toInt());
        else if (metaDur is String)
          duration = Duration(milliseconds: int.tryParse(metaDur) ?? 0);
      }
    }

    final position = playerState.position;

    return Dismissible(
      key: const Key('player_screen_dismiss'),
      direction: DismissDirection.down,
      onDismissed: (_) {
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Fundo Animado
            AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: _topAlignmentAnim.value,
                      end: _bottomAlignmentAnim.value,
                      colors: _gradientColors,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                );
              },
            ),

            // 2. Conteúdo Principal
            SizedBox.expand(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  height: 852,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // COVER
                      Positioned(
                        top: 140,
                        child: Hero(
                          tag: 'player_cover',
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10))
                              ],
                              image: coverUrl.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(coverUrl),
                                      fit: BoxFit.cover)
                                  : null,
                              color: Colors.grey[900],
                            ),
                            child: coverUrl.isEmpty
                                ? const Icon(Icons.music_note,
                                    color: Colors.white24, size: 80)
                                : null,
                          ),
                        ),
                      ),

                      // TÍTULO
                      Positioned(
                        top: 420,
                        left: 33,
                        right: 80,
                        child: GestureDetector(
                          onTap: () =>
                              _showNavigationModal(context, currentTrack),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),

                      // ARTISTA
                      Positioned(
                        top: 450,
                        left: 33,
                        right: 80,
                        child: GestureDetector(
                          onTap: () =>
                              _showNavigationModal(context, currentTrack),
                          child: Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                color: Colors.white.withOpacity(0.9)),
                          ),
                        ),
                      ),

                      // AÇÕES LATERAIS
                      Positioned(
                        top: 430,
                        right: 33,
                        child: Builder(builder: (context) {
                          // Watch para reagir a mudanças nos favoritos
                          ref.watch(favoriteTracksDataProvider);
                          final libraryController = ref.read(libraryControllerProvider);
                          final isFavorite = libraryController.isFavorite(currentTrack);

                          return Row(
                            children: [
                              _buildGlassActionButton(
                                  icon: isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite ? Colors.red : null,
                                  onTap: () {
                                    ref
                                        .read(libraryControllerProvider)
                                        .toggleFavorite(currentTrack);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(isFavorite
                                                ? "Removido das curtidas"
                                                : "Adicionado às curtidas")));
                                  }),
                              const SizedBox(width: 10),
                              _buildGlassActionButton(
                                  icon: Icons.more_horiz,
                                  onTap: () =>
                                      _showOptionsModal(context, currentTrack)),
                            ],
                          );
                        }),
                      ),

                      // --- BARRA DE PROGRESSO (SLIDER CUSTOMIZADO) ---
                      Positioned(
                        top: 510,
                        left: 33,
                        right: 33,
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 7.0,
                                // ThumbShape com raio 0 para ficar invisível/reto como pedido ("line... arredondada")
                                // Se quiser bolinha, aumente o radius.
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 0.0,
                                    pressedElevation: 0),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 15.0), // Área de toque
                                activeTrackColor: Colors.white,
                                inactiveTrackColor:
                                    Colors.white.withOpacity(0.4),
                                trackShape:
                                    const RoundedRectSliderTrackShape(),
                              ),
                              child: Slider(
                                value: _isDragging
                                    ? _dragValue
                                    : position.inMilliseconds
                                        .toDouble()
                                        .clamp(
                                            0.0,
                                            duration.inMilliseconds
                                                .toDouble()),
                                min: 0.0,
                                max: duration.inMilliseconds.toDouble() > 0
                                    ? duration.inMilliseconds.toDouble()
                                    : 1.0, // Evita divisão por zero
                                onChangeStart: (value) {
                                  setState(() {
                                    _isDragging = true;
                                    _dragValue = value;
                                  });
                                },
                                onChanged: (value) {
                                  setState(() {
                                    _dragValue = value;
                                  });
                                },
                                onChangeEnd: (value) {
                                  setState(() {
                                    _isDragging = false;
                                  });
                                  notifier.seek(
                                      Duration(milliseconds: value.toInt()));
                                },
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(position),
                                    style: GoogleFonts.firaSans(
                                        color: Colors.white, fontSize: 12)),
                                Text(
                                    "-${_formatDuration(duration - position)}",
                                    style: GoogleFonts.firaSans(
                                        color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // QUALIDADE
                      Positioned(
                        top: 545,
                        child: GestureDetector(
                          onTap: () => _showQualitySelector(context, notifier),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.white24)),
                            child: Text(
                              notifier.currentQuality.toUpperCase(),
                              style: GoogleFonts.firaSans(
                                  color: const Color(0xFFD4AF37),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),

                      // CONTROLES DE MÍDIA
                      Positioned(
                        top: 600,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded,
                                  color: Colors.white, size: 40),
                              onPressed: notifier.previous,
                            ),
                            const SizedBox(width: 20),
                            Container(
                              height: 70,
                              width: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                              ),
                              child: IconButton(
                                icon: Icon(
                                    playerState.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 50),
                                onPressed: notifier.togglePlay,
                              ),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded,
                                  color: Colors.white, size: 40),
                              onPressed: notifier.next,
                            ),
                          ],
                        ),
                      ),

                      // BOTÕES INFERIORES
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.shuffle,
                                  color: playerState.isShuffleEnabled 
                                      ? const Color(0xFFD4AF37) 
                                      : Colors.white54, 
                                  size: 24),
                              onPressed: () {
                                ref.read(playerProvider.notifier).toggleShuffle();
                              },
                            ),
                            const SizedBox(width: 20),
                            _buildBottomButton(Icons.lyrics, "Letras", () {}),
                            const SizedBox(width: 40),
                            _buildBottomButton(
                                Icons.speaker_group, "Saída", () {}),
                            const SizedBox(width: 40),
                            _buildBottomButton(Icons.queue_music, "Fila", () {
                              _showQueueModal(
                                  context, playerState.currentTrack, playerState.queue);
                            }),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: Icon(
                                  playerState.loopMode == LoopMode.one 
                                      ? Icons.repeat_one 
                                      : Icons.repeat,
                                  color: playerState.loopMode != LoopMode.off 
                                      ? const Color(0xFFD4AF37) 
                                      : Colors.white54, 
                                  size: 24),
                              onPressed: () {
                                ref.read(playerProvider.notifier).toggleLoop();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. BOTÃO DE VOLTAR (NO TOPO DA PILHA)
            Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ... (Widgets auxiliares mantidos iguais) ...
  Widget _buildGlassActionButton(
      {required IconData icon, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _gradientColors[1].withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 28),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  void _showNavigationModal(BuildContext context, Map<String, dynamic> track) {
    final artistName = track['artistName'] ?? track['artist'] ?? 'Unknown';
    final albumName = track['collectionName'] ?? track['album'] ?? 'Unknown';
    final albumId = track['albumId'] ?? track['collectionId'];
    final artistId = track['artistId'];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Ir para",
                  style: GoogleFonts.firaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title: Text("Ver Artista ($artistName)",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ArtistScreen(
                              artist: {
                                "artistName": artistName,
                                "artistId": artistId,
                              })));
                },
              ),
              ListTile(
                leading: const Icon(Icons.album, color: Colors.white),
                title: Text(
                    "Ver Álbum ($albumName)",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (albumId != null) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                AlbumScreen(collectionId: albumId.toString())));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("ID do álbum não disponível")));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOptionsModal(BuildContext context, Map<String, dynamic> track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.favorite_border, color: Colors.white),
                title: Text("Adicionar às curtidas",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                onTap: () {
                  ref.read(libraryControllerProvider).toggleFavorite(track);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: Text("Adicionar a uma playlist",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPlaylistSelectionModal(context, track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: Text("Compartilhar",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistSelectionModal(BuildContext context, Map<String, dynamic> track) {
    final playlists = ref.read(userPlaylistsProvider);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Adicionar a playlist",
                  style: GoogleFonts.firaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    "Você ainda não tem playlists.\nCrie uma na sua biblioteca!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaSans(color: Colors.white70),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      // Ignora "Músicas Curtidas" se existir como playlist
                      if (playlist['name']?.toLowerCase() == 'músicas curtidas') {
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white10,
                          ),
                          child: playlist['cover_url'] != null && playlist['cover_url'].toString().isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    playlist['cover_url'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.queue_music, color: Colors.white54),
                                  ),
                                )
                              : const Icon(Icons.queue_music, color: Colors.white54),
                        ),
                        title: Text(
                          playlist['name'] ?? 'Playlist',
                          style: GoogleFonts.firaSans(color: Colors.white),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final success = await ref
                              .read(libraryControllerProvider)
                              .addTrackToPlaylist(playlist['id'], track);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success
                                    ? 'Adicionada a "${playlist['name']}"'
                                    : 'Erro ao adicionar'),
                                backgroundColor: success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showQueueModal(BuildContext context, Map<String, dynamic>? current,
      List<dynamic> queue) {
    final playerState = ref.read(playerProvider);
    final currentIndex = playerState.currentIndex;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (ctx, scrollController) {
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Fila de Reprodução",
                            style: GoogleFonts.firaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text("${queue.length} músicas",
                            style: GoogleFonts.firaSans(
                                fontSize: 14,
                                color: Colors.white54)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white24),
                    if (queue.isEmpty)
                      const Expanded(
                          child: Center(
                              child: Text("Fila vazia",
                                  style: TextStyle(color: Colors.white54))))
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: queue.length,
                          itemBuilder: (context, index) {
                            final track = queue[index] as Map<String, dynamic>;
                            final isPlaying = index == currentIndex;
                            final trackName = track['trackName'] ?? 
                                track['title'] ?? 
                                track['display_name'] ?? 
                                'Música';
                            final artistName = track['artistName'] ?? 
                                track['artist'] ?? 
                                'Artista';
                            
                            return ListTile(
                              leading: isPlaying
                                  ? const Icon(Icons.graphic_eq, color: Color(0xFFD4AF37))
                                  : Text("${index + 1}",
                                      style: GoogleFonts.firaSans(
                                          color: Colors.white54, fontSize: 14)),
                              title: Text(
                                trackName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.firaSans(
                                    color: isPlaying
                                        ? const Color(0xFFD4AF37)
                                        : Colors.white,
                                    fontWeight: isPlaying 
                                        ? FontWeight.bold 
                                        : FontWeight.normal),
                              ),
                              subtitle: Text(
                                artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.firaSans(
                                    color: Colors.white54, fontSize: 12),
                              ),
                              trailing: isPlaying
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.play_arrow, 
                                          color: Colors.white54),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        ref.read(playerProvider.notifier)
                                            .skipToIndex(index);
                                      },
                                    ),
                              onTap: isPlaying ? null : () {
                                Navigator.pop(ctx);
                                ref.read(playerProvider.notifier).skipToIndex(index);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            });
      },
    );
  }

  void _showQualitySelector(
      BuildContext context, AudioPlayerNotifier notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['low', 'medium', 'high', 'lossless'].map((q) {
              return ListTile(
                title: Text(q.toUpperCase(),
                    style: const TextStyle(color: Colors.white)),
                trailing: notifier.currentQuality == q
                    ? const Icon(Icons.check, color: Color(0xFFD4AF37))
                    : null,
                onTap: () {
                  notifier.changeQuality(q);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 0) return "0:00";
    return "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }
}
