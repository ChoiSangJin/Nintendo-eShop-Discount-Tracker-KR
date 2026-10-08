import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';

// Read-only live probe. Never use fixture or sample game data in this check.
void main() {
  test(
    'live official Korean catalog and KRW batch prices',
    () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      // The VM's default HTTP client does not honor HTTPS_PROXY automatically.
      // Route through the platform proxy; preserve the default trusted TLS setup.
      final certificate = Platform.environment['CODEX_PROXY_CERT'];
      if (certificate != null) {
        SecurityContext.defaultContext.setTrustedCertificates(certificate);
      }
      final proxy = Platform.environment['HTTPS_PROXY'];
      if (proxy != null) {
        final uri = Uri.parse(proxy);
        HttpOverrides.global = _ProxyOverrides(uri.host, uri.port);
      }
      final repository = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, _TitleStore()),
      );
      try {
        final page = await repository.fetchPage(0);
        if (page.games.isEmpty) {
          throw StateError('No live sale returned; readiness not established.');
        }
        if (!page.games.every((g) => g.saleActiveAt(DateTime.now().toUtc()))) {
          throw StateError('Returned a non-sale game');
        }
        final korean = page.games.where((g) => hasHangul(g.name)).length;
        if (korean == 0) {
          throw StateError('No official Korean game title verified.');
        }
        stdout.writeln(
          'Live KR catalog and batched KRW prices: ${page.games.length} discounted games, '
          '$korean Korean titles; next offset ${page.nextOffset}.',
        );
        for (final game in page.games.take(5)) {
          stdout.writeln(
            '${game.id} | ${game.name} | ${game.regularPrice} -> ${game.discountPrice} KRW',
          );
        }
      } finally {
        dio.close(force: true);
        HttpOverrides.global = null;
      }
    },
    skip: Platform.environment['RUN_LIVE_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.host, this.port);
  final String host;
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY $host:$port';
}

class _TitleStore implements LocalStore {
  @override
  String? readKoreanTitle(String id) => null;
  @override
  Future<void> saveKoreanTitle(String id, String title) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
