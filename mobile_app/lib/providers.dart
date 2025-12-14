import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// --- Configuração de Rede ---
// Aponta para o domínio de produção com HTTPS (Cloudflare Tunnel)
const String baseUrl = 'https://orfeu.ocnaibill.dev';

// --- Cliente HTTP ---
final dioProvider = Provider((ref) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    // Timeout aumentado para 60s para suportar a busca P2P no backend que pode demorar
    receiveTimeout: const Duration(seconds: 60),
  ));
});

// --- Estados Globais ---
final searchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final hasSearchedProvider = StateProvider<bool>((ref) => false);

// Tipo de Busca: 'song' ou 'album'
final searchTypeProvider = StateProvider<String>((ref) => 'song');

// --- Estados de Paginação ---
final searchOffsetProvider = StateProvider<int>((ref) => 0);
final hasMoreResultsProvider = StateProvider<bool>((ref) => true);
final isFetchingMoreProvider = StateProvider<bool>((ref) => false);

// --- Estados de Processamento ---
// Rastreia quais itens do catálogo estão sendo processados pelo Backend (buscando P2P)
final processingItemsProvider = StateProvider<Set<String>>((ref) => {});

// Rastreia o status de download por NOME DE ARQUIVO
final downloadStatusProvider = StateProvider<Map<String, dynamic>>((ref) => {});

// --- Controller Principal ---
final searchControllerProvider = Provider((ref) => SearchController(ref));

class SearchController {
  final Ref ref;
  SearchController(this.ref);

  // 1. Busca Inicial no Catálogo (iTunes)
  Future<void> searchCatalog(String query) async {
    if (query.isEmpty) return;

    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final loading = ref.read(isLoadingProvider.notifier);
    final hasSearched = ref.read(hasSearchedProvider.notifier);
    final searchType = ref.read(searchTypeProvider);

    // Reseta paginação para nova busca
    ref.read(searchOffsetProvider.notifier).state = 0;
    ref.read(hasMoreResultsProvider.notifier).state = true;
    ref.read(isFetchingMoreProvider.notifier).state = false;

    try {
      loading.state = true;
      hasSearched.state = true;
      notifier.state = [];

      print('🔍 Buscando ($searchType): $query');

      final resp = await dio.get('/search/catalog', queryParameters: {
        'query': query,
        'limit': 20,
        'offset': 0,
        'type': searchType
      });

      notifier.state = resp.data;

      // Se vier menos que o limite, não tem mais páginas
      if (resp.data.length < 20) {
        ref.read(hasMoreResultsProvider.notifier).state = false;
      }
    } catch (e) {
      print('❌ Erro na busca de catálogo: $e');
      rethrow;
    } finally {
      loading.state = false;
    }
  }

  // 2. Carregar Mais (Infinite Scroll)
  Future<void> loadMoreCatalog(String query) async {
    final hasMore = ref.read(hasMoreResultsProvider);
    final isFetching = ref.read(isFetchingMoreProvider);

    if (!hasMore || isFetching) return;

    final dio = ref.read(dioProvider);
    final currentOffset = ref.read(searchOffsetProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final fetchingNotifier = ref.read(isFetchingMoreProvider.notifier);
    final searchType = ref.read(searchTypeProvider);

    try {
      fetchingNotifier.state = true;
      final newOffset = currentOffset + 20;

      print('🔍 Carregando mais resultados (Offset $newOffset)...');

      final resp = await dio.get('/search/catalog', queryParameters: {
        'query': query,
        'limit': 20,
        'offset': newOffset,
        'type': searchType
      });

      final List<dynamic> newItems = resp.data;

      if (newItems.isEmpty) {
        ref.read(hasMoreResultsProvider.notifier).state = false;
      } else {
        ref.read(searchOffsetProvider.notifier).state = newOffset;
        notifier.update((state) => [...state, ...newItems]);

        if (newItems.length < 20) {
          ref.read(hasMoreResultsProvider.notifier).state = false;
        }
      }
    } catch (e) {
      print('❌ Erro load more: $e');
    } finally {
      fetchingNotifier.state = false;
    }
  }

  // 3. Detalhes do Álbum
  Future<Map<String, dynamic>> getAlbumDetails(String collectionId) async {
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.get('/catalog/album/$collectionId');
      return resp.data;
    } catch (e) {
      print('❌ Erro ao buscar álbum: $e');
      rethrow;
    }
  }

  // 4. Smart Download - Inicia a busca P2P no Backend
  Future<String?> smartDownload(Map<String, dynamic> catalogItem) async {
    final dio = ref.read(dioProvider);
    final processing = ref.read(processingItemsProvider.notifier);

    // ID único para mostrar spinner no item correto
    final itemId = "${catalogItem['artistName']}-${catalogItem['trackName']}";

    try {
      processing.update((state) => {...state, itemId});
      print('🤖 Iniciando Smart Download para: $itemId');

      final resp = await dio.post('/download/smart', data: {
        "artist": catalogItem['artistName'],
        "track": catalogItem['trackName'],
        "album": catalogItem['collectionName'],
        "tidalId": catalogItem['tidalId'],
        "artworkUrl": catalogItem['artworkUrl'] 
      });

      final filename = resp.data['file'];
      print('⬇️ Arquivo escolhido pelo Orfeu: $filename');

      // Começa a monitorar o progresso
      _pollDownloadStatus(filename);

      return filename;
    } catch (e) {
      print('❌ Erro no smart download: $e');
      rethrow;
    } finally {
      processing.update((state) => {...state}..remove(itemId));
    }
  }

  // 5. Monitoramento de Progresso (Polling)
  void _pollDownloadStatus(String filename) async {
    final dio = ref.read(dioProvider);
    final statusNotifier = ref.read(downloadStatusProvider.notifier);

    bool isFinished = false;
    int attempts = 0;
    const maxAttempts = 600; // ~10 minutos de timeout

    while (!isFinished && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;

      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        final data = resp.data;

        statusNotifier.update((state) {
          final newState = Map<String, dynamic>.from(state);
          newState[filename] = data;
          return newState;
        });

        final state = data['state'];
        if (state == 'Completed') {
          print("✅ Download concluído: $filename");
          isFinished = true;
        } else if (state == 'Aborted' || state == 'Cancelled') {
          print("❌ Download falhou: $filename");
          isFinished = true;
        }
      } catch (e) {
        // Falhas de rede no polling são ignoradas para tentar novamente
      }
    }
  }
}
