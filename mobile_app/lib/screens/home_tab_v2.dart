import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/home_cards.dart';
import '../services/download_manager.dart';
import 'album_screen.dart';
import 'player_screen.dart';
import 'playlist_detail_screen.dart';
import 'profile_screen.dart';

class HomeTabV2 extends ConsumerWidget {
  const HomeTabV2({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return "Bom dia,";
    if (hour >= 12 && hour < 18) return "Boa tarde,";
    if (hour >= 18 && hour < 24) return "Boa noite,";
    return "Boa madrugada,";
  }

  // Função auxiliar para recarregar dados
  void _refreshData(WidgetRef ref) {
    print("🔄 Home: Recarregando dados...");
    ref.invalidate(homeNewReleasesProvider);
    ref.invalidate(homeContinueListeningProvider);
    ref.invalidate(homeRecommendationsProvider);
    ref.invalidate(homeDiscoverProvider);
    ref.invalidate(homeTrajectoryProvider);
    ref.invalidate(downloadedTracksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(authProvider).username ?? "Visitante";
    final isOffline = ref.watch(isOfflineProvider);
    final downloadedTracks = ref.watch(downloadedTracksProvider);

    final newReleases = ref.watch(homeNewReleasesProvider);
    final continueListening = ref.watch(homeContinueListeningProvider);
    final recommendations = ref.watch(homeRecommendationsProvider);
    final discover = ref.watch(homeDiscoverProvider);
    final trajectory = ref.watch(homeTrajectoryProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshData(ref);
          await Future.delayed(const Duration(seconds: 1));
        },
        color: const Color(0xFFD4AF37),
        backgroundColor: const Color(0xFF1A1A1A),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              Padding(
                padding: const EdgeInsets.only(top: 54, left: 33, right: 26),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getGreeting(),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text("$username :)",
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () async {
                        // Await espera a tela fechar
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ProfileScreen()));
                        // Ao voltar, atualiza dados
                        if (context.mounted) _refreshData(ref);
                      },
                      child: Consumer(
                        builder: (context, ref, _) {
                          final userProfile = ref.watch(userProfileProvider);
                          final userImage = userProfile.avatarUrl;
                          return Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: DecorationImage(
                                image: NetworkImage(userImage),
                                fit: BoxFit.cover,
                              ),
                              color: Colors.grey[800],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // --- SEÇÃO 1: NOVIDADES / BAIXADOS ---
              const SizedBox(height: 36),
              Padding(
                  padding: const EdgeInsets.only(left: 33),
                  child: Text(
                      isOffline ? "Baixados dos seus favoritos" : "Novidades dos seus favoritos :)",
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white))),
              const SizedBox(height: 21),

              SizedBox(
                height: 230,
                child: isOffline
                    ? downloadedTracks.when(
                        data: (tracks) {
                          if (tracks.isEmpty) {
                            return const Center(
                                child: Text("Nenhuma música baixada.",
                                    style: TextStyle(color: Colors.white38)));
                          }
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 33),
                            itemCount: tracks.length > 10 ? 10 : tracks.length,
                            separatorBuilder: (ctx, i) => const SizedBox(width: 20),
                            itemBuilder: (ctx, i) {
                              final item = tracks[i];
                              return GestureDetector(
                                onTap: () => _openContent(context, {
                                  'type': 'song',
                                  'title': item['title'] ?? item['trackName'],
                                  'artist': item['artist'] ?? item['artistName'],
                                  'imageUrl': item['artworkUrl'] ?? item['imageUrl'],
                                  'filename': item['filename'],
                                }, ref),
                                child: FeatureAlbumCard(
                                  title: item['title'] ?? item['trackName'] ?? 'Sem Título',
                                  artist: item['artist'] ?? item['artistName'] ?? 'Desconhecido',
                                  imageUrl: item['artworkUrl'] ?? item['imageUrl'] ?? '',
                                  vibrantColor: const Color(0xFF4A00E0),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
                        error: (_, __) => const Center(
                            child: Text("Erro ao carregar downloads",
                                style: TextStyle(color: Colors.white38))),
                      )
                    : newReleases.when(
                        data: (data) {
                          if (data.isEmpty)
                            return const Center(
                                child: Text("Sem novidades.",
                                    style: TextStyle(color: Colors.white38)));
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 33),
                            itemCount: data.length,
                            separatorBuilder: (ctx, i) => const SizedBox(width: 20),
                            itemBuilder: (ctx, i) {
                              final item = data[i];
                              // Parsing da cor hexadecimal (string) para Color
                              Color vibrantColor = const Color(0xFF4A00E0);
                              if (item['vibrantColorHex'] != null) {
                                try {
                                  vibrantColor = Color(int.parse(
                                      item['vibrantColorHex']
                                          .replaceFirst('#', '0xFF')));
                                } catch (_) {}
                              }

                              return GestureDetector(
                                onTap: () => _openContent(context, item, ref),
                                child: FeatureAlbumCard(
                                  title: item['title'] ?? 'Sem Título',
                                  artist: item['artist'] ?? 'Desconhecido',
                                  imageUrl: item['imageUrl'] ?? '',
                                  vibrantColor: vibrantColor,
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                            child:
                                CircularProgressIndicator(color: Color(0xFFD4AF37))),
                        error: (_, __) => const Center(
                            child: Text("Erro",
                                style: TextStyle(color: Colors.white38))),
                      ),
              ),

              // --- SEÇÃO 2: CONTINUE ESCUTANDO ---
              const SizedBox(height: 24),
              const Padding(
                  padding: EdgeInsets.only(left: 33),
                  child: Text("Continue escutando",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white))),
              const SizedBox(height: 18),

              SizedBox(
                height: 210,
                child: continueListening.when(
                  data: (data) {
                    if (data.isEmpty)
                      return const Center(
                          child: Text("Seu histórico aparecerá aqui.",
                              style: TextStyle(color: Colors.white38)));
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 33),
                      itemCount: data.length,
                      separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                      itemBuilder: (ctx, i) {
                        final item = data[i];
                        return GestureDetector(
                          onTap: () => _openContent(context, item, ref),
                          child: StandardAlbumCard(
                            title: item['title'],
                            artist: item['artist'],
                            imageUrl: item['imageUrl'],
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFD4AF37))),
                  error: (_, __) => const SizedBox(),
                ),
              ),

              // --- SEÇÃO 3: RECOMENDAMOS ---
              const SizedBox(height: 24),
              const Padding(
                  padding: EdgeInsets.only(left: 33),
                  child: Text("Recomendamos a você",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white))),
              const SizedBox(height: 18),

              SizedBox(
                height: 210,
                child: recommendations.when(
                  data: (data) {
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 33),
                      itemCount: data.length,
                      separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                      itemBuilder: (ctx, i) {
                        final item = data[i];
                        return GestureDetector(
                          onTap: () => _openContent(context, item, ref),
                          child: StandardAlbumCard(
                            title: item['title'],
                            artist: item['artist'],
                            imageUrl: item['imageUrl'],
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFD4AF37))),
                  error: (_, __) => const SizedBox(),
                ),
              ),

              // --- SEÇÃO: DESCOBERTAS (hidden when offline) ---
              if (!isOffline) ...[
                const SizedBox(height: 24),
                const Padding(
                    padding: EdgeInsets.only(left: 33),
                    child: Text("Descobertas da semana",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white))),
                const SizedBox(height: 6),
                const Padding(
                    padding: EdgeInsets.only(left: 33),
                    child: Text("Artistas novos para você",
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white54))),
                const SizedBox(height: 18),

                SizedBox(
                  height: 210,
                  child: discover.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(
                            child: Text("Ouça mais músicas para personalizarmos",
                                style: TextStyle(color: Colors.white38)));
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 33),
                        itemCount: data.length,
                        separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final item = data[i];
                          return GestureDetector(
                            onTap: () => _openContent(context, item, ref),
                            child: StandardAlbumCard(
                              title: item['title'],
                              artist: item['artist'],
                              imageUrl: item['imageUrl'],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFD4AF37))),
                    error: (_, __) => const SizedBox(),
                  ),
                ),
              ],

              // --- SEÇÃO 4: TRAJETÓRIA (hidden when offline) ---
              if (!isOffline) ...[
                const SizedBox(height: 24),
                const Padding(
                    padding: EdgeInsets.only(left: 33),
                    child: Text("Sua trajetória",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white))),
                const SizedBox(height: 18),

                SizedBox(
                  height: 210,
                  child: trajectory.when(
                    data: (data) {
                      if (data.isEmpty)
                        return const Center(
                            child: Text("Ouça mais para gerar sua trajetória.",
                                style: TextStyle(color: Colors.white38)));
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 33),
                        itemCount: data.length,
                        separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final item = data[i];
                          return GestureDetector(
                            onTap: () => _openPlaylist(
                                context, item['id'], item['title'], ref),
                            child: StandardAlbumCard(
                              title: item['title'],
                              artist: item['artist'],
                              imageUrl: item['imageUrl'],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFD4AF37))),
                    error: (_, __) => const SizedBox(),
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _openContent(
      BuildContext context, Map<String, dynamic> item, WidgetRef ref) async {
    // CASO 1: Álbum vindo do Histórico (sem ID real, apenas Query)
    if (item['type'] == 'album_search') {
      final query = item['search_query'];
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Buscando álbum..."),
          duration: Duration(milliseconds: 500)));

      try {
        final dio = ref.read(dioProvider);
        final response = await dio.get('/search/catalog',
            queryParameters: {'query': query, 'limit': 1, 'type': 'album'});
        final List<dynamic> results = response.data;

        if (results.isNotEmpty) {
          final albumId = results[0]['collectionId'].toString();
          if (context.mounted) {
            // Await para saber quando volta
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlbumScreen(
                        collectionId: albumId,
                        heroTag: "home_recent_${item['title']}")));
            // Refresh ao voltar
            if (context.mounted) _refreshData(ref);
          }
        } else {
          if (context.mounted)
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Álbum não encontrado no catálogo.")));
        }
      } catch (e) {
        print("Erro histórico: $e");
      }
    }

    // CASO 2: Álbum Normal
    else if (item['type'] == 'album') {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AlbumScreen(
                  collectionId: item['id'].toString(),
                  heroTag: "home_${item['id']}")));
      if (context.mounted) _refreshData(ref);
    }

    // CASO 3: Música Solta
    else if (item['type'] == 'song') {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PlayerScreen(
                    item: {
                      'filename': item['filename'],
                      'display_name': item['title'],
                      'artist': item['artist'],
                      'cover_url': item['imageUrl']
                    },
                  )));
      if (context.mounted) _refreshData(ref);
    }
  }

  void _openPlaylist(
      BuildContext context, int id, String title, WidgetRef ref) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                PlaylistDetailScreen(title: title, playlistId: id.toString())));
    if (context.mounted) _refreshData(ref);
  }
}
