import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'dart:typed_data';
import '../providers.dart';
import '../services/audio_service.dart';
import '../services/download_manager.dart';
import '../widgets/bottom_nav_area.dart';

// Provider para carregar os detalhes da playlist
final playlistDetailsProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, id) async {
  // --- CASO 1: MÚSICAS CURTIDAS ---
  if (id == 'favorites' || id.isEmpty) {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/users/me/favorites');
      final List<dynamic> data = response.data;

      final tracks = data.map((t) {
        int durationMs = 0;
        final rawDur = t['duration'] ??
            t['duration_ms'] ??
            t['durationMs'] ??
            t['duration_seconds'] ??
            t['length'] ??
            t['length_seconds'];

        if (rawDur != null) {
          final numDur = num.tryParse(rawDur.toString());
          if (numDur != null) {
            if (numDur < 30000) {
              durationMs = (numDur * 1000).toInt();
            } else {
              durationMs = numDur.toInt();
            }
          }
        }

        final coverUrl = t['coverProxyUrl'] ??
            t['cover'] ??
            t['artworkUrl'] ??
            t['imageUrl'] ??
            t['image'] ??
            t['thumbnail'] ??
            '';

        return {
          'trackName': t['title'] ??
              t['display_name'] ??
              t['name'] ??
              t['trackName'] ??
              t['track_name'] ??
              'Sem Título',
          'artistName': t['artist'] ??
              t['artistName'] ??
              t['artist_name'] ??
              'Desconhecido',
          'collectionName': t['album'] ?? t['collectionName'] ?? '',
          'durationMs': durationMs,
          'artworkUrl': coverUrl,
          'imageUrl': coverUrl,
          'filename': t['filename'],
          'id': t['id'],
        };
      }).toList();

      return {
        'name': 'Músicas Curtidas',
        'owner': 'Você',
        'artworkUrl': 'https://misc.scdn.co/liked-songs/liked-songs-640.png',
        'tracks': tracks,
        'year': DateTime.now().year.toString(),
        'isFavorites': true,
      };
    } catch (e) {
      throw "Erro ao carregar favoritos: $e";
    }
  }

  // --- CASO 2: PLAYLIST COMUM ---
  try {
    if (int.tryParse(id) != null) {
      final rawData = await ref
          .read(libraryControllerProvider)
          .getPlaylistDetails(int.parse(id));

      // Processa as tracks para normalizar os campos
      final rawTracks =
          List<Map<String, dynamic>>.from(rawData['tracks'] ?? []);
      final tracks = rawTracks.map((t) {
        int durationMs = 0;
        final rawDur = t['duration'] ??
            t['duration_ms'] ??
            t['durationMs'] ??
            t['duration_seconds'] ??
            t['length'] ??
            t['length_seconds'];

        if (rawDur != null) {
          final numDur = num.tryParse(rawDur.toString());
          if (numDur != null) {
            // Se menor que 30000, provavelmente está em segundos
            if (numDur < 30000) {
              durationMs = (numDur * 1000).toInt();
            } else {
              durationMs = numDur.toInt();
            }
          }
        }

        final coverUrl = t['coverProxyUrl'] ??
            t['cover'] ??
            t['artworkUrl'] ??
            t['imageUrl'] ??
            t['image'] ??
            t['thumbnail'] ??
            '';

        return {
          'trackName': t['title'] ??
              t['display_name'] ??
              t['name'] ??
              t['trackName'] ??
              t['track_name'] ??
              'Sem Título',
          'artistName': t['artist'] ??
              t['artistName'] ??
              t['artist_name'] ??
              'Desconhecido',
          'collectionName': t['album'] ?? t['collectionName'] ?? '',
          'durationMs': durationMs,
          'artworkUrl': coverUrl,
          'imageUrl': coverUrl,
          'filename': t['filename'],
          'id': t['id'],
          'playlist_item_id': t['playlist_item_id'],
        };
      }).toList();

      return {
        'id': rawData['id'],
        'name': rawData['name'],
        'is_public': rawData['is_public'],
        'tracks': tracks,
        'isFavorites': false,
      };
    }
    throw "Tipo de playlist não suportado: $id";
  } catch (e) {
    rethrow;
  }
});

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String heroTag;
  final Map<String, dynamic>? initialData;
  final String? title;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.heroTag = 'playlist_cover',
    this.initialData,
    this.title,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen>
    with SingleTickerProviderStateMixin {
  Color _vibrantColor = Colors.white;
  bool _colorCalculated = false;
  bool _isDownloaded = false;

  Future<void> _extractColor(String url) async {
    if (_colorCalculated) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          _vibrantColor = palette.vibrantColor?.color ??
              palette.lightVibrantColor?.color ??
              palette.dominantColor?.color ??
              Colors.white;
          _colorCalculated = true;
        });
      }
    } catch (e) {
      // Falha silenciosa
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(playlistDetailsProvider(widget.playlistId));
    final playerState = ref.watch(playerProvider);
    final currentTrack = playerState.currentTrack;
    final isPlaying = playerState.isPlaying;

    final isLoading = playlistAsync.isLoading;
    final hasError = playlistAsync.hasError;

    Map<String, dynamic> playlistData = {};

    if (playlistAsync.hasValue) {
      playlistData = playlistAsync.value!;
    } else {
      playlistData = widget.initialData ?? {};
      if (widget.title != null) playlistData['name'] = widget.title;
    }

    if (playlistData.isEmpty && (isLoading || hasError)) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: isLoading
              ? const CircularProgressIndicator(color: Color(0xFFD4AF37))
              : Text("Erro: ${playlistAsync.error}",
                  style: const TextStyle(color: Colors.white)),
        ),
      );
    }

    final artworkUrl =
        playlistData['cover_url'] ?? playlistData['artworkUrl'] ?? playlistData['imageUrl'] ?? '';
    final tracks =
        List<Map<String, dynamic>>.from(playlistData['tracks'] ?? []);
    final isFavoritesPlaylist = playlistData['isFavorites'] == true;

    final title = playlistData['name'] ?? playlistData['title'] ?? 'Playlist';
    final creator = playlistData['owner'] ?? playlistData['creator'] ?? 'Você';
    final year = playlistData['year'] ??
        playlistData['createdAt']?.toString().substring(0, 4) ??
        DateTime.now().year.toString();

    if (artworkUrl.isNotEmpty && !_colorCalculated) {
      _extractColor(artworkUrl);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const BottomNavArea(),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 45),

                // --- 1. HEADER ---
                SizedBox(
                  height: 50,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 45,
                        top: 0,
                        child: _buildGlassButton(
                          icon: Icons.arrow_back,
                          color: Colors.white,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                      Positioned(
                        right: 35,
                        top: 0,
                        child: _buildGlassButton(
                          icon: Icons.more_horiz,
                          color: _vibrantColor,
                          isVibrantBackground: true,
                          onTap: () => _showPlaylistOptionsModal(playlistData, tracks),
                        ),
                      ),
                      Positioned(
                        right: 100,
                        top: 0,
                        child: _buildGlassButton(
                          icon: _isDownloaded
                              ? Icons.download_done
                              : Icons.download_rounded,
                          color: Colors.white,
                          isVibrantBackground: true,
                          onTap: () =>
                              setState(() => _isDownloaded = !_isDownloaded),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- 2. CAPA E INFO ---
                Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: _vibrantColor.withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: -10,
                              offset: const Offset(0, 20))
                        ],
                        image: artworkUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(artworkUrl),
                                fit: BoxFit.cover)
                            : null,
                        color: Colors.grey[900],
                      ),
                      child: artworkUrl.isEmpty
                          ? const Icon(Icons.music_note,
                              size: 80, color: Colors.white24)
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: 234,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.firaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  "$creator - $year",
                  style: GoogleFonts.firaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: _vibrantColor),
                ),

                Text(
                  _generateStatsString(tracks),
                  style: GoogleFonts.firaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: _vibrantColor),
                ),

                const SizedBox(height: 10),

                // --- 3. AÇÕES ---
                if (tracks.isNotEmpty)
                  SizedBox(
                    height: 60,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 54,
                          child: _buildAcrylicActionButton(
                            label: "Reproduzir",
                            icon: Icons.play_arrow,
                            onTap: () => _playPlaylist(context, ref, tracks, 0,
                                shuffle: false,
                                playlistCover: artworkUrl,
                                isFavorites: isFavoritesPlaylist),
                          ),
                        ),
                        Positioned(
                          right: 54,
                          child: _buildAcrylicActionButton(
                            label: "Aleatório",
                            icon: Icons.shuffle,
                            onTap: () => _playPlaylist(context, ref, tracks, 0,
                                shuffle: true,
                                playlistCover: artworkUrl,
                                isFavorites: isFavoritesPlaylist),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // --- 4. LISTA DE MÚSICAS ---
                if (isLoading && tracks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 33),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];

                        final currentTitle = currentTrack?['trackName'] ??
                            currentTrack?['title'];
                        final thisTitle = track['trackName'] ?? track['title'];

                        final isPlayingThis = currentTitle != null &&
                            thisTitle != null &&
                            currentTitle == thisTitle;

                        final itemColor =
                            isPlayingThis ? _vibrantColor : Colors.white;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: InkWell(
                            onTap: () => _playPlaylist(
                                context, ref, tracks, index,
                                shuffle: false,
                                playlistCover: artworkUrl,
                                isFavorites: isFavoritesPlaylist),
                            child: SizedBox(
                              height: 50,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 25,
                                    child: isPlayingThis
                                        ? EqualizerAnimation(
                                            color: _vibrantColor,
                                            isAnimating: isPlaying)
                                        : Text(
                                            "${index + 1}",
                                            style: GoogleFonts.firaSans(
                                                fontSize: 16,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.white54),
                                          ),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          track['trackName'] ??
                                              track['title'] ??
                                              'Sem Título',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.firaSans(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w400,
                                            color: itemColor,
                                          ),
                                        ),
                                        Text(
                                          track['artistName'] ??
                                              track['artist'] ??
                                              'Desconhecido',
                                          style: GoogleFonts.firaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: itemColor.withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 0),
                                    child: Text(
                                      _formatDuration(track['durationMs'] ?? 0),
                                      style: GoogleFonts.firaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _generateStatsString(List<Map<String, dynamic>> tracks) {
    int totalMs = 0;
    for (var t in tracks) {
      totalMs += (t['durationMs'] as int? ?? 0);
    }

    final totalMinutes = (totalMs / 60000).floor();
    final totalHours = (totalMinutes / 60).floor();

    String durationString;
    if (totalHours < 1) {
      durationString = "$totalMinutes minutos";
    } else {
      durationString = "$totalHours horas";
    }

    return "${tracks.length} músicas, $durationString";
  }

  Widget _buildGlassButton(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap,
      bool isVibrantBackground = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: isVibrantBackground
              ? _vibrantColor.withOpacity(0.2)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildAcrylicActionButton(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 130,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9).withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _vibrantColor, size: 20),
                const SizedBox(width: 5),
                Text(label,
                    style: GoogleFonts.firaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _vibrantColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playPlaylist(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> tracks, int startIndex,
      {required bool shuffle,
      required String playlistCover,
      required bool isFavorites}) async {
    if (tracks.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Preparando fila...",
              style: TextStyle(color: Colors.black)),
          backgroundColor: Color(0xFFD9D9D9),
          duration: Duration(milliseconds: 1500)),
    );

    try {
      // Prepara todas as tracks da playlist com metadados
      final preparedTracks = tracks.map((t) {
        final track = Map<String, dynamic>.from(t);
        if (!isFavorites) {
          if (track['artworkUrl'] == null || track['artworkUrl'].toString().isEmpty) {
            track['artworkUrl'] = playlistCover;
          }
        }
        if (track['artworkUrl'] != null && track['artworkUrl'].toString().isNotEmpty) {
          track['imageUrl'] = track['artworkUrl'];
        }
        return track;
      }).toList();

      // Faz download da primeira música
      final targetTrack = preparedTracks[startIndex];
      final filename = await ref.read(searchControllerProvider).smartDownload(targetTrack);

      if (filename == null) {
        throw Exception('Não foi possível preparar a música');
      }
      preparedTracks[startIndex]['filename'] = filename;

      // Monta a fila na ordem correta (ou embaralhada)
      List<Map<String, dynamic>> playQueue;
      int playIndex = startIndex;
      
      if (shuffle) {
        // Embaralha mas mantém a música selecionada primeiro
        final first = preparedTracks.removeAt(startIndex);
        preparedTracks.shuffle();
        preparedTracks.insert(0, first);
        playQueue = preparedTracks;
        playIndex = 0;
      } else {
        playQueue = preparedTracks;
      }

      // Inicia reprodução com a fila completa
      ref.read(playerProvider.notifier).playContext(
        queue: playQueue,
        initialIndex: playIndex,
        shuffle: false,
      );

      // Pré-download da próxima música em background
      _preloadNextTrack(ref, playQueue, playIndex);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao reproduzir: $e"),
          backgroundColor: Colors.red));
    }
  }

  /// Faz pré-download da próxima música em background
  void _preloadNextTrack(WidgetRef ref, List<Map<String, dynamic>> queue, int currentIndex) async {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= queue.length) return;
    
    final nextTrack = queue[nextIndex];
    if (nextTrack['filename'] != null) return;
    
    try {
      print("📥 Pré-carregando próxima: ${nextTrack['trackName'] ?? nextTrack['display_name']}");
      await ref.read(searchControllerProvider).smartDownload(nextTrack);
    } catch (e) {
      print("⚠️ Erro ao pré-carregar próxima música: $e");
    }
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    return "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  void _showPlaylistOptionsModal(Map<String, dynamic> playlistData, List<Map<String, dynamic>> tracks) {
    final isFavorites = widget.playlistId == 'favorites' || widget.playlistId.isEmpty;
    final playlistName = playlistData['name'] ?? 'Playlist';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final downloadProgress = ref.watch(downloadProgressProvider);
            final isDownloading = downloadProgress.isDownloading && 
                downloadProgress.batchName == playlistName;
            
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- DOWNLOAD PLAYLIST ---
                  ListTile(
                    leading: isDownloading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _vibrantColor,
                            ),
                          )
                        : Icon(Icons.download, color: _vibrantColor),
                    title: Text(
                      isDownloading
                          ? "Baixando ${downloadProgress.currentTrack}/${downloadProgress.totalTracks}..."
                          : "Baixar playlist para offline",
                      style: GoogleFonts.firaSans(color: Colors.white),
                    ),
                    subtitle: isDownloading
                        ? LinearProgressIndicator(
                            value: (downloadProgress.currentTrack - 1 + downloadProgress.progress) / 
                                   downloadProgress.totalTracks,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(_vibrantColor),
                          )
                        : Text("${tracks.length} músicas",
                            style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12)),
                    onTap: isDownloading
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Baixando ${tracks.length} músicas..."),
                                backgroundColor: const Color(0xFFD4AF37),
                              ),
                            );
                            
                            final count = await ref
                                .read(downloadProgressProvider.notifier)
                                .downloadPlaylist(playlistName, tracks);
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("$count músicas baixadas!"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                  ),
                  if (!isFavorites) ...[
                    ListTile(
                      leading: Icon(Icons.image, color: _vibrantColor),
                      title: Text("Alterar capa da playlist",
                          style: GoogleFonts.firaSans(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showChangeCoverModal(playlistData);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.edit, color: _vibrantColor),
                      title: Text("Renomear playlist",
                          style: GoogleFonts.firaSans(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRenameModal(playlistData);
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(Icons.share, color: _vibrantColor),
                    title: Text("Compartilhar",
                        style: GoogleFonts.firaSans(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChangeCoverModal(Map<String, dynamic> playlistData) {
    final controller = TextEditingController(text: playlistData['cover_url'] ?? '');
    final picker = ImagePicker();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Nova capa da playlist",
                  style: GoogleFonts.firaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              
              // --- OPÇÃO 1: ESCOLHER DA GALERIA ---
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _vibrantColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: _vibrantColor),
                ),
                title: Text("Escolher da galeria",
                    style: GoogleFonts.firaSans(color: Colors.white)),
                subtitle: Text("Selecione uma imagem do dispositivo",
                    style: GoogleFonts.firaSans(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      final fileName = image.name;
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fazendo upload da imagem...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      final coverUrl = await ref
                          .read(libraryControllerProvider)
                          .uploadPlaylistCover(int.parse(widget.playlistId), bytes, fileName);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(coverUrl != null
                                ? 'Capa atualizada!'
                                : 'Erro ao atualizar capa'),
                            backgroundColor: coverUrl != null ? Colors.green : Colors.red,
                          ),
                        );
                        if (coverUrl != null) {
                          ref.invalidate(playlistDetailsProvider(widget.playlistId));
                        }
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao selecionar imagem: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              
              const Divider(color: Colors.white24),
              
              // --- OPÇÃO 2: COLAR URL ---
              Text("Ou cole a URL de uma imagem:",
                  style: GoogleFonts.firaSans(
                      fontSize: 14,
                      color: Colors.white70)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: GoogleFonts.firaSans(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "https://exemplo.com/imagem.jpg",
                  hintStyle: GoogleFonts.firaSans(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vibrantColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (controller.text.trim().isNotEmpty) {
                      final success = await ref
                          .read(libraryControllerProvider)
                          .updatePlaylistCover(
                              int.parse(widget.playlistId), controller.text.trim());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? 'Capa atualizada!'
                                : 'Erro ao atualizar capa'),
                            backgroundColor: success ? Colors.green : Colors.red,
                          ),
                        );
                        if (success) {
                          ref.invalidate(playlistDetailsProvider(widget.playlistId));
                        }
                      }
                    }
                  },
                  child: Text("Salvar URL",
                      style: GoogleFonts.firaSans(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showRenameModal(Map<String, dynamic> playlistData) {
    final controller = TextEditingController(text: playlistData['name'] ?? '');
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Renomear playlist",
                  style: GoogleFonts.firaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.firaSans(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Nome da playlist",
                  hintStyle: GoogleFonts.firaSans(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vibrantColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (controller.text.trim().isNotEmpty) {
                      final dio = ref.read(dioProvider);
                      try {
                        await dio.put(
                          '/users/me/playlists/${widget.playlistId}',
                          data: {'name': controller.text.trim()},
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Playlist renomeada!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          ref.invalidate(playlistDetailsProvider(widget.playlistId));
                          ref.invalidate(userPlaylistsProvider);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erro ao renomear: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: Text("Salvar",
                      style: GoogleFonts.firaSans(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class EqualizerAnimation extends StatefulWidget {
  final Color color;
  final bool isAnimating;
  const EqualizerAnimation(
      {super.key, required this.color, required this.isAnimating});

  @override
  State<EqualizerAnimation> createState() => _EqualizerAnimationState();
}

class _EqualizerAnimationState extends State<EqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimating) {
      return Icon(Icons.graphic_eq, color: widget.color, size: 20);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(0.6),
            const SizedBox(width: 2),
            _bar(1.0),
            const SizedBox(width: 2),
            _bar(0.4),
          ],
        );
      },
    );
  }

  Widget _bar(double scaleMax) {
    final height = 12.0 * (0.3 + (scaleMax * _controller.value * 0.7));
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
          color: widget.color, borderRadius: BorderRadius.circular(2)),
    );
  }
}
