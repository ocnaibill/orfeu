import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';
import 'package:dio/dio.dart';

// Provider para carregar os dados do álbum
final albumDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(searchControllerProvider).getAlbumDetails(id);
});

class AlbumScreen extends ConsumerWidget {
  final String collectionId;
  final String heroTag;

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
            child: Text("Erro: $err",
                style: const TextStyle(color: Colors.red))),
        data: (albumData) {
          final tracks = albumData['tracks'] as List;

          // Verifica se todas as faixas já estão baixadas
          final bool allDownloaded =
              tracks.every((t) => t['isDownloaded'] == true);

          return CustomScrollView(
            slivers: [
              // Cabeçalho Expansível
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: const Color(0xFF121212),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Color(0xFF121212)],
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
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black54, blurRadius: 20)
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

              // Informações e Ação Principal
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

                      // Botão Inteligente (Baixar ou Tocar)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _handleMainAction(
                              context, ref, tracks, allDownloaded),
                          icon: Icon(
                              allDownloaded
                                  ? Icons.play_arrow_rounded
                                  : Icons.download_rounded,
                              color: Colors.black),
                          label: Text(
                              allDownloaded
                                  ? "Tocar Álbum"
                                  : "Baixar Álbum Completo",
                              style: const TextStyle(
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

  Future<void> _handleMainAction(BuildContext context, WidgetRef ref,
      List tracks, bool allDownloaded) async {
    // Se tudo baixado, toca a primeira música
    if (allDownloaded) {
      if (tracks.isNotEmpty) {
        _playTrack(context, tracks[0]);
      }
      return;
    }

    // Se não, inicia download em massa
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Adicionando álbum à fila..."),
        duration: Duration(seconds: 2)));

    int started = 0;
    for (var track in tracks) {
      if (track['isDownloaded'] == true) continue;

      try {
        // Dispara o download sem esperar conclusão (fire and forget)
        ref.read(searchControllerProvider).smartDownload(track);
        started++;
        // Pequeno delay para não sobrecarregar a API
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print("Erro ao enfileirar ${track['trackName']}: $e");
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$started faixas adicionadas à fila!"),
          backgroundColor: Colors.green));
    }
  }

  void _playTrack(BuildContext context, Map<String, dynamic> track) {
    final playerItem = {
      'filename': track['filename'],
      'display_name': track['trackName'],
      'artist': track['artistName'],
      'album': track['collectionName'],
      'cover_url': track['artworkUrl']
    };
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PlayerScreen(item: playerItem)));
  }
}

class _AlbumTrackItem extends ConsumerWidget {
  final Map<String, dynamic> track;
  const _AlbumTrackItem({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemId = "${track['artistName']}-${track['trackName']}";
    final isNegotiating = ref.watch(processingItemsProvider).contains(itemId);
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
          content: Text("Buscando melhor versão..."),
          duration: Duration(seconds: 1)));

      final filename =
          await ref.read(searchControllerProvider).smartDownload(track);

      if (filename != null) {
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