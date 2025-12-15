import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'playlist_detail_screen.dart';

final userPlaylistsFuture = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/users/me/playlists');
  return response.data;
});

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(userPlaylistsFuture);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text("Sua Biblioteca",
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFD4AF37)),
            onPressed: () => _showCreatePlaylistDialog(context, ref),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(userPlaylistsFuture),
        color: const Color(0xFFD4AF37),
        child: CustomScrollView(
          slivers: [
            // Espaço
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Grid de Coleções
            playlistsAsync.when(
              data: (playlists) {
                // Item 0 é sempre Favoritos
                final allItems = [
                  {'id': 'fav', 'name': 'Músicas Curtidas', 'type': 'favorite'},
                  ...playlists
                ];

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = allItems[index];
                        return _LibraryCard(item: item);
                      },
                      childCount: allItems.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFD4AF37)))),
              error: (err, stack) => SliverToBoxAdapter(
                  child: Center(
                      child: Text("Erro: $err",
                          style: const TextStyle(color: Colors.red)))),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text("Nova Playlist", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Nome da playlist",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD4AF37))),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37)),
            child: const Text("Criar", style: TextStyle(color: Colors.black)),
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await ref
                    .read(libraryControllerProvider)
                    .createPlaylist(controller.text, false);
                ref.refresh(userPlaylistsFuture); // Atualiza lista
                Navigator.pop(ctx);
              }
            },
          )
        ],
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _LibraryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final bool isFavorite = item['type'] == 'favorite';

    return GestureDetector(
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(
                      title: item['name'],
                      playlistId:
                          isFavorite ? null : item['id'], // Null ID = Favoritos
                    )));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
                gradient: isFavorite
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)])
                    : null,
              ),
              child: Center(
                child: Icon(
                  isFavorite ? Icons.favorite : Icons.music_note,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              // TODO: Futuro - Implementar Mosaico aqui puxando as capas das tracks
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item['name'],
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            isFavorite ? "Automática" : "Playlist",
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
