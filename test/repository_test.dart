import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'support/fakes.dart';

void main() {
  test(
    'full-catalog search retains regular-price games and raw pagination',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final search = options.uri.path == '/kr/api/search';
            if (search) {
              expect(options.queryParameters['k'], '포켓몬');
              expect(options.queryParameters['directory'], 'software');
              expect(options.queryParameters['p'], 2);
            }
            handler.resolve(
              Response(
                requestOptions: options,
                data: search
                    ? {
                        'total': 100,
                        'items': [
                          {'nsuid': '70010000000001', 'title': '포켓몬스터'},
                          {'nsuid': '0000', 'title': '예정 게임'},
                        ],
                      }
                    : {
                        'prices': [
                          {
                            'title_id': '70010000000001',
                            'regular_price': {'raw_value': '64800'},
                          },
                        ],
                      },
              ),
            );
          },
        ),
      );
      final repo = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      final page = await repo.searchPage('포켓몬', 24);
      expect(page.nextOffset, 26);
      expect(page.total, 100);
      expect(page.games.single.name, '포켓몬스터');
      expect(page.games.single.priceAt(DateTime.now()), 64800);
      expect(page.games.single.saleActiveAt(DateTime.now()), isFalse);
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
  test(
    'retired sales API falls back to official Korean titles and real discounts',
    () async {
      final dio = Dio();
      var legacyCalls = 0;
      final catalogPages = <int>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'ec.nintendo.com') {
              legacyCalls++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 404),
                ),
              );
            } else if (options.uri.host == 'www.nintendo.com') {
              final page = options.queryParameters['spage'] as int;
              catalogPages.add(page);
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'total': 200,
                    'items': List.generate(
                      24,
                      (index) => {
                        'nsuid': '${70010000000000 + page * 100 + index}',
                        'title': '공식 한국명 $page-$index',
                        'releaseDateDownload': '2026-01-01',
                      },
                    ),
                  },
                ),
              );
            } else {
              final ids = (options.queryParameters['ids'] as String).split(',');
              expect(ids.length, lessThanOrEqualTo(30));
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'prices': ids
                        .map(
                          (id) => {
                            'title_id': id,
                            'regular_price': {'raw_value': '10000'},
                            if (id.endsWith('00'))
                              'discount_price': {'raw_value': '5000'},
                          },
                        )
                        .toList(),
                  },
                ),
              );
            }
          },
        ),
      );
      final repository = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      final first = await repository.fetchPage(0);
      expect(first.catalogFallback, isTrue);
      expect(first.nextOffset, 96);
      expect(first.games, hasLength(4));
      expect(
        first.games.every(
          (g) => g.name.startsWith('공식 한국명') && g.saleActiveAt(DateTime.now()),
        ),
        isTrue,
      );
      await repository.fetchPage(first.nextOffset);
      expect(legacyCalls, 1);
      expect(catalogPages, [1, 2, 3, 4, 5, 6, 7, 8]);
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
  test('page offsets follow raw entries, missing prices are unknown', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final sales = options.uri.host == 'ec.nintendo.com';
          if (sales) expect(options.queryParameters['offset'], 30);
          handler.resolve(
            Response(
              requestOptions: options,
              data: sales
                  ? {
                      'total': 100,
                      'contents': [
                        {'id': '70010000000001', 'formal_name': '한국 게임'},
                        {'id': 'invalid', 'formal_name': '잘못된 항목'},
                      ],
                    }
                  : {'prices': []},
            ),
          );
        },
      ),
    );
    final page = await NintendoGameRepository(
      dio,
      KoreanTitleResolver(dio, MemoryStore()),
    ).fetchPage(30);
    expect(page.games, hasLength(1));
    expect(page.nextOffset, 32);
    expect(page.total, 100);
    expect(page.games.single.priceAt(DateTime.now()), isNull);
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
