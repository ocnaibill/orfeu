import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

// --- Configuração de Rede ---
const String serverIp = '127.0.0.1';
const String baseUrl = 'https://orfeu.ocnaibill.dev';

// --- Armazenamento Seguro ---
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);

// --- ESTADO DE AUTENTICAÇÃO ---
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? token;
  final String? username;
  final String? error;

  AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.token,
    this.username,
    this.error,
  });

  AuthState copyWith(
      {bool? isAuthenticated,
      bool? isLoading,
      String? token,
      String? username,
      String? error}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      username: username ?? this.username,
      error: error ?? this.error,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(AuthState()) {
    _checkToken();
  }

  Future<void> _checkToken() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final username = await _storage.read(key: 'username');

      if (token != null) {
        state = AuthState(
            isAuthenticated: true,
            isLoading: false,
            token: token,
            username: username);
      } else {
        state = AuthState(isAuthenticated: false, isLoading: false);
      }
    } catch (e) {
      print("⚠️ Erro ao ler token do disco: $e");
      state = AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final dio = Dio(BaseOptions(
          baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)));

      final response = await dio.post('/token',
          data: FormData.fromMap({
            'username': username,
            'password': password,
          }));

      final token = response.data['access_token'];

      try {
        await _storage.write(key: 'jwt_token', value: token);
        await _storage.write(key: 'username', value: username);
      } catch (e) {
        print("⚠️ Falha de Persistência (Login segue em memória): $e");
      }

      state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          token: token,
          username: username);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? "Erro de conexão: ${e.message}";
      state = state.copyWith(isLoading: false, error: msg.toString());
      return false;
    } catch (e) {
      print("❌ Erro inesperado no login: $e");
      state = state.copyWith(isLoading: false, error: "Erro inesperado: $e");
      return false;
    }
  }

  Future<bool> register(
      String username, String email, String password, String fullName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      await dio.post('/auth/register', data: {
        "username": username,
        "email": email,
        "password": password,
        "full_name": fullName
      });

      return await login(username, password);
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? "Erro no registro";
      state = state.copyWith(isLoading: false, error: msg.toString());
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'username');
    } catch (e) {
      print("⚠️ Erro ao limpar token: $e");
    }
    state = AuthState(isAuthenticated: false, isLoading: false);
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

// --- Cliente HTTP (Autenticado) ---
final dioProvider = Provider((ref) {
  final authState = ref.watch(authProvider);

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));

  if (authState.token != null) {
    dio.options.headers['Authorization'] = 'Bearer ${authState.token}';
  }

  return dio;
});

// --- Estados Globais (App) ---
final searchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final hasSearchedProvider = StateProvider<bool>((ref) => false);
final searchTypeProvider = StateProvider<String>((ref) => 'song');
final searchOffsetProvider = StateProvider<int>((ref) => 0);
final hasMoreResultsProvider = StateProvider<bool>((ref) => true);
final isFetchingMoreProvider = StateProvider<bool>((ref) => false);
final processingItemsProvider = StateProvider<Set<String>>((ref) => {});
final downloadStatusProvider = StateProvider<Map<String, dynamic>>((ref) => {});
final currentSearchIdProvider = StateProvider<String?>((ref) => null);

// --- BIBLIOTECA E PLAYLISTS ---
final favoriteTracksProvider = StateProvider<Set<String>>((ref) => {});
final userPlaylistsProvider = StateProvider<List<dynamic>>((ref) => []);

final searchControllerProvider = Provider((ref) => SearchController(ref));
final libraryControllerProvider = Provider((ref) => LibraryController(ref));

class LibraryController {
  final Ref ref;
  LibraryController(this.ref);

