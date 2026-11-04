import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/api_exception.dart';

import 'fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  String? token;
  var unauthorizedCalls = 0;

  ApiClient makeClient() => ApiClient(
        baseUrl: 'https://orfeu.test',
        tokenProvider: () => token,
        onUnauthorized: () => unauthorizedCalls++,
        dio: dioWith(adapter),
      );

  setUp(() {
    token = 'abc';
    unauthorizedCalls = 0;
    adapter = FakeAdapter((_) => jsonBody({'ok': true}));
  });

  test('envia o Bearer e decodifica o JSON', () async {
    adapter = FakeAdapter((_) => jsonBody({'username': 'bia'}));
    final data = await makeClient().getJson('/users/me');
    expect(data, {'username': 'bia'});
    final req = adapter.requests.single;
    expect(req.uri.toString(), 'https://orfeu.test/users/me');
    expect(req.headers['Authorization'], 'Bearer abc');
  });

  test('lê o token na hora da chamada, sem recriar o cliente', () async {
    final client = makeClient();
    await client.getJson('/a');
    token = 'novo';
    await client.getJson('/b');
    token = null;
    await client.getJson('/c');
    expect(adapter.requests.map((r) => r.headers['Authorization']),
        ['Bearer abc', 'Bearer novo', null]);
  });

  test('authenticated:false não manda o token', () async {
    await makeClient().getJson('/public', authenticated: false);
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('401 numa chamada autenticada avisa onUnauthorized', () async {
    adapter = FakeAdapter((_) => jsonBody({'detail': 'Token inválido'}, status: 401));
    await expectLater(
        makeClient().getJson('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', true)
            .having((e) => e.message, 'message', 'Token inválido')));
    expect(unauthorizedCalls, 1);
  });

  test('401 de senha errada no login NÃO desloga', () async {
    adapter = FakeAdapter(
        (_) => jsonBody({'detail': 'Usuário ou senha incorretos'}, status: 401));
    await expectLater(
        makeClient().postForm('/token', {'username': 'a', 'password': 'b'}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Usuário ou senha incorretos')));
    expect(unauthorizedCalls, 0);
  });

  test('postForm manda urlencoded', () async {
    await makeClient().postForm('/token', {'username': 'a b', 'password': 'p&q'});
    final req = adapter.requests.single;
    expect(req.contentType, Headers.formUrlEncodedContentType);
    expect(req.data, {'username': 'a b', 'password': 'p&q'});
  });

  test('postJson, putJson, patchJson e deleteJson usam o método certo', () async {
    final client = makeClient();
    await client.postJson('/x', body: {'a': 1});
    await client.putJson('/x', body: {'a': 1});
    await client.patchJson('/x');
    await client.deleteJson('/x');
    expect(adapter.requests.map((r) => r.method), ['POST', 'PUT', 'PATCH', 'DELETE']);
  });

  test('erro de validação do FastAPI vira uma mensagem só', () async {
    adapter = FakeAdapter((_) => jsonBody({
          'detail': [
            {'msg': 'campo obrigatório'},
            {'msg': 'e-mail inválido'},
          ]
        }, status: 422));
    await expectLater(
        makeClient().postJson('/auth/register', body: {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'campo obrigatório; e-mail inválido')
            .having((e) => e.statusCode, 'status', 422)));
  });

  test('sem conexão vira ApiException de rede', () async {
    adapter = FakeAdapter((o) => throw DioException(
        requestOptions: o, type: DioExceptionType.connectionError));
    await expectLater(makeClient().getJson('/x'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'rede', true)));
    adapter = FakeAdapter((o) => throw DioException(
        requestOptions: o, type: DioExceptionType.receiveTimeout));
    await expectLater(makeClient().getJson('/x'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'rede', true)));
  });

  test('404 sem detail usa mensagem genérica', () async {
    adapter = FakeAdapter((_) => jsonBody('x', status: 404));
    await expectLater(makeClient().getJson('/nada'),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, '404', true)));
  });
}
