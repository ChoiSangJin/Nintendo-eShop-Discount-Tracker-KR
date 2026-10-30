import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/domain/models/popularity_index.dart';
import 'support/fakes.dart';

void main() {
  test(
    'live latest Korean rankings expose consecutive per-platform ranks and KR store IDs',
    () async {
      final certificate = Platform.environment['CODEX_PROXY_CERT'];
      if (certificate != null) {
        SecurityContext.defaultContext.setTrustedCertificates(certificate);
      }
      final proxy = Platform.environment['HTTPS_PROXY'];
      if (proxy != null) {
        HttpOverrides.global = _ProxyOverrides(Uri.parse(proxy));
      }
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final paths = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.host, 'www.nintendo.com');
            expect(options.uri.path, startsWith('/kr/switch/ranking/'));
            paths.add(options.uri.path);
            handler.next(options);
          },
        ),
      );
      try {
        final index = await NintendoGameRepository(
          dio,
          KoreanTitleResolver(dio, MemoryStore()),
        ).fetchPopularity();
        expect(PopularityIndex.periodLabel(index.source), isNotNull);
        expect(paths, hasLength(3));
        for (final platform in [GamePlatform.switch1, GamePlatform.switch2]) {
          final entries = index.entries
              .where((e) => e.platform == platform)
              .toList();
          expect(entries, isNotEmpty);
          expect(
            entries.map((e) => e.rank).toList(),
            List.generate(entries.length, (i) => i + 1),
          );
          expect(entries.every((e) => isStoreId(e.id)), isTrue);
          stdout.writeln(
            '${platform.name}: ${entries.length} official ranks; #1 ${entries.first.title} (${entries.first.id})',
          );
        }
        stdout.writeln(
          'Live Korean rankings: ${index.source}; ${index.byId.length} distinct store products; no US or price API requests.',
        );
      } finally {
        dio.close(force: true);
        HttpOverrides.global = null;
      }
    },
    skip: Platform.environment['RUN_KR_RANKING_LIVE'] != '1',
  );
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);
  final Uri proxy;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}';
}
