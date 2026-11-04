import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'api_client.dart';

/// Resposta de `GET /auth/media-token`.
class MediaToken {
  MediaToken(this.token, this.expiresIn);
  final String token;
  final Duration expiresIn;

  factory MediaToken.fromJson(Map<String, dynamic> json) => MediaToken(
        json['token'] as String,
        Duration(seconds: (json['expires_in'] as num).toInt()),
      );
}

/// URLs e credenciais de mídia (stream, capa, letra).
///
/// O servidor exige login nessas rotas. No app nativo o token vai no header
/// `Authorization`; na web o player HTML5 não manda header, então a URL leva um
/// token de mídia de escopo restrito (`?mt=`), nunca o token da conta.
///
/// O token só vai para o NOSSO servidor: capas do Tidal e outros hosts recebem
/// a URL pura.
class MediaAccess {
  MediaAccess({
    required String baseUrl,
    required TokenProvider tokenProvider,
    this.useQueryToken = kIsWeb,
    Future<MediaToken> Function()? fetchMediaToken,
    DateTime Function()? now,
  })  : _base = Uri.parse(baseUrl),
        _tokenProvider = tokenProvider,
        _fetchMediaToken = fetchMediaToken,
        _now = now ?? DateTime.now;

  final Uri _base;
  final TokenProvider _tokenProvider;
  final Future<MediaToken> Function()? _fetchMediaToken;
  final DateTime Function() _now;

  /// true na web: token de mídia na query em vez de header.
  final bool useQueryToken;

  String? _mediaToken;
  DateTime? _mediaTokenExpiry;
  Future<void>? _refreshing;

  /// URL de streaming de um arquivo da biblioteca.
  String streamUrl(String filename, {String quality = 'lossless'}) =>
      _url('/stream', {'filename': filename, 'quality': quality});

  /// URL da capa embutida no arquivo da biblioteca.
  String coverUrl(String filename) => _url('/cover', {'filename': filename});

  String _url(String path, Map<String, String> query) {
    _refreshIfExpiring();
    final params = {...query};
    if (useQueryToken && _mediaToken != null) params['mt'] = _mediaToken!;
    return _base.replace(path: path, queryParameters: params).toString();
  }

  /// A URL é do nosso servidor? (único destino que pode receber credencial)
  bool isOwnUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasAuthority &&
        uri.scheme == _base.scheme &&
        uri.host == _base.host &&
        uri.port == _base.port;
  }

  /// Headers para uma URL: o Bearer só para o nosso servidor, e só no nativo.
  Map<String, String> headersFor(String url) {
    if (useQueryToken || !isOwnUrl(url)) return const {};
    final token = _tokenProvider();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  /// `NetworkImage` com a credencial certa para a URL.
  NetworkImage imageProvider(String url) =>
      NetworkImage(url, headers: headersFor(url));

  /// Busca um novo token de mídia (só faz algo quando [useQueryToken]).
  Future<void> refresh() {
    if (!useQueryToken || _fetchMediaToken == null) return Future.value();
    // Sem sessão não há o que pedir (e um 401 aqui desligaria o logout em loop).
    final session = _tokenProvider();
    if (session == null || session.isEmpty) return Future.value();
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    try {
      final t = await _fetchMediaToken!();
      _mediaToken = t.token;
      _mediaTokenExpiry = _now().add(t.expiresIn);
    } catch (e) {
      debugPrint('⚠️ Falha ao obter token de mídia: $e');
    }
  }

  /// Esquece o token de mídia (logout).
  void clear() {
    _mediaToken = null;
    _mediaTokenExpiry = null;
  }

  void _refreshIfExpiring() {
    if (!useQueryToken || _fetchMediaToken == null) return;
    final expiry = _mediaTokenExpiry;
    if (_mediaToken == null ||
        (expiry != null && expiry.difference(_now()) < const Duration(minutes: 15))) {
      refresh();
    }
  }
}
