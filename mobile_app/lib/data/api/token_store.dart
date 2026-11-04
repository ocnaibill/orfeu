import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Onde a sessão (JWT + usuário) fica guardada entre execuções.
abstract class TokenStore {
  Future<String?> readToken();
  Future<String?> readUsername();
  Future<void> save({required String token, required String username});
  Future<void> clear();
}

/// Armazenamento seguro do sistema. Mesmas chaves do app antigo, então quem já
/// estava logado continua logado.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const tokenKey = 'jwt_token';
  static const usernameKey = 'username';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: tokenKey);

  @override
  Future<String?> readUsername() => _storage.read(key: usernameKey);

  @override
  Future<void> save({required String token, required String username}) async {
    await _storage.write(key: tokenKey, value: token);
    await _storage.write(key: usernameKey, value: username);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: usernameKey);
  }
}

/// Em memória: testes e fallback quando o armazenamento seguro falha.
class MemoryTokenStore implements TokenStore {
  String? _token;
  String? _username;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<String?> readUsername() async => _username;

  @override
  Future<void> save({required String token, required String username}) async {
    _token = token;
    _username = username;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _username = null;
  }
}
