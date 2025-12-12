import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'player_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();

  void _handleSearch() {
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider).search(_queryController.text);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final hasSearched = ref.watch(hasSearchedProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
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
        Expanded(
          child: isLoading && results.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : results.isEmpty
                  ? Center(
                      child: hasSearched
                          ? const Text("Nenhum resultado encontrado.",
                              style: TextStyle(color: Colors.white54))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.travel_explore,
                                    size: 60, color: Colors.white24),
                                const SizedBox(height: 10),
                                const Text("Explore o submundo P2P",
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: results.length,
                      itemBuilder: (context, index) =>
                          _ResultItem(item: results[index]),
                    ),
        ),
      ],
    );
  }
}

class _ResultItem extends ConsumerWidget {
  final Map<String, dynamic> item;
  const _ResultItem({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadStatusProvider)[item['filename']];
    final isFlac = item['extension'] == 'flac';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PlayerScreen(item: item))),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isFlac
                ? const Color(0xFFD4AF37).withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(isFlac ? "FLAC" : "MP3",
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isFlac ? const Color(0xFFD4AF37) : Colors.grey)),
        ),
        title: Text(item['display_name'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white)),
        subtitle: _buildSubtitle(item, downloadState),
        trailing: _buildActionIcon(ref, item, downloadState, context),
      ),
    );
  }

  Widget _buildSubtitle(
      Map<String, dynamic> item, Map<String, dynamic>? status) {
    if (status != null && status['state'] != 'Completed') {
      return Text(
          "${status['state']} ${(status['progress']?.toStringAsFixed(0))}%",
          style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11));
    }
    return Text("${(item['size'] / 1024 / 1024).toStringAsFixed(1)} MB",
        style: const TextStyle(color: Colors.white38, fontSize: 12));
  }

  Widget _buildActionIcon(WidgetRef ref, Map<String, dynamic> item,
      Map<String, dynamic>? status, BuildContext context) {
    if (status == null) {
      return IconButton(
        icon: const Icon(Icons.download_rounded, color: Colors.white70),
        onPressed: () {
          ref.read(searchControllerProvider).download(item);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Adicionado à fila"),
              duration: Duration(seconds: 1)));
        },
      );
    }
    if (status['state'] == 'Completed')
      return const Icon(Icons.check_circle, color: Colors.green);
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
          value: (status['progress'] ?? 0) / 100,
          strokeWidth: 2,
          color: const Color(0xFFD4AF37)),
    );
  }
}
