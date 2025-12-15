import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';

// Provider para buscar a biblioteca completa (arquivos)
final libraryFilesProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/library');
  return response.data;
});

// Provider para buscar apenas favoritos (banco de dados)
final libraryFavoritesProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/users/me/favorites');
  return response.data;
});

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Carrega favoritos ao abrir a tela
    ref.read(libraryControllerProvider).fetchFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text("Sua Biblioteca",
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFD4AF37),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: "Downloads"),
            Tab(text: "Favoritos"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Aba 1: Arquivos no Disco
          _buildTrackList(ref, libraryFilesProvider, "Nenhum arquivo baixado."),
          // Aba 2: Favoritos do Usuário
          _buildTrackList(
              ref, libraryFavoritesProvider, "Nenhum favorito ainda."),
        ],
      ),
    );
  }

  Widget _buildTrackList(
      WidgetRef ref, FutureProvider<List<dynamic>> provider, String emptyMsg) {
    final listAsync = ref.watch(provider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(provider),
      color: const Color(0xFFD4AF37),
      child: listAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return Center(
                child: Text(emptyMsg,
                    style: const TextStyle(color: Colors.white38)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isFlac = song['format'] == 'flac';

              final filenameEncoded = Uri.encodeComponent(song['filename']);
              final coverUrl = song['coverProxyUrl'] ??
                  '$baseUrl/cover?filename=$filenameEncoded';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.white.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  onTap: () {
                    // Toca a lista inteira a partir desta música
                    _playQueue(
                        context, songs.cast<Map<String, dynamic>>(), index);
                  },
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      coverUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 50,
                          height: 50,
                          color: Colors.white10,
                          child: const Icon(Icons.music_note,
                              color: Colors.white24)),
                    ),
                  ),
                  title: Text(song['display_name'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: Text(song['artist'],
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: isFlac
                      ? const Icon(Icons.high_quality,
                          color: Color(0xFFD4AF37), size: 18)
                      : null,
                ),
              );
            },
          );
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        error: (err, stack) => Center(
            child:
                Text('Erro: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  void _playQueue(
      BuildContext context, List<Map<String, dynamic>> queue, int index) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(
                  queue: queue,
                  initialIndex: index,
                )));
  }
}
