import 'package:dio/dio.dart';

/// Erro de API já traduzido para algo que a UI pode mostrar.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isNetworkError = false});

  /// Mensagem pronta para exibir (vem do `detail` do servidor quando existe).
  final String message;

  /// Status HTTP, ou null quando nem chegou resposta (rede/timeout).
  final int? statusCode;

  /// Sem conexão, DNS, timeout...
  final bool isNetworkError;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final detail = _detail(e.response?.data);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Tempo esgotado ao falar com o servidor',
            statusCode: status, isNetworkError: true);
      case DioExceptionType.connectionError:
        return ApiException('Sem conexão com o servidor',
            statusCode: status, isNetworkError: true);
      default:
        return ApiException(detail ?? e.message ?? 'Erro de comunicação',
            statusCode: status);
    }
  }

  /// FastAPI manda `{"detail": "texto"}` ou, em erro de validação,
  /// `{"detail": [{"msg": ...}, ...]}`.
  static String? _detail(dynamic data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List) {
      final msgs = detail
          .map((d) => d is Map ? d['msg']?.toString() : d?.toString())
          .whereType<String>()
          .toList();
      if (msgs.isNotEmpty) return msgs.join('; ');
    }
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
