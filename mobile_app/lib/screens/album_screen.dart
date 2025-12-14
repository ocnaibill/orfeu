import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';

// Provider temporário para carregar os dados do álbum ao abrir a tela
final albumDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(searchControllerProvider).getAlbumDetails(id);
});

class AlbumScreen extends ConsumerWidget {
  final String collectionId;
  final String heroTag; // Para animação da capa

  const AlbumScreen(
      {super.key, required this.collectionId, required this.heroTag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumAsync = ref.watch(albumDetailsProvider(collectionId));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: albumAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        error: (err, stack) => Center(
            child:
                Text("Erro: $err", style: const TextStyle(color: Colors.red))),
        data: (albumData) {
          final tracks = albumData['tracks'] as List;

          return CustomScrollView(
            slivers: [
              // Cabeçalho Expansível com a Capa
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: const Color(0xFF121212),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, const Color(0xFF121212)],
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60.0),
                        child: Hero(
                          tag: heroTag,
                          child: Container(
                            height: 180,
                            width: 180,
                            decoration: BoxDecoration(
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 20)
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(albumData['artworkUrl'],
                                  fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Informações do Álbum e Botão "Play All"
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        albumData['collectionName'],
                        style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      Text(
                        "${albumData['artistName']} • ${albumData['year']}",
                        style: GoogleFonts.outfit(
                            fontSize: 16, color: Colors.white54),
                      ),
                      const SizedBox(height: 20),

                      // Botão Play (Por enquanto toca a primeira, futuramente fila)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (tracks.isNotEmpty) {
                              _handlePlayOrDownload(context, ref, tracks[0]);
                            }
                          },
                          icon:
                              const Icon(Icons.play_arrow, color: Colors.black),
                          label: const Text("Tocar Álbum",
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Lista de Músicas
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    return _AlbumTrackItem(track: track);
                  },
                  childCount: tracks.length,
                ),
              ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          );
        },
      ),
    );
  }

  void _handlePlayOrDownload(
      BuildContext context, WidgetRef ref, dynamic item) {
    // Reutiliza lógica similar à do SearchScreen, mas simplificada para este contexto
    // Idealmente, extrairíamos isso para um Mixin ou Widget separado
  }
}

class _AlbumTrackItem extends ConsumerWidget {
  final Map<String, dynamic> track;
  const _AlbumTrackItem({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Identifica download e processamento
    final itemId = "${track['artistName']}-${track['trackName']}";
    final isNegotiating = ref.watch(processingItemsProvider).contains(itemId);

    // Tentativa de achar o filename se já estiver baixando
    // (Nota: aqui não temos o filename direto da API de album, então o status bar pode não aparecer
    // até que o usuário clique e o smartDownload retorne o nome. Melhoria futura.)

    final bool isDownloaded = track['isDownloaded'] == true;

    return ListTile(
      leading: Text(
        "${track['trackNumber']}",
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      ),
      title: Text(
        track['trackName'],
        style: TextStyle(
            color: isDownloaded ? const Color(0xFFD4AF37) : Colors.white,
            fontWeight: isDownloaded ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        _formatDuration(track['durationMs'] ?? 0),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: isNegotiating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFD4AF37)))
          : isDownloaded
              ? const Icon(Icons.play_circle_outline, color: Color(0xFFD4AF37))
              : const Icon(Icons.add_circle_outline, color: Colors.white24),
      onTap: () => _handlePlayOrDownload(context, ref),
    );
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    return "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  Future<void> _handlePlayOrDownload(
      BuildContext context, WidgetRef ref) async {
    if (track['isDownloaded'] == true && track['filename'] != null) {
      _openPlayer(context, track['filename']);
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Buscando faixa..."), duration: Duration(seconds: 1)));
      final filename =
          await ref.read(searchControllerProvider).smartDownload(track);
      if (filename != null) {
        // Monitora download e abre player (Lógica simplificada aqui)
        _waitForDownloadAndPlay(context, ref, filename);
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    }
  }

  void _waitForDownloadAndPlay(
      BuildContext context, WidgetRef ref, String filename) async {
    final dio = ref.read(dioProvider);
    bool isReady = false;
    int attempts = 0;
    while (!isReady && attempts < 600) {
      if (!context.mounted) return;
      await Future.delayed(const Duration(seconds: 1));
      attempts++;
      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        if (resp.data['state'] == 'Completed') {
          isReady = true;
          _openPlayer(context, filename);
        }
      } catch (e) {}
    }
  }

  void _openPlayer(BuildContext context, String filename) {
    final playerItem = {
      'filename': filename,
      'display_name': track['trackName'],
      'artist': track['artistName'],
      'album': track['collectionName'],
      'cover_url': track['artworkUrl']
    };
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PlayerScreen(item: playerItem)));
  }
}
