import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import 'player_screen.dart';
import 'album_screen.dart'; // Ensure you have this file created

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Listen to scroll events for infinite scrolling
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // If we are near the bottom (200 pixels), trigger load more
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchControllerProvider).loadMoreCatalog(_queryController.text);
    }
  }

  void _handleSearch() {
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider).searchCatalog(_queryController.text);
  }

  void _changeType(String type) {
    // Update the search type state
    ref.read(searchTypeProvider.notifier).state = type;
    // If there is text, re-trigger search with the new type immediately
    if (_queryController.text.isNotEmpty) {
      _handleSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final isFetchingMore = ref.watch(isFetchingMoreProvider);
    final hasSearched = ref.watch(hasSearchedProvider);
    final currentType = ref.watch(searchTypeProvider);

    return Column(
      children: [
        // --- Search Bar ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 10),
          child: TextField(
            controller: _queryController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'O que você quer ouvir?',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Color(0xFFD4AF37)),
                onPressed: _handleSearch,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _handleSearch(),
          ),
        ),

        // --- Filter Chips (Songs vs Albums) ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildFilterChip("Músicas", "song", currentType),
              const SizedBox(width: 10),
              _buildFilterChip("Álbuns", "album", currentType),
            ],
          ),
        ),

        // --- Results List ---
        Expanded(
          child: isLoading && results.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : results.isEmpty
                  ? Center(
                      child: hasSearched
                          ? const Text("Nenhum resultado.",
                              style: TextStyle(color: Colors.white54))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.album,
                                    size: 60, color: Colors.white24),
                                const SizedBox(height: 10),
                                const Text("Digite para buscar",
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                    )
                  : currentType == 'song'
                      ? _buildSongList(results, isFetchingMore)
                      : _buildAlbumList(results, isFetchingMore),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, String currentValue) {
    final isSelected = value == currentValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _changeType(value),
      selectedColor: const Color(0xFFD4AF37),
      backgroundColor: Colors.white10,
      labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildSongList(List<dynamic> results, bool isFetchingMore) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length + (isFetchingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
        }
        return _CatalogItem(item: results[index]);
      },
    );
  }

  Widget _buildAlbumList(List<dynamic> results, bool isFetchingMore) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length + (isFetchingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        }
        return _AlbumItem(item: results[index]);
      },
    );
  }
}

// --- Song Card (Handles Play/Download Logic) ---
class _CatalogItem extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const _CatalogItem({required this.item});

  @override
  ConsumerState<_CatalogItem> createState() => _CatalogItemState();
}

class _CatalogItemState extends ConsumerState<_CatalogItem> {
  bool _isAutoPlaying = false;
  String? _downloadingFilename;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final itemId = "${item['artistName']}-${item['trackName']}";

    final isNegotiating = ref.watch(processingItemsProvider).contains(itemId);

    final downloadState = _downloadingFilename != null
        ? ref.watch(downloadStatusProvider)[_downloadingFilename]
        : null;

    final bool isDownloaded = item['isDownloaded'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            item['artworkUrl'],
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                width: 50,
                height: 50,
                color: Colors.white10,
                child: const Icon(Icons.music_note, color: Colors.white24)),
          ),
        ),
        title: Text(
          item['trackName'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: Text(
          "${item['artistName']} • ${item['year']}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing:
            _buildActionButton(isDownloaded, isNegotiating, downloadState),
        onTap: () => _handlePlayOrDownload(context, ref),
      ),
    );
  }

  Widget _buildActionButton(bool isDownloaded, bool isNegotiating,
      Map<String, dynamic>? downloadState) {
    if (isNegotiating) {
      return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFD4AF37)));
    }

    if (_isAutoPlaying &&
        downloadState != null &&
        downloadState['state'] != 'Completed') {
      final progress = (downloadState['progress'] ?? 0.0) / 100.0;
      return SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: (downloadState['state'] == 'Unknown') ? null : progress,
              color: const Color(0xFFD4AF37),
              backgroundColor: Colors.white10,
              strokeWidth: 3,
            ),
            const Icon(Icons.download, size: 14, color: Colors.white70),
          ],
        ),
      );
    }

    return IconButton(
      icon: Icon(
        Icons.play_arrow_rounded,
        color: isDownloaded ? const Color(0xFFD4AF37) : Colors.white70,
        size: 32,
      ),
      onPressed: () => _handlePlayOrDownload(context, ref),
    );
  }

  Future<void> _handlePlayOrDownload(
      BuildContext context, WidgetRef ref) async {
    if (widget.item['isDownloaded'] == true &&
        widget.item['filename'] != null) {
      _openPlayer(widget.item['filename']);
      return;
    }

    if (_isAutoPlaying) return;

    setState(() => _isAutoPlaying = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preparando música..."),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final filename =
          await ref.read(searchControllerProvider).smartDownload(widget.item);

      if (filename == null) throw "Arquivo não encontrado.";

      setState(() => _downloadingFilename = filename);

      _waitForDownloadAndPlay(filename);
    } catch (e) {
      setState(() {
        _isAutoPlaying = false;
        _downloadingFilename = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _waitForDownloadAndPlay(String filename) async {
    final dio = ref.read(dioProvider);

    bool isReady = false;
    int attempts = 0;
    while (!isReady && attempts < 600) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
      attempts++;

      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        final state = resp.data['state'];

        if (state == 'Completed') {
          isReady = true;
          _openPlayer(filename);
          if (mounted) setState(() => _isAutoPlaying = false);
        } else if (state == 'Aborted' || state == 'Cancelled') {
          throw "Download cancelado pelo servidor.";
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isAutoPlaying = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Erro no download: $e")));
        }
        return;
      }
    }
  }

  void _openPlayer(String filename) {
    if (!mounted) return;

    final playerItem = {
      'filename': filename,
      'display_name': widget.item['trackName'],
      'artist': widget.item['artistName'],
      'album': widget.item['collectionName'],
      'cover_url': widget.item['artworkUrl']
    };

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(item: playerItem)),
    );
  }
}

// --- Album Card (Navigates to AlbumScreen) ---
class _AlbumItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AlbumItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final heroTag = "album_${item['collectionId']}";

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AlbumScreen(
                    collectionId: item['collectionId'].toString(),
                    heroTag: heroTag,
                  )),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: heroTag,
              child: Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                        image: NetworkImage(item['artworkUrl']),
                        fit: BoxFit.cover)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item['collectionName'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            "${item['artistName']} • ${item['year']}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
