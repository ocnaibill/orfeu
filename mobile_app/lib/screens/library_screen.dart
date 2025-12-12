import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers.dart'; // Importa dioProvider e baseUrl
import 'player_screen.dart';

// Provider para buscar a biblioteca
final libraryProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/library');
  return response.data;
});

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent, // Usa o fundo do HomeShell
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Sua Biblioteca"),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(libraryProvider),
        color: const Color(0xFFD4AF37),
        child: libraryAsync.when(
          data: (songs) {
            if (songs.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  const Center(
                    child: Column(
                      children: [
                        Icon(Icons.music_off, size: 60, color: Colors.white24),
                        SizedBox(height: 10),
                        Text("Nada aqui ainda.",
                            style: TextStyle(color: Colors.white38)),
                        Text("Baixe músicas na aba Buscar.",
                            style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final isFlac = song['format'] == 'flac';

                // Url da capa para o avatar
                final filenameEncoded = Uri.encodeComponent(song['filename']);
                final coverUrl = '$baseUrl/cover?filename=$filenameEncoded';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PlayerScreen(item: song))),
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
                              color: Colors.white24),
                        ),
                      ),
                    ),
                    title: Text(song['display_name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text(song['artist'],
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
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
              child: Text('Erro: $err',
                  style: const TextStyle(color: Colors.red))),
        ),
      ),
    );
  }
}
