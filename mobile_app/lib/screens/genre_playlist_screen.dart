import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers.dart';
import 'player_screen.dart';

/// Tela que mostra as top tracks de um gênero musical.
/// Funciona como uma "playlist dinâmica" baseada em buscas do Tidal.
class GenrePlaylistScreen extends ConsumerStatefulWidget {
  final String genreName;
  final Color genreColor;
  final String? searchQuery;
  final String? playlistId;

  const GenrePlaylistScreen({
    super.key,
    required this.genreName,
    required this.genreColor,
    this.searchQuery,
    this.playlistId,
  });

  @override
  ConsumerState<GenrePlaylistScreen> createState() => _GenrePlaylistScreenState();
}

class _GenrePlaylistScreenState extends ConsumerState<GenrePlaylistScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tracks = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.get('/genres/${Uri.encodeComponent(widget.genreName)}/tracks?limit=100');
      
      if (response != null && response['tracks'] != null) {
        setState(() {
          _tracks = List<Map<String, dynamic>>.from(response['tracks']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Nenhuma música encontrada';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar músicas: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;

    final playerNotifier = ref.read(playerProvider.notifier);
    
    List<Map<String, dynamic>> queue = List.from(_tracks);
    if (shuffle) {
      queue.shuffle();
    }
    
    // Primeira música pode não ter filename, vamos preparar
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        shuffle ? "Reproduzindo aleatoriamente..." : "Reproduzindo ${widget.genreName}...",
        style: const TextStyle(color: Colors.black),
      ),
      backgroundColor: const Color(0xFFD9D9D9),
      duration: const Duration(seconds: 2),
    ));

    try {
      final firstTrack = queue[0];
      
      // Tenta baixar a primeira música se necessário
      if (firstTrack['filename'] == null) {
        final searchCtrl = ref.read(searchControllerProvider);
        final filename = await searchCtrl.smartDownload(firstTrack);
        if (filename != null) {
          queue[0] = {...firstTrack, 'filename': filename};
        }
      }
      
      playerNotifier.playContext(queue: queue, initialIndex: 0);
      
      // Pré-download da próxima
      _preloadNextTrack(queue, 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao reproduzir: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _playTrack(Map<String, dynamic> track, int index) async {
    final playerNotifier = ref.read(playerProvider.notifier);

    // Se já tem filename, toca direto
    if (track['filename'] != null) {
      playerNotifier.playContext(queue: _tracks, initialIndex: index);
      return;
    }

    // Se não tem, tenta baixar/resolver primeiro
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Preparando música...", style: TextStyle(color: Colors.black)),
      backgroundColor: Color(0xFFD9D9D9),
      duration: Duration(seconds: 2),
    ));

    try {
      final searchCtrl = ref.read(searchControllerProvider);
      final filename = await searchCtrl.smartDownload(track);

      if (filename != null && mounted) {
        // Atualiza a lista local com o filename
        setState(() {
          _tracks[index] = {...track, 'filename': filename};
        });

        playerNotifier.playContext(queue: _tracks, initialIndex: index);
        
        // Pré-download da próxima
        _preloadNextTrack(_tracks, index);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao reproduzir: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _preloadNextTrack(List<Map<String, dynamic>> queue, int currentIndex) async {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= queue.length) return;
    
    final nextTrack = queue[nextIndex];
    if (nextTrack['filename'] != null) return;
    
    try {
      print("📥 Pré-carregando próxima: ${nextTrack['trackName']}");
      await ref.read(searchControllerProvider).smartDownload(nextTrack);
    } catch (e) {
      print("⚠️ Erro ao pré-carregar próxima música: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // Header com gradiente
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: widget.genreColor.withOpacity(0.8),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.genreName,
                style: GoogleFonts.firaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.genreColor,
                      widget.genreColor.withOpacity(0.6),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.music_note,
                    size: 80,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),

          // Botões de ação
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  // Play All
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _tracks.isEmpty ? null : () => _playAll(),
                      icon: const Icon(Icons.play_arrow, color: Colors.black),
                      label: Text(
                        "Tocar Tudo",
                        style: GoogleFonts.firaSans(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Shuffle
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _tracks.isEmpty ? null : () => _playAll(shuffle: true),
                      icon: const Icon(Icons.shuffle, color: Colors.white),
                      label: Text(
                        "Aleatório",
                        style: GoogleFonts.firaSans(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _isLoading 
                    ? "Carregando..." 
                    : "${_tracks.length} músicas",
                style: GoogleFonts.firaSans(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Lista de tracks ou loading/error
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
              ),
            )
          else if (_errorMessage.isNotEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.grey, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      style: GoogleFonts.firaSans(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadTracks,
                      child: const Text("Tentar novamente"),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return _buildTrackTile(track, index);
                },
                childCount: _tracks.length,
              ),
            ),

          // Espaço para o mini player
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildTrackTile(Map<String, dynamic> track, int index) {
    final title = track['trackName'] ?? track['title'] ?? 'Música';
    final artist = track['artistName'] ?? track['artist'] ?? 'Artista';
    final artworkUrl = track['artworkUrl'] ?? '';
    final hasFile = track['filename'] != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Número da track
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: GoogleFonts.firaSans(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: artworkUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: artworkUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.grey),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.grey),
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note, color: Colors.grey),
                  ),
          ),
        ],
      ),
      title: Text(
        title,
        style: GoogleFonts.firaSans(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        artist,
        style: GoogleFonts.firaSans(
          color: Colors.grey,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador de disponível localmente
          if (hasFile)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.download_done, color: Color(0xFFD4AF37), size: 18),
            ),
          // Botão de play
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
            onPressed: () => _playTrack(track, index),
          ),
        ],
      ),
      onTap: () => _playTrack(track, index),
    );
  }
}
