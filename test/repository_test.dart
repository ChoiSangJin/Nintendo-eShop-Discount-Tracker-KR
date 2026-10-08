import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'support/fakes.dart';

void main() {
  test(
    'complete collection recovers unstable boundaries, deduplicates IDs and bounds all requests',
    () async {
      final dio = Dio();
      var active = 0, maxActive = 0;
      final catalogCalls = <num>[];
      final priceCounts = <int>[];
      final records = List.generate(
        121,
        (i) => {
          'sys': {'id': 'record-$i'},
          'nsuid': i == 120
              ? '0000'
              : '${70010000000000 + (i == 119 ? 118 : i)}',
          'title': '공식 게임 $i',
        },
      );
      final progress = <CatalogProgress>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            active++;
            maxActive = active > maxActive ? active : maxActive;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            Map<String, dynamic> data;
            if (options.uri.path == '/kr/api/software') {
              final page = options.queryParameters['spage'] as num;
              catalogCalls.add(page);
              final offset = ((page - 1) * 24).round();
              final items = records.skip(offset).take(24).toList();
              if (page == 2 && options.queryParameters['sfsort'] != 'adate') {
                items[0] = records[0];
              }
              data = {'items': items, 'total': records.length};
            } else {
              expect(options.queryParameters['country'], 'KR');
              expect(options.queryParameters['lang'], 'ko');
              final ids = (options.queryParameters['ids'] as String).split(',');
              priceCounts.add(ids.length);
              data = {
                'prices': ids
                    .skip(1)
                    .map(
                      (id) => {
                        'title_id': id,
                        'regular_price': {'raw_value': '10000'},
                        'discount_price': {'raw_value': '7000'},
                      },
                    )
                    .toList(),
              };
            }
            active--;
            handler.resolve(Response(requestOptions: options, data: data));
          },
        ),
      );
      final repo = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      final games = await repo.fetchCatalog(onProgress: progress.add);
      expect(games, hasLength(119));
      expect(games.any((g) => g.name == '공식 게임 24'), isTrue);
      expect(games.map((g) => g.id).toSet(), hasLength(119));
      expect(games.any((g) => g.priceAt(DateTime.now()) == null), isTrue);
      expect(catalogCalls, containsAll([1, 2, 3, 4, 5, 6]));
      expect(priceCounts, [30, 30, 30, 29]);
      expect(maxActive, 4);
      expect(
        progress.where((p) => p.label == '전체 게임 목록 확인 중').last.completed,
        121,
      );
      expect(progress.last.completed, 119);
      dio.close();
    },
  );
  test(
    'truncated catalog or final price failure rejects whole collection',
    () async {
      for (final truncated in [true, false]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.uri.path == '/kr/api/software') {
                final page = options.queryParameters['spage'] as num;
                handler.resolve(
                  Response(
                    requestOptions: options,
                    data: {
                      'total': 25,
                      'items': page == 1
                          ? List.generate(
                              24,
                              (i) => {
                                'sys': {'id': 'r$i'},
                                'nsuid': '${70010000000000 + i}',
                                'title': '게임 $i',
                              },
                            )
                          : truncated
                          ? []
                          : [
                              {
                                'sys': {'id': 'r24'},
                                'nsuid': '70010000000024',
                                'title': '게임 24',
                              },
                            ],
                    },
                  ),
                );
              } else {
                handler.reject(DioException(requestOptions: options));
              }
            },
          ),
        );
        final repo = NintendoGameRepository(
          dio,
          KoreanTitleResolver(dio, MemoryStore()),
        );
        await expectLater(
          repo.fetchCatalog(),
          truncated ? throwsFormatException : throwsA(isA<DioException>()),
        );
        dio.close();
      }
    },
  );
  test(
    'only the official best-seller grid supplies ranks, duplicates keep first rank',
    () {
      final data = {
        'props': {
          'pageProps': {
            'page': {
              'slug': '/games/best-sellers/',
              'content': {
                'merchandisedGrid': [
                  {'nsuid': '70010000000001', 'name': '인기 게임'},
                  {'nsuid': null},
                  {'nsuid': '70010000000002', 'name': '또 다른 게임'},
                  {'nsuid': '70010000000001'},
                ],
              },
            },
          },
        },
      };
      final body =
          '<script id="__NEXT_DATA__" type="application/json">${jsonEncode(data)}</script>';
      expect(NintendoGameRepository.parsePopularity(body).byId, {
        '70010000000001': 1,
        '70010000000002': 3,
      });
      expect(
        () => NintendoGameRepository.parsePopularity(
          body.replaceAll('/games/best-sellers/', '/games/'),
        ),
        throwsFormatException,
      );
    },
  );
  test('61 price lookups use exactly 30/30/1 IDs and KR/ko', () async {
    final dio = Dio();
    final counts = <int>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.uri.host, 'api.ec.nintendo.com');
          expect(options.queryParameters['country'], 'KR');
          expect(options.queryParameters['lang'], 'ko');
          final ids = (options.queryParameters['ids'] as String).split(',');
          counts.add(ids.length);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'prices': ids
                    .map(
                      (id) => {
                        'title_id': int.parse(id),
                        'regular_price': {'raw_value': '74800'},
                        'discount_price': {'raw_value': '52360'},
                      },
                    )
                    .toList(),
              },
            ),
          );
        },
      ),
    );
    final repository = NintendoGameRepository(
      dio,
      KoreanTitleResolver(dio, MemoryStore()),
    );
    final priced = await repository.refreshPrices(
      List.generate(61, (i) => exampleGame(id: '${70010000000000 + i}')),
    );
    expect(counts, [30, 30, 1]);
    expect(priced, hasLength(61));
    expect(priced.every((g) => g.discountRateAt(DateTime.now()) == 30), isTrue);
  });
  test('official Korean title requires an exact matching NSUID canonical', () {
    const body =
        '<link rel="canonical" href="https://store.nintendo.co.kr/70010000000001">'
        '<h1 class="page-title"><span class="base">공식 한국 게임명</span></h1>';
    expect(
      KoreanTitleResolver.parseOfficialTitle(body, '70010000000001'),
      '공식 한국 게임명',
    );
    expect(
      KoreanTitleResolver.parseOfficialTitle(body, '70010000000002'),
      isNull,
    );
    expect(
      KoreanTitleResolver.parseOfficialTitle(
        body.replaceAll('store.nintendo.co.kr', 'example.com'),
        '70010000000001',
      ),
      isNull,
    );
  });
  test(
    'Korean API names and verified cached names need no storefront request',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final store = MemoryStore()..titles['70010000000001'] = '공식 한국명';
      final resolver = KoreanTitleResolver(dio, store);
      expect(
        await resolver.resolve('70010000000001', 'English Title'),
        '공식 한국명',
      );
      expect(await resolver.resolve('70010000000002', '이미 한국명'), '이미 한국명');
      expect(requests, 0);
      expect(
        await resolver.resolve('70010000000003', 'English-only Title'),
        'English-only Title',
      );
      expect(requests, 1);
    },
  );
}
