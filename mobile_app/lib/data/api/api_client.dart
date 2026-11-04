import 'package:dio/dio.dart';

import 'api_exception.dart';

typedef TokenProvider = String? Function();

/// Cliente HTTP do Orfeu.
///
/// - põe `Authorization: Bearer` em toda chamada autenticada, lendo o token na
///   hora da chamada (não precisa recriar o cliente quando o usuário loga);
/// - quando o servidor responde 401 a uma chamada com token, avisa
///   [onUnauthorized] (o app desloga);
/// - os métodos `getJson`/`postJson`/... devolvem o JSON decodificado e só
///   lançam [ApiException]. O [dio] cru continua exposto para o código legado,
///   que espera `DioException`.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required TokenProvider tokenProvider,
    void Function()? onUnauthorized,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 60),
  })  : _tokenProvider = tokenProvider,
        _onUnauthorized = onUnauthorized,
        dio = dio ?? Dio() {
    this.dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = connectTimeout
      ..receiveTimeout = receiveTimeout;
    this.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.extra[_authKey] != false) {
          final token = _tokenProvider();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (e, handler) {
        final sentToken = e.requestOptions.headers.containsKey('Authorization');
        if (e.response?.statusCode == 401 && sentToken) {
          _onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));
  }

  static const _authKey = 'auth';

  final String baseUrl;
  final Dio dio;
  final TokenProvider _tokenProvider;
  final void Function()? _onUnauthorized;

  Future<dynamic> getJson(String path,
          {Map<String, dynamic>? query, bool authenticated = true}) =>
      _send('GET', path, query: query, authenticated: authenticated);

  Future<dynamic> postJson(String path,
          {Object? body, Map<String, dynamic>? query, bool authenticated = true}) =>
      _send('POST', path, body: body, query: query, authenticated: authenticated);

  Future<dynamic> putJson(String path, {Object? body, bool authenticated = true}) =>
      _send('PUT', path, body: body, authenticated: authenticated);

  Future<dynamic> patchJson(String path, {Object? body, bool authenticated = true}) =>
      _send('PATCH', path, body: body, authenticated: authenticated);

  Future<dynamic> deleteJson(String path, {bool authenticated = true}) =>
      _send('DELETE', path, authenticated: authenticated);

  /// `application/x-www-form-urlencoded` (o `/token` do OAuth2 do FastAPI).
  Future<dynamic> postForm(String path, Map<String, String> fields,
          {bool authenticated = false}) =>
      _send('POST', path,
          body: fields,
          contentType: Headers.formUrlEncodedContentType,
          authenticated: authenticated);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? contentType,
    required bool authenticated,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: contentType,
          extra: {_authKey: authenticated},
        ),
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
