import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/token_store.dart';

const _unset = Object();

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

  /// Passe `error: null` para limpar o erro (o parâmetro omitido mantém o atual).
  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? token,
    String? username,
    Object? error = _unset,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      username: username ?? this.username,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required TokenStore store,
    required ApiClient Function() api,
    VoidCallback? onSessionStarted,
    VoidCallback? onSessionEnded,
  })  : _store = store,
        _api = api,
        _onSessionStarted = onSessionStarted,
        _onSessionEnded = onSessionEnded,
        super(AuthState()) {
    restoreSession();
  }

  final TokenStore _store;
  final ApiClient Function() _api;
  final VoidCallback? _onSessionStarted;
  final VoidCallback? _onSessionEnded;

  Future<void> restoreSession() async {
    try {
      final token = await _store.readToken();
      final username = await _store.readUsername();
      if (token != null) {
        state = AuthState(
            isAuthenticated: true,
            isLoading: false,
            token: token,
            username: username);
        _onSessionStarted?.call();
      } else {
        state = AuthState(isAuthenticated: false, isLoading: false);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao ler token do disco: $e');
      state = AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api().postForm(
          '/token', {'username': username, 'password': password}) as Map;
      final token = data['access_token'] as String;

      try {
        await _store.save(token: token, username: username);
      } catch (e) {
        debugPrint('⚠️ Falha de persistência (login segue em memória): $e');
      }

      state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          token: token,
          username: username);
      _onSessionStarted?.call();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      debugPrint('❌ Erro inesperado no login: $e');
      state = state.copyWith(isLoading: false, error: 'Erro inesperado: $e');
      return false;
    }
  }

  Future<bool> register(
      String username, String email, String password, String fullName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api().postJson('/auth/register', authenticated: false, body: {
        'username': username,
        'email': email,
        'password': password,
        'full_name': fullName,
      });
      return await login(username, password);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _store.clear();
    } catch (e) {
      debugPrint('⚠️ Erro ao limpar token: $e');
    }
    _onSessionEnded?.call();
    state = AuthState(isAuthenticated: false, isLoading: false);
  }
}
