import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// --- Configuração de Rede ---
// Agora apontamos para o domínio com HTTPS (SSL gerado pela Cloudflare)
const String baseUrl = 'https://orfeu.ocnaibill.dev';

// --- Cliente HTTP ---
final dioProvider = Provider((ref) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    // Timeout ajustado para 60s para suportar buscas P2P mais longas
    receiveTimeout: const Duration(seconds: 60),
  ));
});

// --- Estados Globais ---
final searchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final hasSearchedProvider = StateProvider<bool>((ref) => false);

// Rastreia quais itens do catálogo estão sendo processados pelo Backend (buscando P2P)
final processingItemsProvider = StateProvider<Set<String>>((ref) => {});

// Rastreia o status de download por NOME DE ARQUIVO (retornado pelo backend)
final downloadStatusProvider = StateProvider<Map<String, dynamic>>((ref) => {});

// --- Controller de Busca e Download ---
final searchControllerProvider = Provider((ref) => SearchController(ref));

class SearchController {
  final Ref ref;
  SearchController(this.ref);

  // 1. Busca no Catálogo (iTunes) - Rápida e Visual
  Future<void> searchCatalog(String query) async {
    if (query.isEmpty) return;

    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final loading = ref.read(isLoadingProvider.notifier);
    final hasSearched = ref.read(hasSearchedProvider.notifier);

    try {
      loading.state = true;
      hasSearched.state = true;
      notifier.state = [];

      print('🔍 Buscando no catálogo: $query');
      // Chama a nova rota de catálogo
      final resp =
          await dio.get('/search/catalog', queryParameters: {'query': query});

      notifier.state = resp.data;
    } catch (e) {
      print('❌ Erro na busca de catálogo: $e');
      rethrow;
    } finally {
      loading.state = false;
    }
  }

  // 2. Smart Download - O Backend faz o trabalho sujo
  Future<String?> smartDownload(Map<String, dynamic> catalogItem) async {
    final dio = ref.read(dioProvider);
    final processing = ref.read(processingItemsProvider.notifier);

    // Cria um ID único para o item na lista para mostrar o spinner
    final itemId = "${catalogItem['artistName']}-${catalogItem['trackName']}";

    try {
      // Marca como processando (UI mostra spinner "Buscando melhor versão...")
      processing.update((state) => {...state, itemId});
      print('🤖 Iniciando Smart Download para: $itemId');

      final resp = await dio.post('/download/smart', data: {
        "artist": catalogItem['artistName'],
        "track": catalogItem['trackName'],
        "album": catalogItem['collectionName']
      });

      // O backend retorna o nome do arquivo que ele escolheu/baixou
      final filename = resp.data['file'];
      print('⬇️ Arquivo escolhido pelo Orfeu: $filename');

      // Começa a monitorar o progresso real desse arquivo
      _pollDownloadStatus(filename);

      return filename;
    } catch (e) {
      print('❌ Erro no smart download: $e');
      rethrow;
    } finally {
      // Remove do estado de processamento
      processing.update((state) => {...state}..remove(itemId));
    }
  }

  // Monitora o status de um arquivo específico até completar
  void _pollDownloadStatus(String filename) async {
    final dio = ref.read(dioProvider);
    final statusNotifier = ref.read(downloadStatusProvider.notifier);

    bool isFinished = false;
    int attempts = 0;
    const maxAttempts = 600; // 10 minutos de timeout

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
          isFinished = true;
          print("✅ Download concluído: $filename");
        } else if (state == 'Aborted' || state == 'Cancelled') {
          isFinished = true;
          print("❌ Download cancelado/falhou: $filename");
        }
      } catch (e) {
        // Silently fail on network glitches during polling
      }
    }
  }
}
