import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'support/fakes.dart';

void main() {
  test(
    'a denied price request stops queued work and never publishes partial prices',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 403),
              ),
            );
          },
        ),
      );
      final repo = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      await expectLater(
        repo.refreshPrices(
          List.generate(300, (i) => exampleGame(id: '${70010000000000 + i}')),
        ),
        throwsA(isA<DioException>()),
      );
      expect(requests, 1);
      dio.close();
    },
  );

  test(
    'price workers fill free slots without waiting for a slow batch',
    () async {
      final dio = Dio();
      RequestInterceptorHandler? slow;
      RequestOptions? slowOptions;
      final fifth = Completer<void>();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            if (requests == 1) {
              slow = handler;
              slowOptions = options;
              return;
            }
            if (requests == 5) fifth.complete();
            handler.resolve(
              Response(requestOptions: options, data: {'prices': []}),
            );
          },
        ),
      );
      final repo = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      final result = repo.refreshPrices(
        List.generate(150, (i) => exampleGame(id: '${70010000000000 + i}')),
      );
      try {
        await fifth.future.timeout(const Duration(seconds: 2));
        expect(requests, 5);
      } finally {
        slow?.resolve(
          Response(requestOptions: slowOptions!, data: {'prices': []}),
        );
      }
      expect(await result, hasLength(150));
      dio.close();
    },
  );

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
      expect(games, hasLength(120));
      expect(games.any((g) => g.name == '공식 게임 24'), isTrue);
      expect(games.map((g) => g.id).toSet(), hasLength(120));
      expect(games.any((g) => g.priceAt(DateTime.now()) == null), isTrue);
      expect(catalogCalls, containsAll([1, 2, 3, 4, 5, 6]));
      expect(catalogCalls, contains(1.5));
      // Only the damaged boundary is repaired instead of a full reverse scan.
      expect(catalogCalls.length, lessThan(12));
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
    'Korean ranking parser validates period, platform, consecutive ranks and official store IDs',
    () {
      const url =
          'https://www.nintendo.com/kr/switch/ranking/ranking_2027_full.html';
      const body =
          '<div id="featureListRanking">'
          '<div id="featureListRanking__headlineTextArea">Nintendo Switch 2027년 연간 다운로드 랭킹 ※유료 소프트웨어 대상으로 집계</div>'
          '<div data-rank="1"><a href="https://store.nintendo.co.kr/70010000000001"><p class="tit">첫 게임</p></a></div>'
          '<div data-rank="2"><a href="https://store.nintendo.co.kr/70010000000002"><p class="tit">다음 게임</p></a></div></div>';
      final index = NintendoGameRepository.parsePopularity(
        body,
        sourceUrl: Uri.parse(url),
      );
      expect(index.source, 'kr:2027:full');
      expect(index.byId, {'70010000000001': 1, '70010000000002': 2});
      for (final changed in [
        body.replaceAll('2027년', '2026년'),
        body.replaceAll('data-rank="2"', 'data-rank="3"'),
        body.replaceAll('store.nintendo.co.kr', 'example.com'),
        body.replaceAll('70010000000002', '70010000000001'),
      ]) {
        expect(
          () => NintendoGameRepository.parsePopularity(
            changed,
            sourceUrl: Uri.parse(url),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => NintendoGameRepository.parsePopularity(
          body,
          sourceUrl: Uri.parse(
            url.replaceAll('_full.html', '_full_switch2.html'),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('latest period and Switch 2 link are discovered from official pages', () async {
    final dio = Dio();
    final paths = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.uri.path);
          final switch2 = options.uri.path.endsWith('_switch2.html');
          handler.resolve(
            Response(
              requestOptions: options,
              data: options.uri.path.endsWith('/ranking/')
                  ? "<script>window.location.href = 'ranking_2028_1st.html';</script>"
                  : '<div id="featureListRanking">'
                        '<div id="featureListRanking__tabSwitcherArea"><a href="ranking_2028_1st_switch2.html">Switch 2</a></div>'
                        '<div id="featureListRanking__headlineTextArea">Nintendo Switch${switch2 ? ' 2' : ''} 2028년 상반기 다운로드 랭킹 ※유료</div>'
                        '<div data-rank="1"><a href="https://store.nintendo.co.kr/${switch2 ? '70010000000002' : '70010000000001'}"><p class="tit">게임</p></a></div></div>',
            ),
          );
        },
      ),
    );
    final index = await NintendoGameRepository(
      dio,
      KoreanTitleResolver(dio, MemoryStore()),
    ).fetchPopularity();
    expect(index.source, 'kr:2028:1st');
    expect(index.byId, {'70010000000001': 1, '70010000000002': 1});
    expect(paths, [
      '/kr/switch/ranking/',
      '/kr/switch/ranking/ranking_2028_1st.html',
      '/kr/switch/ranking/ranking_2028_1st_switch2.html',
    ]);
    expect(
      () => NintendoGameRepository.rankingUrl(
        'https://example.com/ranking_2028_1st.html',
        Uri.parse('https://www.nintendo.com/kr/switch/ranking/'),
      ),
      throwsFormatException,
    );
    dio.close();
  });
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
