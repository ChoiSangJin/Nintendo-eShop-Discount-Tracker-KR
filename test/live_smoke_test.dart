import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';

// Read-only live probe. Never use fixture or sample game data in this check.
void main() {
  test(
    Platform.environment['LIVE_CATALOG_OUTPUT'] == null
        ? 'live official Korean catalog and KRW batch prices'
        : 'live verified Korean metadata snapshot without bundled prices',
    () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      var catalogRequests = 0;
      var priceRequests = 0;
      final elapsed = Stopwatch()..start();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/kr/api/software') catalogRequests++;
            if (options.uri.path == '/v1/price') priceRequests++;
            handler.next(options);
          },
          onError: (error, handler) {
            stdout.writeln(
              'Official API failed: ${error.requestOptions.uri} (HTTP ${error.response?.statusCode})',
            );
            handler.next(error);
          },
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
      final snapshotPath = Platform.environment['LIVE_CATALOG_OUTPUT'];
      try {
        void progress(CatalogProgress p) {
          if (p.completed == p.total) {
            stdout.writeln('${p.label}: ${p.completed}/${p.total}');
          }
        }

        final games = snapshotPath == null
            ? await repository.fetchCatalog(onProgress: progress)
            : await repository.fetchMetadata(onProgress: progress);
        final now = DateTime.now().toUtc();
        final upcoming = games.where((g) => g.upcomingAt(now)).toList();
        expect(upcoming, isNotEmpty);
        expect(games.any((g) => g.supportsKorean), isTrue);
        expect(games.any((g) => g.publisher?.isNotEmpty == true), isTrue);
        stdout.writeln(
          'Official collection: ${elapsed.elapsed.inMilliseconds} ms; $catalogRequests catalog requests, $priceRequests price requests; ${upcoming.length} upcoming games.',
        );
        final sales = games.where((g) => g.saleActiveAt(now)).toList();
        expect(games.map((g) => g.id).toSet().length, games.length);
        if (snapshotPath == null) expect(sales, isNotEmpty);
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
          query: '포켓몬스터',
          sort: GameSort.discount,
          now: now,
        );
        if (snapshotPath == null) {
          expect(
            pokemon.any((g) => g.regularPrice != null && !g.saleActiveAt(now)),
            isTrue,
          );
        }
        final verifiedIds = {
          '70010000053968',
          '70010000053973',
          '70010000039952',
          '70010000039957',
          '70010000026251',
          '70010000026252',
          '70010000015693',
          '70010000015694',
        };
        expect(pokemon.map((g) => g.id), containsAll(verifiedIds));
        for (final game in pokemon.where((g) => verifiedIds.contains(g.id))) {
          if (snapshotPath == null) expect(game.regularPrice, isNotNull);
          expect(game.storeUrl, isNotNull);
          stdout.writeln('${game.name}: ${game.priceAt(now)} KRW (${game.id})');
        }
        final metadataOnly = games.where((g) => !isStoreId(g.id)).toList();
        expect(metadataOnly, isNotEmpty);
        expect(
          metadataOnly.every(
            (g) => g.priceAt(now) == null && g.storeUrl == null,
          ),
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
          'Live complete KR catalog: ${games.length} unique products, ${metadataOnly.length} metadata-only records, ${snapshotPath == null ? '${sales.length} active discounts' : 'prices not bundled'}, ${persona.length} Persona matches, ${pokemon.length} Pokémon matches. ${snapshotPath == null ? 'Global sorting verified.' : 'Metadata coverage verified; prices require a separate live lookup.'}',
        );
        if (snapshotPath != null) {
          expect(priceRequests, 0);
          expect(
            games.every(
              (g) =>
                  g.regularPrice == null &&
                  g.discountPrice == null &&
                  g.priceCheckedAt == null,
            ),
            isTrue,
          );
          await File(snapshotPath).writeAsString(
            jsonEncode({
              'version': 1,
              'product_count': games.length,
              'catalog_at': now.toIso8601String(),
              'prices_verified': false,
              'games': games.map((g) => g.toJson()).toList(),
            }),
          );
        }
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
