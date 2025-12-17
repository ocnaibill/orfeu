import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
final savedAlbumsProvider = StateProvider<List<dynamic>>((ref) => []);
final savedArtistsProvider = StateProvider<List<dynamic>>((ref) => []);

final searchControllerProvider = Provider((ref) => SearchController(ref));
final libraryControllerProvider = Provider((ref) => LibraryController(ref));

// --- NOVOS PROVIDERS DA HOME ---
final homeNewReleasesProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/home/new-releases');
  return resp.data;
});

final homeContinueListeningProvider =
    FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/home/continue-listening');
  return resp.data;
});

final homeRecommendationsProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/home/recommendations');
  return resp.data;
});

final homeDiscoverProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/home/discover');
  return resp.data;
});

final homeTrajectoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/home/trajectory');
  return resp.data;
});

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

  Future<void> fetchPlaylists() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/users/me/playlists');
      ref.read(userPlaylistsProvider.notifier).state = response.data;
    } catch (e) {
      print("⚠️ Erro playlists: $e");
    }
  }

  Future<bool> createPlaylist(String name, bool isPublic) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/users/me/playlists',
          data: {"name": name, "is_public": isPublic});
      await fetchPlaylists();
      return true;
    } catch (e) {
      print("❌ Erro criar playlist: $e");
      return false;
    }
  }

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

    // CORREÇÃO: Enviar duração e capa para o backend salvar corretamente
    dynamic durationSec = 0;
    if (track['durationMs'] != null) {
      durationSec = (track['durationMs'] / 1000);
    } else if (track['duration'] != null) {
      durationSec = track['duration'];
    }

    // Tenta pegar a melhor capa disponível
    final cover =
        track['artworkUrl'] ?? track['imageUrl'] ?? track['cover'] ?? '';

    try {
      await dio.post('/users/me/favorites', data: {
        "filename": filename,
        "title": track['display_name'] ?? track['trackName'] ?? track['title'],
        "artist": track['artist'] ?? track['artistName'],
        "album": track['album'] ?? track['collectionName'],
        "cover": cover, // Salva a capa
        "duration": durationSec, // Salva a duração em segundos
      });
    } catch (e) {
      print("❌ Erro ao favoritar: $e");
      ref.read(favoriteTracksProvider.notifier).state = currentFavorites;
    }
  }

  // --- REGISTRO DE HISTÓRICO ---
  Future<void> logPlay(String filename, int seconds) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/users/me/history',
          data: {"filename": filename, "duration_listened": seconds});
      print("✅ Play registrado: $filename ($seconds s)");
    } catch (e) {
      print("⚠️ Erro ao registrar play: $e");
    }
  }

  // --- ÁLBUNS SALVOS ---
  Future<void> fetchSavedAlbums() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/users/me/albums');
      ref.read(savedAlbumsProvider.notifier).state = response.data;
    } catch (e) {
      print("⚠️ Erro ao carregar álbuns salvos: $e");
    }
  }

  Future<bool> saveAlbum(Map<String, dynamic> album) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/users/me/albums', data: {
        "album_id":
            album['id']?.toString() ?? album['collectionId']?.toString(),
        "title": album['title'] ?? album['collectionName'],
        "artist": album['artist'] ?? album['artistName'],
        "artwork_url": album['artworkUrl'] ?? album['imageUrl'],
        "year": album['year'] ?? album['releaseYear'],
      });
      await fetchSavedAlbums();
      return true;
    } catch (e) {
      print("❌ Erro ao salvar álbum: $e");
      return false;
    }
  }

  Future<bool> removeAlbum(String albumId) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/users/me/albums/$albumId');
      await fetchSavedAlbums();
      return true;
    } catch (e) {
      print("❌ Erro ao remover álbum: $e");
      return false;
    }
  }

  bool isAlbumSaved(String albumId) {
    final albums = ref.read(savedAlbumsProvider);
    return albums.any((a) => a['id'] == albumId);
  }

  // --- ARTISTAS SALVOS ---
  Future<void> fetchSavedArtists() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/users/me/artists');
      ref.read(savedArtistsProvider.notifier).state = response.data;
    } catch (e) {
      print("⚠️ Erro ao carregar artistas salvos: $e");
    }
  }

  Future<bool> saveArtist(Map<String, dynamic> artist) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/users/me/artists', data: {
        "artist_id": artist['id']?.toString() ?? artist['artistId']?.toString(),
        "name": artist['name'] ?? artist['artistName'],
        "image_url": artist['imageUrl'] ?? artist['image'],
      });
      await fetchSavedArtists();
      return true;
    } catch (e) {
      print("❌ Erro ao salvar artista: $e");
      return false;
    }
  }

  Future<bool> removeArtist(String artistId) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/users/me/artists/$artistId');
      await fetchSavedArtists();
      return true;
    } catch (e) {
      print("❌ Erro ao remover artista: $e");
      return false;
    }
  }

  bool isArtistSaved(String artistId) {
    final artists = ref.read(savedArtistsProvider);
    return artists.any((a) => a['id'] == artistId);
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
      final status = resp.data['status'];

      // Se o arquivo já estava baixado, retorna imediatamente
      if (status == "Already downloaded") {
        return filename;
      }

      // Se o download foi iniciado, aguarda ele completar
      if (status == "Download started" || status == "Queued") {
        print('⏳ Aguardando download completar: $filename');
        final completed = await _waitForDownload(filename);
        if (completed) {
          return filename;
        } else {
          throw Exception('Download falhou ou timeout');
        }
      }

      // Para Soulseek (que pode retornar "Queued")
      _pollDownloadStatus(filename);
      return filename;
    } catch (e) {
      print('❌ Erro no smart download: $e');
      rethrow;
    } finally {
      processing.update((state) => {...state}..remove(itemId));
    }
  }

  Future<bool> _waitForDownload(String filename) async {
    final dio = ref.read(dioProvider);
    final statusNotifier = ref.read(downloadStatusProvider.notifier);
    int attempts = 0;
    const maxAttempts = 120; // 2 minutos máximo

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;

      try {
        final encodedName = Uri.encodeComponent(filename);
        final resp = await dio.get('/download/status?filename=$encodedName');
        final state = resp.data['state'];

        statusNotifier.update((data) => {...data, filename: resp.data});

        if (state == 'Completed') {
          print('✅ Download concluído: $filename');
          return true;
        }

        if (state == 'Aborted' || state == 'Failed') {
          print('❌ Download falhou: $filename');
          return false;
        }

        // Log progresso a cada 10 segundos
        if (attempts % 10 == 0) {
          final progress = resp.data['progress'] ?? 0;
          print(
              '⏳ Download em andamento ($attempts s): ${progress.toStringAsFixed(1)}%');
        }
      } catch (e) {
        // Ignora erros de rede temporários
        print('⚠️ Erro ao verificar status: $e');
      }
    }

    print('⚠️ Timeout aguardando download: $filename');
    return false;
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

