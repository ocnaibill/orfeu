import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/api_client.dart';
import 'package:orfeu/data/api/token_store.dart';
import 'package:orfeu/data/core_providers.dart';

import 'fake_adapter.dart';

void main() {
  late MemoryTokenStore store;
  late FakeAdapter adapter;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      // Mesma ligação do app (token do authProvider, 401 -> logout), só com HTTP falso.
      apiClientProvider.overrideWith((ref) => ApiClient(
            baseUrl: 'https://orfeu.test',
            tokenProvider: () => ref.read(authProvider).token,
            onUnauthorized: () => ref.read(authProvider.notifier).logout(),
            dio: dioWith(adapter),
          )),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ResponseBody handler(options) {
    switch (options.path) {
      case '/token':
        final f = options.data as Map;
        if (f['password'] == 'certa') {
          return jsonBody({'access_token': 'JWT-${f['username']}', 'token_type': 'bearer'});
        }
        return jsonBody({'detail': 'Usuário ou senha incorretos'}, status: 401);
      case '/auth/register':
        return jsonBody({'access_token': 'ignorado', 'token_type': 'bearer'});
      case '/users/me':
        return jsonBody({'detail': 'Token inválido'}, status: 401);
      default:
        return jsonBody({});
    }
  }

  setUp(() {
    store = MemoryTokenStore();
    adapter = FakeAdapter(handler);
  });

  test('sem sessão guardada: fica deslogado e para de carregar', () async {
    final c = makeContainer();
    c.read(authProvider);
    await settle();
    final s = c.read(authProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.isLoading, isFalse);
  });

  test('restaura a sessão guardada', () async {
    await store.save(token: 'T0', username: 'bia');
    final c = makeContainer();
    c.read(authProvider);
    await settle();
    final s = c.read(authProvider);
    expect(s.isAuthenticated, isTrue);
    expect(s.token, 'T0');
    expect(s.username, 'bia');
  });

  test('login guarda token e usuário', () async {
    final c = makeContainer();
    expect(await c.read(authProvider.notifier).login('bia', 'certa'), isTrue);
    final s = c.read(authProvider);
    expect(s.isAuthenticated, isTrue);
    expect(s.token, 'JWT-bia');
    expect(await store.readToken(), 'JWT-bia');
    expect(await store.readUsername(), 'bia');
    // o login em si não leva Authorization
    expect(adapter.requests.firstWhere((r) => r.path == '/token').headers.containsKey('Authorization'), isFalse);
  });

  test('senha errada mostra o erro do servidor e não desloga nem guarda nada', () async {
    final c = makeContainer();
    expect(await c.read(authProvider.notifier).login('bia', 'errada'), isFalse);
    final s = c.read(authProvider);
    expect(s.isAuthenticated, isFalse);
    expect(s.isLoading, isFalse);
    expect(s.error, 'Usuário ou senha incorretos');
    expect(await store.readToken(), isNull);
  });

  test('o erro some na tentativa seguinte', () async {
    final c = makeContainer();
    final auth = c.read(authProvider.notifier);
    await auth.login('bia', 'errada');
    expect(c.read(authProvider).error, isNotNull);
    await auth.login('bia', 'certa');
    expect(c.read(authProvider).error, isNull);
  });

  test('cadastro cria a conta e já entra', () async {
    final c = makeContainer();
    expect(await c.read(authProvider.notifier).register('bia', 'b@x.dev', 'certa', 'Bia'), isTrue);
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), ['POST /auth/register', 'POST /token']);
    expect(adapter.requests.first.data, {
      'username': 'bia', 'email': 'b@x.dev', 'password': 'certa', 'full_name': 'Bia',
    });
    expect(c.read(authProvider).isAuthenticated, isTrue);
  });

  test('401 numa chamada autenticada encerra a sessão', () async {
    final c = makeContainer();
    await c.read(authProvider.notifier).login('bia', 'certa');
    expect(c.read(authProvider).isAuthenticated, isTrue);

    await expectLater(c.read(apiClientProvider).getJson('/users/me'), throwsA(anything));
    await settle();

    expect(c.read(authProvider).isAuthenticated, isFalse);
    expect(await store.readToken(), isNull);
  });

  test('logout limpa o armazenamento', () async {
    final c = makeContainer();
    await c.read(authProvider.notifier).login('bia', 'certa');
    await c.read(authProvider.notifier).logout();
    expect(c.read(authProvider).isAuthenticated, isFalse);
    expect(await store.readToken(), isNull);
    expect(await store.readUsername(), isNull);
  });
}
