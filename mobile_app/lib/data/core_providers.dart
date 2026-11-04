import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/media_access.dart';
import 'api/server_config.dart';
import 'api/token_store.dart';
import 'auth/auth_controller.dart';

export 'auth/auth_controller.dart' show AuthState, AuthController;

/// Onde a sessão fica guardada. Os testes trocam por [MemoryTokenStore].
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Sessão do usuário (login, token, logout).
final StateNotifierProvider<AuthController, AuthState> authProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    store: ref.read(tokenStoreProvider),
    api: () => ref.read(apiClientProvider),
    onSessionStarted: () => ref.read(mediaAccessProvider).refresh(),
    onSessionEnded: () => ref.read(mediaAccessProvider).clear(),
  );
});

/// Cliente HTTP único do app. Lê o token na hora de cada chamada; um 401 numa
/// chamada autenticada encerra a sessão.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ServerConfig.defaultBaseUrl,
    tokenProvider: () => ref.read(authProvider).token,
    onUnauthorized: () => ref.read(authProvider.notifier).logout(),
  );
});

/// URLs e credenciais de stream/capa/letra.
final Provider<MediaAccess> mediaAccessProvider = Provider<MediaAccess>((ref) {
  return MediaAccess(
    baseUrl: ServerConfig.defaultBaseUrl,
    tokenProvider: () => ref.read(authProvider).token,
    fetchMediaToken: () async => MediaToken.fromJson(
        (await ref.read(apiClientProvider).getJson('/auth/media-token'))
            as Map<String, dynamic>),
  );
});
