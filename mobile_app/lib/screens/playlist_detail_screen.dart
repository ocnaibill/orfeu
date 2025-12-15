import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';

// Provider temporário para carregar detalhes da playlist
final playlistDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  return ref.read(libraryControllerProvider).getPlaylistDetails(id);
});

// Provider especial para FAVORITOS (que é uma lista direta)
final favoritesListProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/users/me/favorites');
  return response.data;
});

class PlaylistDetailScreen extends ConsumerWidget {
  final String title;
  final int? playlistId; // Se null, assume que é a tela de Favoritos
  final String? coverUrl; // Para animação Hero (opcional)

  const PlaylistDetailScreen(
      {super.key, required this.title, this.playlistId, this.coverUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Decide qual provider usar
    final AsyncValue<dynamic> dataAsync = playlistId != null
        ? ref.watch(playlistDetailsProvider(playlistId!))
        : ref.watch(favoritesListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: dataAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        error: (err, stack) => Center(
            child:
                Text("Erro: $err", style: const TextStyle(color: Colors.red))),
        data: (data) {
          // Normaliza os dados (Favoritos retorna lista direta, Playlist retorna objeto)
          final List<dynamic> rawTracks =
              playlistId != null ? data['tracks'] : data;
          final tracks =
              rawTracks.map((e) => e as Map<String, dynamic>).toList();

          return CustomScrollView(
            slivers: [
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
                        colors: [
                          playlistId == null
                              ? Colors.redAccent.withOpacity(0.2)
                              : Colors.blueGrey.withOpacity(0.2),
                          const Color(0xFF121212)
                        ],
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Capa (Mosaico ou Ícone)
                            Container(
                              height: 140,
                              width: 140,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black45, blurRadius: 20)
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildCover(tracks),
                            ),
                            const SizedBox(height: 16),
                            Text(title,
                                style: GoogleFonts.outfit(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            Text("${tracks.length} músicas",
                                style: GoogleFonts.outfit(
                                    fontSize: 14, color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Botão Play e Shuffle
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: tracks.isEmpty
                            ? null
                            : () => _playAll(context, tracks),
                        icon: const Icon(Icons.play_arrow, color: Colors.black),
                        label: const Text("Tocar",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37)),
                      ),
                      const SizedBox(width: 16),
                      IconButton.filled(
                        onPressed: tracks.isEmpty
                            ? null
                            : () => _playAll(context, tracks, shuffle: true),
                        icon:
                            const Icon(Icons.shuffle, color: Color(0xFFD4AF37)),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.white10),
                      )
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    // Recupera URL da capa via proxy
                    final String? cover = track['coverProxyUrl'];

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: cover != null
                            ? Image.network(cover,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.music_note,
                                    color: Colors.white24))
                            : const Icon(Icons.music_note,
                                color: Colors.white24, size: 40),
                      ),
                      title: Text(track['display_name'],
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(track['artist'],
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                          maxLines: 1),
                      onTap: () =>
                          _playAll(context, tracks, initialIndex: index),
                    );
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

  // Gera o mosaico de capas
  Widget _buildCover(List<Map<String, dynamic>> tracks) {
    // Se for Favoritos, ícone de coração
    if (playlistId == null) {
      return const Icon(Icons.favorite, size: 60, color: Colors.white);
    }

    // Tenta pegar até 4 capas
    final covers = tracks
        .map((t) => t['coverProxyUrl'])
        .where((url) => url != null)
        .take(4)
        .toList();

    if (covers.isEmpty)
      return const Icon(Icons.music_note, size: 60, color: Colors.white24);

    // Se tiver menos que 4, mostra a primeira cheia
    if (covers.length < 4) {
      return Image.network(covers[0], fit: BoxFit.cover);
    }

    // Grid 2x2
    return Column(
      children: [
        Expanded(
            child: Row(children: [
          Expanded(child: Image.network(covers[0], fit: BoxFit.cover)),
          Expanded(child: Image.network(covers[1], fit: BoxFit.cover))
        ])),
        Expanded(
            child: Row(children: [
          Expanded(child: Image.network(covers[2], fit: BoxFit.cover)),
          Expanded(child: Image.network(covers[3], fit: BoxFit.cover))
        ])),
      ],
    );
  }

  void _playAll(BuildContext context, List<Map<String, dynamic>> tracks,
      {int initialIndex = 0, bool shuffle = false}) {
    // A fila do player espera o campo 'filename', que já temos aqui.
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(
                  queue: tracks,
                  initialIndex: initialIndex,
                  shuffle: shuffle,
                )));
  }
}
