/// Leitura tolerante de JSON para os modelos.
///
/// O servidor monta algumas respostas a partir de fontes externas (Tidal, YT Music,
/// Last.fm), então campos podem faltar ou mudar de tipo (um id ora é número, ora
/// texto). Os helpers abaixo nunca lançam: devolvem null/padrão.
typedef Json = Map<String, dynamic>;

/// Mapa tipado a partir de qualquer coisa; vazio se não for um mapa.
Json asJson(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String? asString(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool asBool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return fallback;
}

DateTime? asDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Lista de objetos; ignora itens que não sejam mapas e devolve `[]` se não for lista.
List<T> parseList<T>(Object? v, T Function(Json json) parse) {
  if (v is! List) return const [];
  return [for (final item in v) if (item is Map) parse(asJson(item))];
}

/// Lista de textos; ignora itens nulos.
List<String> asStringList(Object? v) {
  if (v is! List) return const [];
  return [for (final item in v) if (asString(item) != null) asString(item)!];
}