  Future<void> fetchFavorites() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/users/me/favorites');
      final List<dynamic> data = response.data;
      final favorites = data.map((item) => item['filename'].toString()).toSet();
      ref.read(favoriteTracksProvider.notifier).state = favorites;
    } catch (e) {
      print("⚠️ Erro ao carregar favoritos: $e");
    }
  }

  // Busca lista de playlists criadas
  Future<void> fetchPlaylists() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/users/me/playlists');
      ref.read(userPlaylistsProvider.notifier).state = response.data;
    } catch (e) {
      print("⚠️ Erro playlists: $e");
    }
  }

  // Cria nova playlist
  Future<bool> createPlaylist(String name, bool isPublic) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/users/me/playlists',
          data: {"name": name, "is_public": isPublic});
      // Atualiza a lista local
      await fetchPlaylists();
      return true;
    } catch (e) {
      print("❌ Erro criar playlist: $e");
      return false;
    }
  }

  // Busca detalhes de uma playlist (tracks)
  Future<Map<String, dynamic>> getPlaylistDetails(int playlistId) async {
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.get('/users/me/playlists/$playlistId');
      return resp.data;
    } catch (e) {
      print("❌ Erro detalhes playlist: $e");
      rethrow;
    }
  }

  Future<void> toggleFavorite(Map<String, dynamic> track) async {
    final dio = ref.read(dioProvider);
    final filename = track['filename'];
    if (filename == null) return;

    final currentFavorites = ref.read(favoriteTracksProvider);
    final isFavorite = currentFavorites.contains(filename);

    if (isFavorite) {
      ref.read(favoriteTracksProvider.notifier).state = {...currentFavorites}
        ..remove(filename);
    } else {
      ref.read(favoriteTracksProvider.notifier).state = {
        ...currentFavorites,
        filename
      };
    }

    try {
      await dio.post('/users/me/favorites', data: {
        "filename": filename,
        "title": track['display_name'] ?? track['trackName'],
        "artist": track['artist'] ?? track['artistName'],
        "album": track['album'] ?? track['collectionName'],
      });
    } catch (e) {
      print("❌ Erro ao favoritar: $e");
      ref.read(favoriteTracksProvider.notifier).state = currentFavorites;
    }
  }
}

class SearchController {
  final Ref ref;
  SearchController(this.ref);

  Future<void> searchCatalog(String query) async {
    if (query.isEmpty) return;

    final dio = ref.read(dioProvider);
    final notifier = ref.read(searchResultsProvider.notifier);
    final loading = ref.read(isLoadingProvider.notifier);
    final hasSearched = ref.read(hasSearchedProvider.notifier);
    final searchType = ref.read(searchTypeProvider);

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

  Future<Map<String, dynamic>> getAlbumDetails(String collectionId) async {
    final dio = ref.read(dioProvider);
    try {
      final resp = await dio.get('/catalog/album/$collectionId');
      return resp.data;
    } catch (e) {
      print('❌ Erro álbum: $e');
      rethrow;
    }
  }

  Future<String?> smartDownload(Map<String, dynamic> catalogItem) async {
    final dio = ref.read(dioProvider);
    final processing = ref.read(processingItemsProvider.notifier);
    final itemId = "${catalogItem['artistName']}-${catalogItem['trackName']}";

    try {
      processing.update((state) => {...state, itemId});
      print('🤖 Smart DL: $itemId');

      final resp = await dio.post('/download/smart', data: {
        "artist": catalogItem['artistName'],
        "track": catalogItem['trackName'],
        "album": catalogItem['collectionName'],
        "tidalId": catalogItem['tidalId'],
        "artworkUrl": catalogItem['artworkUrl']
      });

      final filename = resp.data['file'];
      _pollDownloadStatus(filename);
      return filename;
    } catch (e) {
      print('❌ Erro no smart download: $e');
      rethrow;
    } finally {
      processing.update((state) => {...state}..remove(itemId));
    }
  }

  Future<void> refresh() async {
    // Método placeholder para compatibilidade
  }

  void _pollDownloadStatus(String filename) async {
    final dio = ref.read(dioProvider);
    final statusNotifier = ref.read(downloadStatusProvider.notifier);
    bool isFinished = false;
    int attempts = 0;

    while (!isFinished && attempts < 600) {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;
      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        statusNotifier.update((state) => {...state, filename: resp.data});
        if (resp.data['state'] == 'Completed' ||
            resp.data['state'] == 'Aborted') isFinished = true;
      } catch (e) {}
    }
  }
}
