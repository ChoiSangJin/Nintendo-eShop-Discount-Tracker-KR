import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';

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
        final games = await repository.fetchCatalog(
          onProgress: (p) {
            if (p.completed == p.total) {
              stdout.writeln('${p.label}: ${p.completed}/${p.total}');
            }
          },
        );
        final now = DateTime.now().toUtc();
        final sales = games.where((g) => g.saleActiveAt(now)).toList();
        expect(games.map((g) => g.id).toSet().length, games.length);
        expect(sales, isNotEmpty);
        final persona = filterAndSortGames(
          games,
          genre: '전체',
          query: '페르소나',
          sort: GameSort.discount,
          now: now,
        );
        expect(
          persona.any((g) => normalizeSearch(g.name).contains('페르소나3')),
          isTrue,
        );
        expect(
          persona.any((g) => normalizeSearch(g.name).contains('페르소나5')),
          isTrue,
        );
        final pokemon = filterAndSortGames(
          games,
          genre: '전체',
          query: '포켓몬',
          sort: GameSort.discount,
          now: now,
        );
        expect(
          pokemon.any((g) => g.regularPrice != null && !g.saleActiveAt(now)),
          isTrue,
        );
        for (final sort in [
          GameSort.discount,
          GameSort.price,
          GameSort.newest,
        ]) {
          final sorted = filterAndSortGames(
            sales,
            genre: '전체',
            query: '',
            sort: sort,
            now: now,
          );
          for (var i = 1; i < sorted.length; i++) {
            if (sort == GameSort.discount) {
              expect(
                compareDiscount(sorted[i - 1], sorted[i], now),
                lessThanOrEqualTo(0),
              );
            }
            if (sort == GameSort.price) {
              expect(
                sorted[i - 1].priceAt(now),
                lessThanOrEqualTo(sorted[i].priceAt(now)!),
              );
            }
            if (sort == GameSort.newest) {
              expect(
                (sorted[i - 1].releaseDate ?? DateTime(1970)).isBefore(
                  sorted[i].releaseDate ?? DateTime(1970),
                ),
                isFalse,
              );
            }
          }
        }
        final ranks = await repository.fetchPopularity();
        expect(games.any((g) => ranks.rankFor(g) != null), isTrue);
        stdout.writeln(
          'Live complete KR catalog: ${games.length} valid unique NSUIDs, ${sales.length} active discounts, ${persona.length} Persona matches, ${pokemon.length} Pokémon matches. Global discount/price/release order verified across every 20-item page.',
        );
        for (final g in persona) {
          stdout.writeln('${g.name}: ${g.priceAt(now)} KRW');
        }
      } finally {
        dio.close(force: true);
        HttpOverrides.global = null;
      }
    },
    skip: Platform.environment['RUN_LIVE_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 8)),
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
