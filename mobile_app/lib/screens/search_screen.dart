import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
    ref.read(searchControllerProvider).searchCatalog(_queryController.text);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final hasSearched = ref.watch(hasSearchedProvider);

    return Column(
      children: [
        // Barra de Busca
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: TextField(
            controller: _queryController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar músicas, artistas...',
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

        // Lista de Resultados
        Expanded(
          child: isLoading && results.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : results.isEmpty
                  ? Center(
                      child: hasSearched
                          ? const Text("Nenhum resultado no catálogo.",
                              style: TextStyle(color: Colors.white54))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.album,
                                    size: 60, color: Colors.white24),
                                const SizedBox(height: 10),
                                const Text(
                                    "Digite para buscar no catálogo global",
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: results.length,
                      itemBuilder: (context, index) =>
                          _CatalogItem(item: results[index]),
                    ),
        ),
      ],
    );
  }
}

class _CatalogItem extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const _CatalogItem({super.key, required this.item});

  @override
  ConsumerState<_CatalogItem> createState() => _CatalogItemState();
}

class _CatalogItemState extends ConsumerState<_CatalogItem> {
  bool _isAutoPlaying =
      false; // Estado local para saber se estamos aguardando download para tocar
  String?
      _downloadingFilename; // Nome do arquivo sendo baixado (para monitorar progresso)

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final itemId = "${item['artistName']}-${item['trackName']}";

    // Verifica se está processando no backend (buscando P2P)
    final isNegotiating = ref.watch(processingItemsProvider).contains(itemId);

    // Verifica status do download se já tivermos o filename
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
        // Capa
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

        // Títulos
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

        // Botão de Ação (Play / Loading)
        trailing:
            _buildActionButton(isDownloaded, isNegotiating, downloadState),

        // O toque no card faz a mesma coisa que o botão
        onTap: () => _handlePlayOrDownload(context, ref),
      ),
    );
  }

  Widget _buildActionButton(bool isDownloaded, bool isNegotiating,
      Map<String, dynamic>? downloadState) {
    // 1. Negociando com Backend (Smart Search em andamento)
    if (isNegotiating) {
      return const SizedBox(
        width: 24,
        height: 24,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
      );
    }

    // 2. Baixando (Temos status de progresso)
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

    // 3. Pronto para tocar (Já baixado ou estado inicial)
    return IconButton(
      icon: Icon(
        Icons.play_arrow_rounded,
        color: isDownloaded
            ? const Color(0xFFD4AF37)
            : Colors.white70, // Dourado se já tem, Branco se vai baixar
        size: 32,
      ),
      onPressed: () => _handlePlayOrDownload(context, ref),
    );
  }

  Future<void> _handlePlayOrDownload(
      BuildContext context, WidgetRef ref) async {
    // 1. Se já está baixado (flag do catálogo), toca direto
    if (widget.item['isDownloaded'] == true &&
        widget.item['filename'] != null) {
      _openPlayer(widget.item['filename']);
      return;
    }

    // 2. Se já estamos baixando, não faz nada (ou cancela? por enquanto ignora)
    if (_isAutoPlaying) return;

    setState(() => _isAutoPlaying = true);

    try {
      // Feedback visual
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preparando música..."),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Inicia Smart Download
      final filename =
          await ref.read(searchControllerProvider).smartDownload(widget.item);

      if (filename == null) throw "Arquivo não encontrado.";

      setState(() => _downloadingFilename = filename);

      // Monitora até completar para abrir o player
      _waitForDownloadAndPlay(filename);
    } catch (e) {
      setState(() {
        _isAutoPlaying = false;
        _downloadingFilename = null;
      });
      if (mounted) {
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
    // Timeout de 10 minutos de download
    while (!isReady && attempts < 600) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
      attempts++;

      try {
        final encodedName = Uri.encodeComponent(filename);
        // Consulta status local (Backend já verifica disco e Slskd)
        final resp = await dio.get('/download/status?filename=$encodedName');
        final state = resp.data['state'];

        if (state == 'Completed') {
          isReady = true;
          _openPlayer(filename);
          // Atualiza estado visual local (opcional, pois navegou)
          if (mounted) setState(() => _isAutoPlaying = false);
        } else if (state == 'Aborted' || state == 'Cancelled') {
          throw "Download cancelado pelo servidor.";
        }
      } catch (e) {
        // Se der erro, paramos o loop
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

    // Monta o objeto que o PlayerScreen espera
    final playerItem = {
      'filename': filename,
      'display_name': widget.item['trackName'],
      'artist': widget.item['artistName'],
      // Adicionamos metadados extras que já temos do iTunes
      'album': widget.item['collectionName'],
      'cover_url': widget.item['artworkUrl']
    };

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(item: playerItem)),
    );
  }
}
