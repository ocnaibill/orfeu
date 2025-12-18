import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_screen.dart';
import 'player_screen.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'genre_playlist_screen.dart';
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

  // Fallback genres caso os favoritos estejam vazios
  static const List<Map<String, dynamic>> _defaultFavoriteGenres = [
    {"name": "Pop", "color": 0xFFE91E63},
    {"name": "Rock", "color": 0xFFF44336},
    {"name": "Hip Hop", "color": 0xFFFFC107},
    {"name": "Electronic", "color": 0xFF00BCD4},
    {"name": "Jazz", "color": 0xFF795548},
    {"name": "R&B", "color": 0xFF9C27B0},
  ];

  @override
  void initState() {
    super.initState();
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
    // Não faz mais a busca aqui - agora só quando der Enter
  }

  void _onSearchSubmitted(String query) {
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
      // Monta fila baseada nos resultados da busca
      final searchQueue = _buildSearchQueue(item);
      final index = searchQueue.indexWhere((t) => 
          (t['tidalId'] == item['tidalId'] && item['tidalId'] != null) ||
          (t['trackName'] == item['trackName'] && t['artistName'] == item['artistName']));
      playerNotifier.playContext(queue: searchQueue, initialIndex: index >= 0 ? index : 0);
      return;
    }

    // Se não tem, tenta baixar/resolver primeiro
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text("Preparando fila...", style: TextStyle(color: Colors.black)),
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

        // Monta fila baseada nos resultados da busca
        final searchQueue = _buildSearchQueue(playableItem);
        final index = searchQueue.indexWhere((t) => t['filename'] == filename);
        
        playerNotifier.playContext(queue: searchQueue, initialIndex: index >= 0 ? index : 0);
        
        // Pré-download da próxima música
        _preloadNextTrack(searchQueue, index >= 0 ? index : 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao reproduzir: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  /// Monta a fila de reprodução baseada nos resultados da busca
  List<Map<String, dynamic>> _buildSearchQueue(Map<String, dynamic> selectedItem) {
    final results = ref.read(searchResultsProvider);
    
    // Filtra apenas músicas (ignora álbuns e artistas)
    final songResults = results
        .where((r) => r['type'] != 'album' && r['type'] != 'artist')
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    
    // Se o item selecionado tiver filename, atualiza na lista
    if (selectedItem['filename'] != null) {
      for (int i = 0; i < songResults.length; i++) {
        if ((songResults[i]['tidalId'] == selectedItem['tidalId'] && selectedItem['tidalId'] != null) ||
            (songResults[i]['trackName'] == selectedItem['trackName'] && 
             songResults[i]['artistName'] == selectedItem['artistName'])) {
          songResults[i] = selectedItem;
          break;
        }
      }
    }
    
    // Se não há resultados, retorna apenas o item selecionado
    if (songResults.isEmpty) {
      return [selectedItem];
    }
    
    return songResults;
  }

  /// Pré-download da próxima música em background
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
            top: 54,
            right: 26,
            child: GestureDetector(
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
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
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
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
    // Busca gêneros favoritos do usuário
    final favoriteGenresAsync = ref.watch(favoriteGenresProvider);
    // Busca todos os gêneros disponíveis
    final allGenresAsync = ref.watch(allGenresProvider);
    // Busca gêneros da biblioteca (músicas baixadas)
    final libraryGenresAsync = ref.watch(libraryGenresProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 164),
          
          // === SUA BIBLIOTECA (GÊNEROS DAS MÚSICAS BAIXADAS) ===
          libraryGenresAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (libraryGenres) {
              if (libraryGenres.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 33, bottom: 20),
                    child: Text("Sua Biblioteca",
                        style: GoogleFonts.firaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: libraryGenres.length,
                      itemBuilder: (context, index) {
                        final genre = libraryGenres[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 32 : 12,
                            right: index == libraryGenres.length - 1 ? 32 : 0,
                          ),
                          child: _buildLibraryGenreChip(genre),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
          
          // === SEUS GÊNEROS FAVORITOS ===
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
            child: favoriteGenresAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
              ),
              error: (e, _) => _buildFavoriteGenresList(_defaultFavoriteGenres),
              data: (favorites) {
                // Se não tem favoritos, usa os defaults
                final genres = favorites.isEmpty ? _defaultFavoriteGenres : favorites;
                return _buildFavoriteGenresList(genres);
              },
            ),
          ),
          
          const SizedBox(height: 50),
          
          // === CONHEÇA MAIS ===
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
            child: allGenresAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  "Erro ao carregar gêneros",
                  style: GoogleFonts.firaSans(color: Colors.grey),
                ),
              ),
              data: (genres) => GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.0,
                ),
                itemCount: genres.length,
                itemBuilder: (context, index) {
                  final genre = genres[index];
                  return Center(child: _buildGenreCard(genre, 150, 150));
                },
              ),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildFavoriteGenresList(List<Map<String, dynamic>> genres) {
    return ListView.builder(
      controller: _favoritesScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        return Padding(
          padding: EdgeInsets.only(
            left: index == 0 ? 32 : 16,
            right: index == genres.length - 1 ? 32 : 0,
          ),
          child: _buildGenreCard(genre, 200, 200),
        );
      },
    );
  }

  /// Converte um valor de cor (int hex ou Color) para Color
  Color _parseColor(dynamic colorValue) {
    if (colorValue is Color) return colorValue;
    if (colorValue is int) return Color(colorValue);
    return Colors.grey;
  }

  Widget _buildGenreCard(
      Map<String, dynamic> genre, double width, double height) {
    final genreName = genre['name'] ?? 'Gênero';
    final color = _parseColor(genre['color']);
    final searchQuery = genre['search_query'] ?? genreName;
    final playlistId = genre['playlist_id'];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GenrePlaylistScreen(
              genreName: genreName,
              genreColor: color,
              searchQuery: searchQuery,
              playlistId: playlistId,
            ),
          ),
        );
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withOpacity(0.9),
                color.withOpacity(0.5)
              ]),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Ícone de fundo decorativo
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                Icons.music_note,
                size: 100,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            // Nome do gênero
            Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(genreName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.firaSans(
                          fontSize: width > 150 ? 20 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            const Shadow(blurRadius: 8, color: Colors.black54)
                          ])),
                )),
            // Ícone de play
            Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                ))
          ],
        ),
      ),
    );
  }

  /// Widget para mostrar gêneros da biblioteca (chips compactos)
  Widget _buildLibraryGenreChip(Map<String, dynamic> genre) {
    final genreName = genre['name'] ?? 'Gênero';
    final color = _parseColor(genre['color']);
    final count = genre['count'] ?? 0;
    final searchQuery = genre['search_query'] ?? genreName;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GenrePlaylistScreen(
              genreName: genreName,
              genreColor: color,
              searchQuery: searchQuery,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getGenreIcon(genreName),
              size: 32,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              genreName,
              style: GoogleFonts.firaSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              "$count músicas",
              style: GoogleFonts.firaSans(
                fontSize: 11,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Retorna um ícone apropriado para o gênero
  IconData _getGenreIcon(String genreName) {
    final name = genreName.toLowerCase();
    if (name.contains('pop')) return Icons.star;
    if (name.contains('rock')) return Icons.bolt;
    if (name.contains('jazz')) return Icons.music_note;
    if (name.contains('hip') || name.contains('rap')) return Icons.mic;
    if (name.contains('electronic') || name.contains('edm')) return Icons.waves;
    if (name.contains('classical')) return Icons.piano;
    if (name.contains('r&b') || name.contains('soul')) return Icons.favorite;
    if (name.contains('country')) return Icons.landscape;
    if (name.contains('latin') || name.contains('reggae')) return Icons.sunny;
    if (name.contains('metal')) return Icons.whatshot;
    if (name.contains('folk') || name.contains('indie')) return Icons.park;
    if (name.contains('blues')) return Icons.nightlight;
    if (name.contains('soundtrack') || name.contains('video game') || name.contains('anime')) return Icons.movie;
    if (name.contains('j-pop') || name.contains('k-pop')) return Icons.auto_awesome;
    if (name.contains('bossa') || name.contains('mpb')) return Icons.wb_sunny;
    if (name.contains('alternative')) return Icons.alt_route;
    return Icons.album;
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

    return GestureDetector(
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
      child: Container(
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

          // 3. Indicador visual (Play para música, Seta para álbum)
          Positioned(
            right: isAlbum ? 30 : 20,
            top: isAlbum ? 0 : 11.5,
            bottom: isAlbum ? 0 : null,
            child: Icon(
              isAlbum
                  ? Icons.arrow_forward_ios_rounded
                  : Icons.play_circle_fill,
              color: Colors.white,
              size: isAlbum ? 20 : 32,
            ),
          ),
        ],
      ),
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
