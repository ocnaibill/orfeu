import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_screen.dart';
import 'player_screen.dart';
import 'artist_screen.dart';
import 'album_screen.dart'; // <--- Import Adicionado
import '../providers.dart';
import '../services/audio_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _favoritesScrollController = ScrollController();

  bool _isSearching = false;
  String _searchType = 'song'; // 'song', 'album', 'artist'

  // Mock de gêneros favoritos
  final List<Map<String, dynamic>> _favoriteGenres = [
    {"name": "Jazz Pop", "color": Colors.orangeAccent},
    {"name": "Indie", "color": Colors.blueAccent},
    {"name": "Bossa Nova", "color": Colors.green},
    {"name": "Lo-Fi", "color": Colors.purple},
    {"name": "Rock", "color": Colors.redAccent},
  ];

  // Mock de gêneros "Conheça mais"
  final List<Map<String, dynamic>> _browseGenres = [
    {"name": "Pop", "color": Colors.pink},
    {"name": "Hip Hop", "color": Colors.amber},
    {"name": "Classical", "color": Colors.brown},
    {"name": "Electronic", "color": Colors.cyan},
    {"name": "Metal", "color": Colors.grey},
    {"name": "R&B", "color": Colors.indigo},
    {"name": "Reggae", "color": Colors.lightGreen},
    {"name": "Blues", "color": Colors.deepPurple},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_favoritesScrollController.hasClients) {
        _favoritesScrollController.jumpTo(_favoriteGenres.length * 200.0 * 100);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _favoritesScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
    });
    if (query.isNotEmpty) {
      ref.read(searchTypeProvider.notifier).state = _searchType;
      ref.read(searchControllerProvider).searchCatalog(query);
    }
  }

  void _onFilterChanged(String newType) {
    if (_searchType == newType) return;
    setState(() {
      _searchType = newType;
    });

    if (_textController.text.isNotEmpty) {
      ref.read(searchTypeProvider.notifier).state = newType;
      ref.read(searchControllerProvider).searchCatalog(_textController.text);
    }
  }

  // Lógica de Play Inteligente (Download -> Play)
  Future<void> _handlePlay(Map<String, dynamic> item) async {
    final playerNotifier = ref.read(playerProvider.notifier);

    // Se já tem filename, toca direto
    if (item['filename'] != null) {
      playerNotifier.playContext(queue: [item], initialIndex: 0);
      return;
    }

    // Se não tem, tenta baixar/resolver primeiro
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text("Preparando música...", style: TextStyle(color: Colors.black)),
      backgroundColor: Color(0xFFD9D9D9),
      duration: Duration(seconds: 2),
    ));

    try {
      final searchCtrl = ref.read(searchControllerProvider);
      // smartDownload deve retornar o filename ou lançar erro
      final filename = await searchCtrl.smartDownload(item);

      if (filename != null && mounted) {
        // Cria uma cópia do item com o filename atualizado
        final playableItem = Map<String, dynamic>.from(item);
        playableItem['filename'] = filename;

        playerNotifier.playContext(queue: [playableItem], initialIndex: 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao reproduzir: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Altura da "Barra Preta" (Blocker) que impede itens de aparecerem atrás do header
    final double headerBlockerHeight = _isSearching ? 220.0 : 150.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. CONTEÚDO PRINCIPAL (Scrollável)
          Positioned.fill(
            child:
                _isSearching ? _buildSearchResults() : _buildDiscoverContent(),
          ),

          // 2. BLOCKER (Fundo preto do Header)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerBlockerHeight,
            child: Container(
              color: Colors.black,
            ),
          ),

          // 3. ELEMENTOS FIXOS / HEADER (UI)

          // Texto "Buscar"
          Positioned(
            top: 54,
            left: 34,
            child: Text(
              "Buscar",
              style: GoogleFonts.firaSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          // Ícone de Usuário
          Positioned(
            top: 41,
            right: 22,
            child: GestureDetector(
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
          ),

          // Container de Busca
          Positioned(
            top: 110,
            left: 33,
            right: 33,
            height: 34,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9).withOpacity(0.60),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    right: 15,
                    child:
                        const Icon(Icons.search, color: Colors.white, size: 20),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 20, right: 40, bottom: 2),
                    child: TextField(
                      controller: _textController,
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.firaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: "O que estamos procurando hoje?",
                        hintStyle: GoogleFonts.firaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Botões de Filtro
          if (_isSearching)
            Positioned(
              top: 164,
              left: 33,
              right: 33,
              child: _buildFilterButtons(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSingleFilterBtn("Músicas", "song"),
        _buildSingleFilterBtn("Álbuns", "album"),
        _buildSingleFilterBtn("Artistas", "artist"),
      ],
    );
  }

  Widget _buildSingleFilterBtn(String label, String type) {
    final isSelected = _searchType == type;
    final width = isSelected ? 100.0 : 75.0;
    final height = isSelected ? 40.0 : 34.0;
    final color =
        isSelected ? Colors.white : const Color(0xFFD9D9D9).withOpacity(0.60);

    return GestureDetector(
      onTap: () => _onFilterChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.firaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 16, color: Colors.black)
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 164),
          Padding(
            padding: const EdgeInsets.only(left: 33, bottom: 20),
            child: Text("Seus gêneros favoritos",
                style: GoogleFonts.firaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          SizedBox(
            height: 200,
            child: ListView.builder(
              controller: _favoritesScrollController,
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final genre = _favoriteGenres[index % _favoriteGenres.length];
                return Padding(
                  padding:
                      EdgeInsets.only(left: 32, right: index == 10000 ? 32 : 0),
                  child: _buildGenreCard(genre, 200, 200),
                );
              },
            ),
          ),
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.only(left: 33, bottom: 20),
            child: Text("Conheça mais.",
                style: GoogleFonts.firaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 33),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 1.0,
              ),
              itemCount: _browseGenres.length * 5,
              itemBuilder: (context, index) {
                final genre = _browseGenres[index % _browseGenres.length];
                return Center(child: _buildGenreCard(genre, 150, 150));
              },
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildGenreCard(
      Map<String, dynamic> genre, double width, double height) {
    return GestureDetector(
      onTap: () {
        print("Criando playlist: ${genre['name']}");
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: genre['color'],
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                genre['color'].withOpacity(0.8),
                genre['color'].withOpacity(0.4)
              ]),
        ),
        child: Stack(
          children: [
            Center(
                child: Text(genre['name'],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          const Shadow(blurRadius: 5, color: Colors.black45)
                        ]))),
            const Positioned(
                bottom: 10,
                right: 10,
                child: Icon(Icons.play_circle_fill, color: Colors.white54))
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = ref.watch(searchResultsProvider);
    final isLoading = ref.watch(isLoadingProvider);

    return Container(
      color: Colors.black,
      child: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : ListView.builder(
              // PADDING SUPERIOR: Ajustado para 244px para compensar o Header + Filtros
              padding: const EdgeInsets.only(
                  top: 244, bottom: 100, left: 33, right: 33),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final item = results[index];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: _searchType == 'artist'
                      ? _buildArtistCard(item)
                      : _buildTrackCard(item),
                );
              },
            ),
    );
  }

  // Card para Músicas e Álbuns
  Widget _buildTrackCard(Map<String, dynamic> item) {
    String year = "";
    if (item['year'] != null && item['year'].toString().isNotEmpty) {
      year = item['year'].toString();
    } else {
      final dateStr = item['releaseDate'] ?? item['release_date'];
      if (dateStr != null && dateStr.toString().isNotEmpty) {
        try {
          year = DateTime.parse(dateStr).year.toString();
        } catch (_) {
          if (dateStr.toString().length >= 4) {
            year = dateStr.toString().substring(0, 4);
          }
        }
      }
    }

    final coverUrl = item['artworkUrl'] ??
        item['imageUrl'] ??
        item['artworkUrl100'] ??
        item['artworkUrl60'] ??
        item['cover'] ??
        '';

    final title = item['trackName'] ?? item['collectionName'] ?? 'Sem Título';
    final artist = item['artistName'] ?? 'Desconhecido';
    final isAlbum = item['type'] == 'album';

    return Container(
      height: 55,
      width: double.infinity,
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1. Foto
          Positioned(
            left: 9,
            top: 2.5,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.grey[900],
                image: coverUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(coverUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: coverUrl.isEmpty
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
          ),

          // 2. Textos
          Positioned(
            left: 69,
            top: 6,
            right: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  year.isNotEmpty ? "$artist - $year" : artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),

          // 3. Ação (Play para música, Seta para álbum)
          Positioned(
            right: isAlbum ? 30 : 20,
            top: isAlbum ? 0 : 11.5,
            bottom: isAlbum ? 0 : null,
            child: GestureDetector(
              onTap: () {
                if (isAlbum) {
                  final collectionId =
                      (item['collectionId'] ?? item['tidalId'] ?? '')
                          .toString();
                  if (collectionId.isNotEmpty) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => AlbumScreen(
                                collectionId: collectionId,
                                heroTag: "search_album_$collectionId")));
                  }
                } else {
                  _handlePlay(item);
                }
              },
              child: Icon(
                isAlbum
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.play_circle_fill,
                color: Colors.white,
                size: isAlbum ? 20 : 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card para Artistas
  Widget _buildArtistCard(Map<String, dynamic> item) {
    final artistName = item['artistName'] ?? 'Desconhecido';
    final imageUrl = item['artworkUrl'] ??
        item['imageUrl'] ??
        item['artworkUrl100'] ??
        item['artworkUrl60'] ??
        '';

    return GestureDetector(
      // --- NAVEGAÇÃO PARA A TELA DE ARTISTA ---
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistScreen(artist: item),
          ),
        );
      },
      child: Container(
        height: 73,
        width: double.infinity,
        color: Colors.transparent, // Permite clique em toda a área
        child: Stack(
          children: [
            // 1. Foto
            Positioned(
              left: 7,
              top: 6.5,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.grey[900],
                  image: imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: imageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
            ),

            // 2. Nome
            Positioned(
              left: 83,
              right: 60,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // 3. Seta
            Positioned(
              right: 30,
              top: 0,
              bottom: 0,
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
