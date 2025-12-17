import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:ui';
import '../providers.dart';
import '../services/audio_service.dart';
import '../widgets/bottom_nav_area.dart';
import 'album_screen.dart';

// --- PROVIDER PARA DADOS DO ARTISTA ---
final artistDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, artistName) async {
  // 1. Busca Álbuns
  final albumsRaw = await ref.read(dioProvider).get('/search/catalog',
      queryParameters: {'query': artistName, 'type': 'album', 'limit': 20});

  // 2. Busca Músicas (Singles/Top Songs)
  final songsRaw = await ref.read(dioProvider).get('/search/catalog',
      queryParameters: {'query': artistName, 'type': 'song', 'limit': 20});

  // 3. Simula Artistas Relacionados
  final relatedArtists = [
    {
      "name": "Laufey",
      "image":
          "https://i.scdn.co/image/ab6761610000e5eb56653303e94d8c792982d69f"
    },
    {
      "name": "Beabadoobee",
      "image":
          "https://i.scdn.co/image/ab6761610000e5eb3e0b29952003eb7cb8338302"
    },
    {
      "name": "Mitski",
      "image":
          "https://i.scdn.co/image/ab6761610000e5eb1436df76059b0ae99c086438"
    },
    {
      "name": "Clairo",
      "image":
          "https://i.scdn.co/image/ab6761610000e5eb817c95a319409b68eb943477"
    },
  ];

  List<dynamic> albums = List.from(albumsRaw.data);
  List<dynamic> songs = List.from(songsRaw.data);

  Map<String, dynamic>? latestRelease;

  final allItems = [...albums, ...songs];
  if (allItems.isNotEmpty) {
    allItems.sort((a, b) {
      String dateA = a['releaseDate'] ?? a['year'] ?? "0000";
      String dateB = b['releaseDate'] ?? b['year'] ?? "0000";
      return dateB.compareTo(dateA);
    });
    latestRelease = allItems.first;

    // --- CORREÇÃO: BUSCAR DETALHES DO ÚLTIMO LANÇAMENTO ---
    if (latestRelease!['type'] == 'album') {
      try {
        final id = latestRelease!['collectionId'] ?? latestRelease!['tidalId'];
        if (id != null) {
          final details = await ref
              .read(searchControllerProvider)
              .getAlbumDetails(id.toString());
          if (details['tracks'] != null) {
            latestRelease = Map<String, dynamic>.from(latestRelease!);
            latestRelease!['trackCount'] = (details['tracks'] as List).length;
          }
        }
      } catch (e) {
        print("Erro ao carregar detalhes do último álbum: $e");
      }
    }
  }

  return {
    "latest": latestRelease,
    "albums": albums,
    "singles": songs,
    "related": relatedArtists
  };
});

class ArtistScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  Color _playButtonColor = Colors.white;
  bool _colorCalculated = false;

  // --- LÓGICA DE PLAY (Singles) ---
  Future<void> _handlePlaySingle(Map<String, dynamic> item) async {
    final playerNotifier = ref.read(playerProvider.notifier);

    if (item['filename'] != null) {
      playerNotifier.playContext(queue: [item], initialIndex: 0);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text("Preparando música...", style: TextStyle(color: Colors.black)),
        backgroundColor: Color(0xFFD9D9D9),
        duration: Duration(milliseconds: 1500)));

    try {
      final searchCtrl = ref.read(searchControllerProvider);
      final filename = await searchCtrl.smartDownload(item);

      if (filename != null && mounted) {
        final playableItem = Map<String, dynamic>.from(item);
        playableItem['filename'] = filename;
        playerNotifier.playContext(queue: [playableItem], initialIndex: 0);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    }
  }

  // --- LÓGICA DE PLAY (Albums/Latest) ---
  Future<void> _handlePlayAlbum(Map<String, dynamic> albumItem) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Carregando álbum...",
              style: TextStyle(color: Colors.black)),
          backgroundColor: Color(0xFFD9D9D9)));

      final searchCtrl = ref.read(searchControllerProvider);
      final details = await searchCtrl
          .getAlbumDetails(albumItem['collectionId'] ?? albumItem['tidalId']);

      final tracks = List<Map<String, dynamic>>.from(details['tracks']);
      if (tracks.isEmpty) throw "Álbum vazio";

      final firstTrack = tracks[0];
      firstTrack['artworkUrl'] = albumItem['artworkUrl'];

      final filename = await searchCtrl.smartDownload(firstTrack);

      if (filename != null && mounted) {
        firstTrack['filename'] = filename;
        ref.read(playerProvider.notifier).playContext(
            queue: [firstTrack, ...tracks.sublist(1)], initialIndex: 0);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao tocar álbum: $e"),
            backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final artistName =
        widget.artist['artistName'] ?? widget.artist['name'] ?? 'Artista';
    final artistImage =
        widget.artist['artworkUrl'] ?? widget.artist['imageUrl'] ?? '';
    final asyncDetails = ref.watch(artistDetailsProvider(artistName));

    final double bottomPadding = getBottomNavAreaHeight(ref);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // CONTEÚDO SCROLLÁVEL
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1. TOPO (VÍDEO/IMAGEM) ---
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 317,
                        decoration: BoxDecoration(
                          image: artistImage.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(artistImage),
                                  fit: BoxFit.cover)
                              : null,
                          color: Colors.grey[900],
                        ),
                        child: artistImage.isEmpty
                            ? const Center(
                                child: Icon(Icons.person,
                                    size: 80, color: Colors.white24))
                            : null,
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.8)
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 50,
                        left: 20,
                        child: IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        left: 20,
                        child: Text(
                          artistName,
                          style: GoogleFonts.firaSans(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      // Botão Play Aleatório (Shuffle)
                      Positioned(
                        bottom: 20,
                        right: 20,
                        child: FloatingActionButton(
                          backgroundColor: const Color(0xFFD4AF37),
                          shape: const CircleBorder(),
                          onPressed: () {
                            if (asyncDetails.hasValue) {
                              _playArtistShuffle(
                                  context, ref, asyncDetails.value);
                            }
                          },
                          child: const Icon(Icons.play_arrow,
                              color: Colors.black, size: 30),
                        ),
                      )
                    ],
                  ),

                  // --- 2. DADOS ---
                  asyncDetails.when(
                    data: (data) {
                      final latest = data['latest'];
                      final albums = data['albums'] as List;
                      final singles = data['singles'] as List;
                      final related = data['related'] as List;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (latest != null) ...[
                            const SizedBox(height: 28),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text("Ultimo lançamento",
                                  style: GoogleFonts.firaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                            const SizedBox(height: 10),
                            _buildLatestReleaseCard(latest),
                          ],
                          if (albums.isNotEmpty) ...[
                            const SizedBox(height: 50),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text("Álbuns",
                                  style: GoogleFonts.firaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 210,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 33),
                                itemCount: albums.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (ctx, i) => _buildStandardCard(
                                    albums[i],
                                    isAlbum: true),
                              ),
                            ),
                          ],
                          if (singles.isNotEmpty) ...[
                            const SizedBox(height: 30),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text("Singles",
                                  style: GoogleFonts.firaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 210,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 33),
                                itemCount: singles.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (ctx, i) => _buildStandardCard(
                                    singles[i],
                                    isAlbum: false),
                              ),
                            ),
                          ],
                          if (related.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text("Artistas Parecidos",
                                  style: GoogleFonts.firaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 160,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 33),
                                itemCount: related.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(width: 20),
                                itemBuilder: (ctx, i) =>
                                    _buildRelatedArtistCard(related[i]),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFD4AF37))),
                    ),
                    error: (err, stack) => Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: Center(
                          child: Text("Erro: $err",
                              style: const TextStyle(color: Colors.white))),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // MINIPLAYER + NAVBAR
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomNavArea(),
          ),
        ],
      ),
    );
  }

  // --- WIDGET: ÚLTIMO LANÇAMENTO ---
  Widget _buildLatestReleaseCard(Map<String, dynamic> item) {
    final title = item['collectionName'] ?? item['trackName'] ?? 'Sem Título';
    final rawDate = item['releaseDate'] ?? item['year'] ?? '';
    final coverUrl = item['artworkUrl'] ?? item['imageUrl'] ?? '';

    // Contagem de Músicas
    int count = item['trackCount'] ?? 0;
    if (count == 0 && item['type'] == 'song') count = 1;
    final trackCountStr = count > 0 ? "$count músicas" : "";

    String formattedDate = "DATA DESCONHECIDA";
    try {
      if (rawDate.length >= 4) {
        final date = DateTime.tryParse(rawDate);
        if (date != null) {
          formattedDate = DateFormat("d 'DE' MMM. 'DE' y", "pt_BR")
              .format(date)
              .toUpperCase();
        } else {
          formattedDate = rawDate;
        }
      }
    } catch (_) {}

    if (!_colorCalculated && coverUrl.isNotEmpty) {
      _extractColor(coverUrl);
    }

    // Wrap com GestureDetector para navegação
    return GestureDetector(
      onTap: () {
        // Se for um álbum, navega para a tela de álbum
        if (item['type'] == 'album') {
          final collectionId =
              (item['collectionId'] ?? item['tidalId'] ?? '').toString();
          if (collectionId.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => AlbumScreen(
                        collectionId: collectionId,
                        heroTag: "latest_release_${collectionId}")));
          }
        }
        // Se for música (single), já tem o botão de reproduzir,
        // mas podemos fazer o clique geral tocar também se desejado.
        // Por padrão, deixamos o botão Play tratar a reprodução.
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Centralizado verticalmente
              children: [
                // Cover (140x140)
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: coverUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(coverUrl), fit: BoxFit.cover)
                        : null,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(width: 15),

                // Informações
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment
                        .center, // Garante alinhamento ao centro do bloco
                    children: [
                      Text(
                        formattedDate,
                        style: GoogleFonts.firaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 3),
                      if (trackCountStr.isNotEmpty)
                        Text(
                          trackCountStr,
                          style: GoogleFonts.firaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFFB3B3B3)),
                        ),

                      const SizedBox(height: 15),

                      // Botão Reproduzir (Com seu próprio GestureDetector)
                      GestureDetector(
                        onTap: () {
                          if (item['type'] == 'song') {
                            _handlePlaySingle(item);
                          } else {
                            _handlePlayAlbum(item);
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              width: 123,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFD9D9D9).withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow,
                                      color: _playButtonColor, size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Reproduzir",
                                    style: GoogleFonts.firaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _playButtonColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardCard(Map<String, dynamic> item,
      {required bool isAlbum}) {
    final title =
        item['title'] ?? item['trackName'] ?? item['collectionName'] ?? '';
    final year = item['year'] ?? '';
    final imageUrl = item['artworkUrl'] ?? item['imageUrl'] ?? '';

    // Contagem de músicas para álbuns
    int trackCount = item['trackCount'] ?? 0;
    String subtitle;
    if (isAlbum && trackCount > 0) {
      subtitle = year.isNotEmpty
          ? "$year • $trackCount músicas"
          : "$trackCount músicas";
    } else {
      subtitle = year.isNotEmpty ? year : (isAlbum ? 'Álbum' : 'Single');
    }

    return GestureDetector(
      onTap: () {
        if (isAlbum) {
          final collectionId =
              (item['collectionId'] ?? item['tidalId'] ?? '').toString();
          // Navega passando o ID do álbum
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => AlbumScreen(
                      collectionId: collectionId,
                      heroTag: "artist_album_$collectionId")));
        } else {
          _handlePlaySingle(item);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: imageUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(imageUrl), fit: BoxFit.cover)
                  : null,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 150,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.firaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.firaSans(fontSize: 12, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedArtistCard(Map<String, dynamic> artist) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(65),
            image: artist['image'] != null
                ? DecorationImage(
                    image: NetworkImage(artist['image']), fit: BoxFit.cover)
                : null,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          artist['name'] ?? '',
          textAlign: TextAlign.center,
          style: GoogleFonts.firaSans(
              fontSize: 14, fontWeight: FontWeight.w400, color: Colors.white),
        ),
      ],
    );
  }

  Future<void> _extractColor(String url) async {
    if (_colorCalculated) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          _playButtonColor = palette.vibrantColor?.color ??
              palette.dominantColor?.color ??
              Colors.white;
          _colorCalculated = true;
        });
      }
    } catch (e) {}
  }

  void _playArtistShuffle(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? data) {
    if (data == null) return;
    List<Map<String, dynamic>> singles = List.from(data['singles'] ?? []);

    if (singles.isNotEmpty) {
      _handlePlaySingle(singles[0]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Nenhuma música disponível para tocar.")));
    }
  }
}