// --- PROFILE STATS PROVIDER ---
class ProfileStats {
  final int playlistCount;
  final int genreCount;
  final int artistCount;
  final int totalMinutes;
  final int totalPlays;
  final String topArtist;
  final bool isLoading;
  final String? error;

  ProfileStats({
    this.playlistCount = 0,
    this.genreCount = 0,
    this.artistCount = 0,
    this.totalMinutes = 0,
    this.totalPlays = 0,
    this.topArtist = "Nenhum",
    this.isLoading = true,
    this.error,
  });

  ProfileStats copyWith({
    int? playlistCount,
    int? genreCount,
    int? artistCount,
    int? totalMinutes,
    int? totalPlays,
    String? topArtist,
    bool? isLoading,
    String? error,
  }) {
    return ProfileStats(
      playlistCount: playlistCount ?? this.playlistCount,
      genreCount: genreCount ?? this.genreCount,
      artistCount: artistCount ?? this.artistCount,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      totalPlays: totalPlays ?? this.totalPlays,
      topArtist: topArtist ?? this.topArtist,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ProfileStatsNotifier extends StateNotifier<ProfileStats> {
  final Ref ref;

  ProfileStatsNotifier(this.ref) : super(ProfileStats()) {
    load();
  }

  Future<void> load() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final authState = ref.read(authProvider);
      if (authState.token == null) {
        state = state.copyWith(isLoading: false, error: "Não autenticado");
        return;
      }

      final dio = Dio();
      dio.options.headers['Authorization'] = 'Bearer ${authState.token}';
      dio.options.baseUrl = baseUrl;

      // Faz as requisições em paralelo
      final results = await Future.wait([
        dio.get('/users/me/analytics/summary').catchError(
            (e) => Response(requestOptions: RequestOptions(), data: {})),
        dio.get('/users/me/playlists').catchError(
            (e) => Response(requestOptions: RequestOptions(), data: [])),
      ]);

      final analyticsData = results[0].data as Map<String, dynamic>? ?? {};
      final playlistsData = results[1].data as List? ?? [];

      state = ProfileStats(
        playlistCount: playlistsData.length,
        genreCount: analyticsData['unique_genres'] ?? 0,
        artistCount: analyticsData['unique_artists'] ?? 0,
        totalMinutes: analyticsData['total_minutes'] ?? 0,
        totalPlays: analyticsData['total_plays'] ?? 0,
        topArtist: analyticsData['top_artist'] ?? "Nenhum",
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final profileStatsProvider =
    StateNotifierProvider<ProfileStatsNotifier, ProfileStats>((ref) {
  return ProfileStatsNotifier(ref);
});

// --- USER PROFILE PROVIDER ---
class UserProfile {
  final String username;
  final String fullName;
  final String email;
  final String? profileImageUrl;
  final bool isLoading;
  final String? error;

  UserProfile({
    this.username = "",
    this.fullName = "",
    this.email = "",
    this.profileImageUrl,
    this.isLoading = true,
    this.error,
  });

  UserProfile copyWith({
    String? username,
    String? fullName,
    String? email,
    String? profileImageUrl,
    bool? isLoading,
    String? error,
  }) {
    return UserProfile(
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  /// Retorna a URL da imagem de perfil ou um avatar gerado
  String get avatarUrl {
    if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
      return profileImageUrl!;
    }
    return "https://ui-avatars.com/api/?name=${Uri.encodeComponent(fullName.isNotEmpty ? fullName : username)}&background=D4AF37&color=000&size=300";
  }
}

class UserProfileNotifier extends StateNotifier<UserProfile> {
  final Ref ref;

  UserProfileNotifier(this.ref) : super(UserProfile()) {
    load();
  }

  Future<void> load() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final dio = ref.read(dioProvider);
      final response = await dio.get('/users/me');
      final data = response.data;

      state = UserProfile(
        username: data['username'] ?? "",
        fullName: data['full_name'] ?? "",
        email: data['email'] ?? "",
        profileImageUrl: data['profile_image_url'],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> updateProfile({
    String? fullName,
    String? email,
  }) async {
    try {
      final dio = ref.read(dioProvider);

      final updateData = <String, dynamic>{};
      if (fullName != null) updateData['full_name'] = fullName;
      if (email != null) updateData['email'] = email;

      await dio.put('/users/me', data: updateData);

      // Atualiza estado local
      state = state.copyWith(
        fullName: fullName ?? state.fullName,
        email: email ?? state.email,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> uploadProfileImage(
      String base64Data, String contentType) async {
    try {
      final dio = ref.read(dioProvider);

      final response = await dio.post('/users/me/profile-image', data: {
        'image_data': base64Data,
        'content_type': contentType,
      });

      final url = response.data['url'] as String?;
      if (url != null) {
        state = state.copyWith(profileImageUrl: url);
      }

      return url;
    } catch (e) {
      print('❌ Erro ao fazer upload da imagem: $e');
      return null;
    }
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier(ref);
});
