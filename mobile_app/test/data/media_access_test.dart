import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orfeu/data/api/media_access.dart';

void main() {
  const base = 'https://orfeu.test';
  String? token = 'abc';

  MediaAccess native() =>
      MediaAccess(baseUrl: base, tokenProvider: () => token, useQueryToken: false);

  setUp(() => token = 'abc');

  group('nativo (token no header)', () {
    test('monta URLs de stream e capa com o filename codificado', () {
      final media = native();
      const file = 'Artist/Álbum & Co/01 - Song?.flac';
      final stream = Uri.parse(media.streamUrl(file, quality: 'high'));
      expect(stream.origin, base);
      expect(stream.path, '/stream');
      expect(stream.queryParameters, {'filename': file, 'quality': 'high'});
      final cover = Uri.parse(media.coverUrl(file));
      expect(cover.path, '/cover');
      expect(cover.queryParameters, {'filename': file});
    });

    test('qualidade padrão é lossless', () {
      expect(Uri.parse(native().streamUrl('a.flac')).queryParameters['quality'], 'lossless');
    });

    test('nunca coloca token na URL', () {
      expect(native().streamUrl('a.flac'), isNot(contains('mt=')));
      expect(native().streamUrl('a.flac'), isNot(contains('abc')));
    });

    test('manda o Bearer só para o nosso servidor', () {
      final media = native();
      expect(media.headersFor('$base/cover?filename=x'), {'Authorization': 'Bearer abc'});
      // CDN do Tidal e qualquer outro host: nada de credencial
      expect(media.headersFor('https://resources.tidal.com/images/a/b/750x750.jpg'), isEmpty);
      expect(media.headersFor('https://orfeu.test.evil.com/cover'), isEmpty);
      expect(media.headersFor('http://orfeu.test/cover'), isEmpty, reason: 'esquema diferente');
      expect(media.headersFor('https://orfeu.test:8443/cover'), isEmpty, reason: 'porta diferente');
      expect(media.headersFor('/cover?filename=x'), isEmpty, reason: 'URL relativa');
      expect(media.headersFor('lixo'), isEmpty);
    });

    test('sem token não manda header', () {
      token = null;
      expect(native().headersFor('$base/cover'), isEmpty);
      token = '';
      expect(native().headersFor('$base/cover'), isEmpty);
    });

    test('imageProvider leva os headers certos', () {
      final own = native().imageProvider('$base/cover?filename=x');
      expect(own, isA<NetworkImage>());
      expect(own.headers, {'Authorization': 'Bearer abc'});
      expect(native().imageProvider('https://cdn.exemplo/a.jpg').headers, anyOf(isNull, isEmpty));
    });

    test('refresh não faz nada no nativo', () async {
      var calls = 0;
      final media = MediaAccess(
        baseUrl: base,
        tokenProvider: () => token,
        useQueryToken: false,
        fetchMediaToken: () async {
          calls++;
          return MediaToken('mt1', const Duration(hours: 12));
        },
      );
      await media.refresh();
      expect(calls, 0);
    });
  });

  group('web (token de mídia na query)', () {
    late DateTime clock;
    late int fetches;

    MediaAccess web() => MediaAccess(
          baseUrl: base,
          tokenProvider: () => token,
          useQueryToken: true,
          now: () => clock,
          fetchMediaToken: () async {
            fetches++;
            return MediaToken('mt$fetches', const Duration(hours: 12));
          },
        );

    setUp(() {
      clock = DateTime(2026, 1, 1, 12);
      fetches = 0;
    });

    test('não manda header e usa ?mt= depois do refresh', () async {
      final media = web();
      await media.refresh();
      final url = media.streamUrl('a.flac');
      expect(Uri.parse(url).queryParameters['mt'], 'mt1');
      expect(media.headersFor('$base/stream'), isEmpty);
      // a credencial da conta jamais aparece na URL
      expect(url, isNot(contains('abc')));
    });

    test('chamadas simultâneas fazem uma busca só', () async {
      final media = web();
      await Future.wait([media.refresh(), media.refresh(), media.refresh()]);
      expect(fetches, 1);
    });

    test('renova quando falta menos de 15 minutos', () async {
      final media = web();
      await media.refresh();
      expect(fetches, 1);

      clock = clock.add(const Duration(hours: 5));
      media.streamUrl('a.flac');
      await Future<void>.delayed(Duration.zero);
      expect(fetches, 1, reason: 'ainda longe de expirar');

      clock = clock.add(const Duration(hours: 6, minutes: 50));
      media.streamUrl('a.flac');
      await Future<void>.delayed(Duration.zero);
      expect(fetches, 2);
      expect(Uri.parse(media.streamUrl('a.flac')).queryParameters['mt'], 'mt2');
    });

    test('clear esquece o token e, sem sessão, não pede outro (logout)', () async {
      final media = web();
      await media.refresh();
      expect(Uri.parse(media.coverUrl('a.flac')).queryParameters['mt'], 'mt1');

      token = null; // o logout apaga a sessão e depois chama clear()
      media.clear();
      final url = media.coverUrl('a.flac');
      await Future<void>.delayed(Duration.zero);
      expect(Uri.parse(url).queryParameters.containsKey('mt'), isFalse);
      expect(fetches, 1, reason: 'sem sessão não deve buscar token de mídia');
    });

    test('falha ao buscar o token não derruba o app', () async {
      final media = MediaAccess(
        baseUrl: base,
        tokenProvider: () => token,
        useQueryToken: true,
        fetchMediaToken: () async => throw Exception('offline'),
      );
      await media.refresh();
      expect(Uri.parse(media.streamUrl('a.flac')).queryParameters.containsKey('mt'), isFalse);
    });
  });
}
