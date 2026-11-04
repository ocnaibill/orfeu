import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/models/json.dart';

void main() {
  test('asInt aceita número, texto e ignora o resto', () {
    expect(asInt(5), 5);
    expect(asInt(5.9), 5);
    expect(asInt('12'), 12);
    expect(asInt('x'), isNull);
    expect(asInt(null), isNull);
    expect(asInt([]), isNull);
  });

  test('asString normaliza ids numéricos e trata vazio como ausente', () {
    expect(asString(123), '123');
    expect(asString('abc'), 'abc');
    expect(asString(''), isNull);
    expect(asString(null), isNull);
  });

  test('asDouble, asBool e asDate', () {
    expect(asDouble(3), 3.0);
    expect(asDouble('2.5'), 2.5);
    expect(asDouble('x'), isNull);
    expect(asBool(true), isTrue);
    expect(asBool(1), isTrue);
    expect(asBool('true'), isTrue);
    expect(asBool(null), isFalse);
    expect(asBool(null, fallback: true), isTrue);
    expect(asDate('2026-01-02T03:04:05Z'), DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(asDate('lixo'), isNull);
    expect(asDate(5), isNull);
  });

  test('parseList ignora itens que não são objetos e listas ausentes', () {
    expect(parseList([{'a': 1}, 'x', null, {'a': 2}], (j) => j['a']), [1, 2]);
    expect(parseList(null, (j) => j), isEmpty);
    expect(parseList('x', (j) => j), isEmpty);
  });

  test('asJson e asStringList', () {
    expect(asJson({'a': 1}), {'a': 1});
    expect(asJson(null), isEmpty);
    expect(asJson([]), isEmpty);
    expect(asStringList(['a', 1, null, '']), ['a', '1']);
    expect(asStringList('x'), isEmpty);
  });
}
