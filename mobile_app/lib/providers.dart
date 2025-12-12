import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// --- Configuração de Rede ---
// Ajuste o IP conforme necessário (127.0.0.1 para Mac/Simulator, IP da rede para outros)
const String serverIp = '127.0.0.1';
const String baseUrl = 'http://$serverIp:8000';

// --- Cliente HTTP ---
final dioProvider = Provider((ref) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
});

// --- Estados Globais ---
final searchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final hasSearchedProvider = StateProvider<bool>((ref) => false);
final currentSearchIdProvider = StateProvider<String?>((ref) => null);
final downloadStatusProvider = StateProvider<Map<String, dynamic>>((ref) => {});

// --- Controller de Busca e Download ---
final searchControllerProvider = Provider((ref) => SearchController(ref));

class SearchController {
  final Ref ref;
  SearchController(this.ref);

  Future<void> search(String query) async {
    if (query.isEmpty) return;

    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final loading = ref.read(isLoadingProvider.notifier);
    final hasSearched = ref.read(hasSearchedProvider.notifier);
    final currentId = ref.read(currentSearchIdProvider.notifier);

    try {
      loading.state = true;
      hasSearched.state = true;
      notifier.state = [];

      print('🔍 Iniciando busca por: $query');
      final searchResp = await dio.post('/search/$query');
      final searchId = searchResp.data['search_id'];

      currentId.state = searchId;
      await _pollResults(searchId);
    } catch (e) {
      print('❌ Erro na busca: $e');
      rethrow;
    } finally {
      loading.state = false;
    }
  }

  Future<void> refresh() async {
    final searchId = ref.read(currentSearchIdProvider);
    if (searchId == null) return;

    final loading = ref.read(isLoadingProvider.notifier);
    try {
      loading.state = true;
      await _pollResults(searchId, attempts: 1);
    } catch (e) {
      print('❌ Erro no refresh: $e');
    } finally {
      loading.state = false;
    }
  }

  Future<void> _pollResults(String searchId, {int attempts = 20}) async {
    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);

    for (int i = 1; i <= attempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final resultsResp = await dio.get('/results/$searchId');
        final List<dynamic> data = resultsResp.data;
        if (data.isNotEmpty) {
          notifier.state = data;
        }
      } catch (e) {
        print('⚠️ Erro polling: $e');
      }
    }
  }

  Future<void> download(Map<String, dynamic> item) async {
    final dio = ref.read(dioProvider);
    final filename = item['filename'];

    try {
      await dio.post('/download', data: {
        "username": item['username'],
        "filename": filename,
        "size": item['size']
      });
      _pollDownloadStatus(filename);
    } catch (e) {
      print('❌ Erro no download: $e');
      rethrow;
    }
  }

  void _pollDownloadStatus(String filename) async {
    final dio = ref.read(dioProvider);
    final statusNotifier = ref.read(downloadStatusProvider.notifier);

    bool isFinished = false;
    int attempts = 0;
    const maxAttempts = 600;

    while (!isFinished && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;
      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        statusNotifier.update((state) {
          final newState = Map<String, dynamic>.from(state);
          newState[filename] = resp.data;
          return newState;
        });

        final state = resp.data['state'];
        if (state == 'Completed' || state == 'Aborted') isFinished = true;
      } catch (e) {
        print("⚠️ Erro polling status: $e");
      }
    }
  }
}
