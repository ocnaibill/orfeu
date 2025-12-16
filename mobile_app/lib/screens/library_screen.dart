import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import '../providers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // Filtro: 'Playlists', 'Álbuns', 'Artistas' ou null (todos)
  String? _selectedFilter;
  
  // Ordenação: 'Recentes', 'Alfabética', 'Data'
  String _sortMode = 'Tocadas Recentemente';

  @override
  void initState() {
    super.initState();
    // Garante que as playlists do usuário estejam carregadas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryControllerProvider).fetchPlaylists();
    });
  }

  // Lógica de Ordenação
  List<Map<String, dynamic>> _sortItems(List<Map<String, dynamic>> items) {
    final sorted = List<Map<String, dynamic>>.from(items);
    
    switch (_sortMode) {
      case 'Ordem Alfabética':
        sorted.sort((a, b) => (a['title'] ?? a['name'] ?? '').compareTo(b['title'] ?? b['name'] ?? ''));
        break;
      case 'Data de Adição':
        // Simulação, pois backend pode não ter data para tudo
        // sorted.sort((a, b) => ...); 
        break;
      case 'Tocadas Recentemente':
      default:
        // Mantém ordem original ou lógica de recent
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userImage = "https://i.scdn.co/image/ab6761610000e5eb56653303e94d8c792982d69f"; // Mock

    // 1. Coleta dados reais de Playlists
    final userPlaylists = ref.watch(userPlaylistsProvider);
    
    // 2. Mocks para Álbuns e Artistas (enquanto backend não tem endpoint /me/albums)
    final savedAlbums = [
      {
        "type": "album",
        "id": "297839093", // Bewitched
        "title": "Bewitched",
        "artist": "Laufey",
        "year": "2023",
        "imageUrl": "https://resources.tidal.com/images/cbdcd847/9c57/4999/95c0/bd24f9178694/640x640.jpg",
        "isPinned": true,
        "vibrantColor": Colors.orangeAccent
      },
      {
        "type": "album",
        "id": "320084588",
        "title": "A Night To Remember",
        "artist": "Beabadoobee",
        "year": "2023",
        "imageUrl": "https://resources.tidal.com/images/b3a85202/2ec3/452e/bad7/3a887c2fe132/640x640.jpg",
        "isPinned": false,
      }
    ];

    final savedArtists = [
      {
        "type": "artist",
        "name": "Laufey",
        "imageUrl": "https://resources.tidal.com/images/ea7b3f6d/0e60/4071/8c61/920219a090e8/750x750.jpg",
        "isPinned": true,
        "vibrantColor": Colors.pinkAccent
      },
      {
        "type": "artist",
        "name": "Mitski",
        "imageUrl": "https://i.scdn.co/image/ab6761610000e5eb1436df76059b0ae99c086438",
        "isPinned": false,
      }
    ];

    // 3. Unifica a lista (Normalizando campos para o Widget)
    List<Map<String, dynamic>> allItems = [];

    // Adiciona Playlists
    for (var p in userPlaylists) {
      allItems.add({
        "type": "playlist",
        "id": p['id'].toString(),
        "title": p['name'],
        "subtitle": "Playlist • ${p['tracks_count'] ?? 0} músicas",
        "imageUrl": p['cover'] ?? "", // Pode ser null
        "isPinned": false, // Playlists não tem pin no backend ainda
      });
    }

    // Adiciona Álbuns
    for (var a in savedAlbums) {
      allItems.add({
        "type": "album",
        "id": a['id'],
        "title": a['title'],
        "subtitle": "Álbum • ${a['artist']} • ${a['year']}",
        "imageUrl": a['imageUrl'],
        "isPinned": a['isPinned'],
        "vibrantColor": a['vibrantColor']
      });
    }

    // Adiciona Artistas
    for (var ar in savedArtists) {
      allItems.add({
        "type": "artist",
        "name": ar['name'], // Artistas usam 'name' e layout diferente
        "imageUrl": ar['imageUrl'],
        "isPinned": ar['isPinned'],
        "vibrantColor": ar['vibrantColor']
      });
    }

    // 4. Aplica Filtros
    if (_selectedFilter == "Playlists") {
      allItems = allItems.where((i) => i['type'] == 'playlist').toList();
    } else if (_selectedFilter == "Álbuns") {
      allItems = allItems.where((i) => i['type'] == 'album').toList();
    } else if (_selectedFilter == "Artistas") {
      allItems = allItems.where((i) => i['type'] == 'artist').toList();
    }

    // 5. Aplica Ordenação
    allItems = _sortItems(allItems);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            // "54px abaixo do topo"
            Padding(
              padding: const EdgeInsets.only(top: 54, left: 33, right: 26),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Sua Biblioteca",
                    style: GoogleFonts.firaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                    child: Container(
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
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- FILTROS ---
            // "16px abaixo do texto Sua Biblioteca"
            Padding(
              padding: const EdgeInsets.only(left: 33),
              child: Row(
                children: [
                  _buildFilterButton("Playlists"),
                  const SizedBox(width: 24),
                  _buildFilterButton("Álbuns"),
                  const SizedBox(width: 24),
                  _buildFilterButton("Artistas"),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // --- ORDENAÇÃO ---
            // "25 px abaixo dos botões"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 33),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _sortMode, // "Tocadas Recentemente" (Dinâmico)
                    style: GoogleFonts.firaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600, // SemiBold
                      color: Colors.white,
                    ),
                  ),
                  // Botão "Quatro Quadrados" (Grid View / Sort)
                  // "40px a esquerda do canto esquerdo" (Interpretado como alinhado à direita com padding, 
                  // já que o texto está na esquerda. O padding do pai é 33, ajustando visualmente).
                  IconButton(
                    icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                    onPressed: () => _showSortModal(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --- LISTA DE CONTEÚDO ---
            
            // 1. Músicas Curtidas (Sempre primeiro, a menos que filtrado fora)
            // "a playlist músicas curtidas sempre estará fixada como primeiro"
            if (_selectedFilter == null || _selectedFilter == "Playlists")
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: _buildListItem(
                  context,
                  item: {
                    "type": "playlist",
                    "id": "favorites", // ID especial
                    "title": "Músicas Curtidas",
                    "subtitle": "Playlist • Fixada",
                    "imageUrl": "https://misc.scdn.co/liked-songs/liked-songs-640.png",
                    "isPinned": true,
                    "vibrantColor": const Color(0xFF4A00E0) // Roxo destaque
                  },
                ),
              ),

            // 2. Itens Dinâmicos
            ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: _buildListItem(context, item: allItems[index]),
                );
              },
            ),

            const SizedBox(height: 100), // Espaço final para navbar
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildFilterButton(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          // Toggle filter
          if (_selectedFilter == label) {
            _selectedFilter = null;
          } else {
            _selectedFilter = label;
          }
        });
      },
      child: Container(
        width: 75,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFFD9D9D9).withOpacity(0.60),
          borderRadius: BorderRadius.circular(17), // Arredondado (metade da altura)
        ),
        child: Text(
          label,
          style: GoogleFonts.firaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600, // SemiBold
            color: Colors.black, // Sempre preto conforme pedido
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(BuildContext context, {required Map<String, dynamic> item}) {
    final type = item['type'];
    final isArtist = type == 'artist';
    final isPinned = item['isPinned'] == true;
    final highlightColor = item['vibrantColor'] as Color? ?? const Color(0xFFD4AF37);

    // Dimensões: 327x75
    // Padding lateral para centralizar: (Screen - 327) / 2 ~= 33px. 
    // Como o pai já tem padding? Não, ListView builder não tem padding lateral no código acima.
    // Vamos usar Center + Container fixo.

    return Center(
      child: GestureDetector(
        onTap: () {
          if (type == 'playlist') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: item['id'], title: item['title'])));
          } else if (type == 'album') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(collectionId: item['id'])));
          } else if (type == 'artist') {
            // Reconstrói objeto artist para a tela
            Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artist: {"artistName": item['name'], "artworkUrl": item['imageUrl']})));
          }
        },
        child: Container(
          width: 327,
          height: 75,
          color: Colors.transparent, // Hitbox
          child: Row(
            children: [
              // --- COVER / FOTO ---
              Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isArtist ? 65 : 4), // "65 border radius" se artista
                  color: Colors.grey[900],
                  image: (item['imageUrl'] != null && item['imageUrl'].toString().isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(item['imageUrl']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (item['imageUrl'] == null || item['imageUrl'].toString().isEmpty) 
                    ? Icon(isArtist ? Icons.person : Icons.music_note, color: Colors.white24) 
                    : null,
              ),

              const SizedBox(width: 10), // "10 px a direita"

              // --- TEXTOS ---
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // "centralizado ao cover"
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // NOME
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isArtist ? item['name'] : item['title'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaSans(
                              fontSize: isArtist ? 24 : 16, // Artista 24, Outros (implícito padrão ou herdado?) Vamos usar 16 Bold para outros para hierarquia
                              fontWeight: isArtist ? FontWeight.normal : FontWeight.bold, // Artista Regular, Outros Bold
                              color: Colors.white,
                            ),
                          ),
                        ),
                        // PIN ICON (ARTISTA)
                        // "caso o artista esteja fixado, o alfinete deve aparecer 5px a direita do fim de seu nome"
                        if (isArtist && isPinned) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.push_pin, color: highlightColor, size: 16)
                        ]
                      ],
                    ),
                    
                    // SUBTITULO / PIN (ALBUM/PLAYLIST)
                    if (!isArtist) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // PIN ICON (ALBUM/PLAYLIST)
                          if (isPinned) ...[
                            Icon(Icons.push_pin, color: highlightColor, size: 14), // "cor em destaque"
                            const SizedBox(width: 5),
                          ],
                          
                          // TEXTO DESCRIÇÃO
                          Expanded(
                            child: Text(
                              item['subtitle'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.firaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w200, // ExtraLight
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- MODAL DE ORDENAÇÃO ---
  void _showSortModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Classificar por", style: GoogleFonts.firaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              _buildSortOption("Tocadas Recentemente"),
              _buildSortOption("Ordem Alfabética"),
              _buildSortOption("Data de Adição"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOption(String label) {
    final isSelected = _sortMode == label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: GoogleFonts.firaSans(
          color: isSelected ? const Color(0xFFD4AF37) : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFD4AF37)) : null,
      onTap: () {
        setState(() {
          _sortMode = label;
        });
        Navigator.pop(context);
      },
    );
  }
}