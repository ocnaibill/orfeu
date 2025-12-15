import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';

// Provider para carregar os dados do álbum
final albumDetailsProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(searchControllerProvider).getAlbumDetails(id);
});

class AlbumScreen extends ConsumerStatefulWidget {
  final String collectionId;
  final String heroTag;

  const AlbumScreen(
      {super.key, required this.collectionId, required this.heroTag});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final Map<String, String> _localTrackFilenames = {};

  void _startRefreshLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) break;
      ref.invalidate(albumDetailsProvider(widget.collectionId));
    }
  }

  @override
  void initState() {
    super.initState();
    // Carrega os favoritos atuais ao abrir o álbum para garantir sincronia
    ref.read(libraryControllerProvider).fetchFavorites();
    _startRefreshLoop();
  }

  bool _isTrackDownloaded(Map<String, dynamic> track) {
    if (track['isDownloaded'] == true) return true;
    final id = "${track['artistName']}-${track['trackName']}";
    final filename = _localTrackFilenames[id];
    if (filename != null) {
      final status = ref.read(downloadStatusProvider)[filename];
      if (status != null && status['state'] == 'Completed') return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final albumAsync = ref.watch(albumDetailsProvider(widget.collectionId));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: albumAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        error: (err, stack) => Center(
            child:
                Text("Erro: $err", style: const TextStyle(color: Colors.red))),
        data: (albumData) {
          final tracks = List<Map<String, dynamic>>.from(albumData['tracks']);

          final int totalTracks = tracks.length;
          final int downloadedCount = tracks.where(_isTrackDownloaded).length;
          final bool allDownloaded = downloadedCount == totalTracks;
          final bool isPartiallyDownloaded =
              downloadedCount > 0 && !allDownloaded;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: const Color(0xFF121212),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Color(0xFF121212)],
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60.0),
                        child: Hero(
                          tag: widget.heroTag,
                          child: Container(
                            height: 180,
                            width: 180,
                            decoration: const BoxDecoration(
                              boxShadow: [
                                BoxShadow(color: Colors.black54, blurRadius: 20)
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(albumData['artworkUrl'],
                                  fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        albumData['collectionName'],
                        style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      Text(
                        "${albumData['artistName']} • ${albumData['year']}",
                        style: GoogleFonts.outfit(
                            fontSize: 16, color: Colors.white54),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          allDownloaded
                              ? "Álbum completo disponível"
                              : "$downloadedCount de $totalTracks faixas prontas",
                          style: TextStyle(
                              color: allDownloaded
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _handleMainAction(context, ref,
                                  tracks, allDownloaded, albumData),
                              icon: Icon(
                                  allDownloaded
                                      ? Icons.play_arrow_rounded
                                      : Icons.download_rounded,
                                  color: Colors.black),
                              label: Text(
                                  allDownloaded
                                      ? "Tocar Álbum"
                                      : (isPartiallyDownloaded
                                          ? "Baixar Restantes"
                                          : "Baixar Álbum"),
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: allDownloaded
                                    ? Colors.greenAccent
                                    : const Color(0xFFD4AF37),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed: () =>
                                _handleShuffleAction(context, tracks),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white10,
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.shuffle,
                                color: Color(0xFFD4AF37)),
                            tooltip: "Aleatório",
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    final itemId =
                        "${track['artistName']}-${track['trackName']}";
                    final localFilename = _localTrackFilenames[itemId];

                    return _AlbumTrackItem(
                      track: track,
                      localFilename: localFilename,
                      // Passamos dados do álbum para caso precisem ser usados no download/favorito
                      albumArtworkUrl: albumData['artworkUrl'],
                      albumCollectionName: albumData['collectionName'],
                      onPlayTap: () => _playQueue(context, tracks, index),
                      onDownloadStart: (filename) {
                        if (mounted) {
                          setState(() {
                            _localTrackFilenames[itemId] = filename;
                          });
                        }
                      },
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

  Future<void> _handleMainAction(
      BuildContext context,
      WidgetRef ref,
      List<Map<String, dynamic>> tracks,
      bool allDownloaded,
      Map<String, dynamic> albumData) async {
    if (allDownloaded) {
      if (tracks.isNotEmpty) {
        _playQueue(context, tracks, 0);
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Solicitando downloads ao servidor..."),
        duration: Duration(seconds: 2)));

    int started = 0;
    for (var track in tracks) {
      if (_isTrackDownloaded(track)) continue;

      final smartTrack = Map<String, dynamic>.from(track);
      if (smartTrack['artworkUrl'] == null)
        smartTrack['artworkUrl'] = albumData['artworkUrl'];
      if (smartTrack['album'] == null)
        smartTrack['album'] = albumData['collectionName'];

      try {
        final filename =
            await ref.read(searchControllerProvider).smartDownload(smartTrack);
        if (filename != null) {
          started++;
          final itemId = "${track['artistName']}-${track['trackName']}";
          if (mounted) {
            setState(() {
              _localTrackFilenames[itemId] = filename;
            });
          }
        }
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print("Erro: $e");
      }
    }

    if (context.mounted && started > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$started faixas atualizadas!"),
          backgroundColor: Colors.green));
    }
  }

  void _handleShuffleAction(
      BuildContext context, List<Map<String, dynamic>> tracks) {
    final playable = _getPlayableTracks(tracks);

    if (playable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Baixe as músicas primeiro."),
          backgroundColor: Colors.orange));
      return;
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(
                  queue: playable,
                  initialIndex: 0,
                  shuffle: true,
                )));
  }

  void _playQueue(BuildContext context, List<Map<String, dynamic>> queue,
      int initialIndex) {
    final playableQueue = _getPlayableTracks(queue);

    if (playableQueue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Nenhuma música disponível."),
          backgroundColor: Colors.orange));
      return;
    }

    final targetTrack = queue[initialIndex];
    int newIndex = playableQueue.indexWhere((t) =>
        t['trackName'] == targetTrack['trackName'] &&
        t['artistName'] == targetTrack['artistName']);

    if (newIndex == -1) newIndex = 0;

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(
                  queue: playableQueue,
                  initialIndex: newIndex,
                  shuffle: false,
                )));
  }

  List<Map<String, dynamic>> _getPlayableTracks(
      List<Map<String, dynamic>> rawTracks) {
    List<Map<String, dynamic>> playable = [];

    for (var t in rawTracks) {
      String? filename = t['filename'];

      if (filename == null) {
        final id = "${t['artistName']}-${t['trackName']}";
        filename = _localTrackFilenames[id];
      }

      if (filename != null) {
        final status = ref.read(downloadStatusProvider)[filename];
        final isLocalCompleted =
            status != null && status['state'] == 'Completed';

        if (t['isDownloaded'] == true || isLocalCompleted) {
          final trackWithFile = Map<String, dynamic>.from(t);
          trackWithFile['filename'] = filename;
          playable.add(trackWithFile);
        }
      }
    }
    return playable;
  }
}

class _AlbumTrackItem extends ConsumerWidget {
  final Map<String, dynamic> track;
  final String? localFilename;
  final String? albumArtworkUrl;
  final String? albumCollectionName;
  final VoidCallback onPlayTap;
  final Function(String) onDownloadStart;

  const _AlbumTrackItem(
      {super.key,
      required this.track,
      this.localFilename,
      this.albumArtworkUrl,
      this.albumCollectionName,
      required this.onPlayTap,
      required this.onDownloadStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemId = "${track['artistName']}-${track['trackName']}";
    final isNegotiating = ref.watch(processingItemsProvider).contains(itemId);

    final downloadState = localFilename != null
        ? ref.watch(downloadStatusProvider)[localFilename]
        : null;

    final bool isCompleted = track['isDownloaded'] == true ||
        (downloadState != null && downloadState['state'] == 'Completed');

    final bool isDownloading =
        (downloadState != null && downloadState['state'] != 'Completed') ||
            isNegotiating;

    // FAVORITOS: Lógica de UI
    final favorites = ref.watch(favoriteTracksProvider);
    // Para verificar se é favorito, precisamos do filename.
    // Se ainda não baixou, não dá para favoritar (pois o backend usa o filename como chave).
    final String? effectiveFilename = track['filename'] ?? localFilename;
    final bool isFavorite =
        effectiveFilename != null && favorites.contains(effectiveFilename);

    return ListTile(
      leading: Text(
        "${track['trackNumber']}",
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      ),
      title: Text(
        track['trackName'],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: isCompleted ? const Color(0xFFD4AF37) : Colors.white,
            fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        _formatDuration(track['durationMs'] ?? 0),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      // TRAILING: Agora contém Download/Play E Favorito
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botão Favorito (Só aparece se já tivermos o arquivo/filename para linkar)
          if (effectiveFilename != null)
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? const Color(0xFFD4AF37) : Colors.white24,
                size: 20,
              ),
              onPressed: () {
                // Monta objeto completo para enviar ao backend se necessário
                final trackToFav = Map<String, dynamic>.from(track);
                trackToFav['filename'] = effectiveFilename;
                trackToFav['album'] = albumCollectionName;
                trackToFav['display_name'] = track['trackName'];
                trackToFav['artist'] = track['artistName'];

                ref.read(libraryControllerProvider).toggleFavorite(trackToFav);
              },
            ),

          const SizedBox(width: 8),

          // Botão de Status (Download/Play)
          _buildStatusIcon(isCompleted, isDownloading, downloadState),
        ],
      ),
      onTap: () {
        if (isCompleted) {
          onPlayTap();
        } else if (!isDownloading) {
          _handleSingleDownload(context, ref);
        }
      },
    );
  }

  Widget _buildStatusIcon(bool isCompleted, bool isDownloading, Map? status) {
    if (isCompleted) {
      return const Icon(Icons.play_circle_outline, color: Color(0xFFD4AF37));
    }
    if (isDownloading) {
      double? progress;
      if (status != null && status['progress'] != null) {
        progress = (status['progress'] as num).toDouble() / 100.0;
      }
      return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            color: const Color(0xFFD4AF37),
            backgroundColor: Colors.white10,
          ));
    }
    return const Icon(Icons.add_circle_outline, color: Colors.white24);
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    return "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  void _handleSingleDownload(BuildContext context, WidgetRef ref) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Buscando..."), duration: Duration(seconds: 1)));

      final smartTrack = Map<String, dynamic>.from(track);
      if (smartTrack['artworkUrl'] == null)
        smartTrack['artworkUrl'] = albumArtworkUrl;
      if (smartTrack['album'] == null)
        smartTrack['album'] = albumCollectionName;

      final filename =
          await ref.read(searchControllerProvider).smartDownload(smartTrack);
      if (filename != null) {
        onDownloadStart(filename);
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    }
  }
}
