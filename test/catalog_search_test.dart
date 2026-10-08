import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'package:switch_sale_tracker/presentation/widgets/game_card.dart';
import 'support/fakes.dart';

void main() {
  for (final source in [null, '/kr/games/switch2/example/']) {
    testWidgets(
      'metadata-only details use official introduction or disable missing link ($source)',
      (tester) async {
        final game = GameItem.fromKoreanCatalog({
          'nsuid': 'catalog:unknown',
          'title': '공식 게임',
          'pageLinkCustom': source,
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showGameDetails(context, game, DateTime.utc(2026, 10, 8)),
                  child: const Text('상세'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('상세'));
        await tester.pumpAndSettle();
        expect(find.text('가격 확인 불가'), findsOneWidget);
        expect(find.text('스토어 정보가 확인되지 않아 가격을 표시할 수 없습니다.'), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed == null, source == null);
        expect(
          find.text(source == null ? '스토어 연결 정보 없음' : '공식 소개에서 보기'),
          findsOneWidget,
        );
        expect(find.text('한국 공식 스토어에서 보기'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'placeholder and paired records remain searchable with separate KR prices',
    () async {
      final records = [
        {
          'sys': {'id': '3eHGcNQqWT0hFf8U9Blxrz'},
          'nsuid': '0001',
          'title': '포켓몬스터스칼렛・바이올렛',
          'hardwareCategory': 'Nintendo Switch',
          'pageLinkCustom': '/kr/software/switch/sv/',
        },
        {
          'sys': {'id': '5fQdHlcRCjcj1dqn118zxs'},
          'nsuid': '70010000026251',
          'title': '포켓몬스터소드 · 실드',
        },
        {
          'sys': {'id': 'unresolved-switch2'},
          'nsuid': '000',
          'title': '포켓몬 신규 게임',
          'hardwareCategory': 'Nintendo Switch 2',
          'pageLinkCustom':
              'https://www.nintendo.com/kr/games/switch2/example/',
        },
        {
          'sys': {'id': 'direct-store-link'},
          'nsuid': '0000000008',
          'title': '진・여신전생5 Vengeance',
          'pageLinkCustom': 'https://store.nintendo.co.kr/70010000064455',
        },
        {
          'sys': {'id': 'metadata-only'},
          'nsuid': 'no-route',
          'title': '판매 종료 게임',
        },
      ];
      final dio = Dio();
      final requested = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/kr/api/software') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {'total': records.length, 'items': records},
                ),
              );
            } else {
              final ids = (options.queryParameters['ids'] as String).split(',');
              expect(ids.every(isStoreId), isTrue);
              requested.addAll(ids);
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'prices': [
                      for (final id in ids)
                        {
                          'title_id': id,
                          'regular_price': {
                            'raw_value': id == '70010000053973'
                                ? '64000'
                                : '64800',
                          },
                        },
                    ],
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
      final games = await repository.fetchCatalog();
      expect(games, hasLength(7));
      expect(requested, hasLength(5));
      final now = DateTime.utc(2026, 10, 8);
      List<GameItem> search(String query) => filterAndSortGames(
        games,
        genre: '전체',
        query: query,
        sort: GameSort.price,
        now: now,
      );
      for (final query in ['포켓몬스터', '포켓몬', 'Pokémon', 'Pokemon']) {
        expect(search(query), hasLength(5));
      }
      final scarlet = search('포켓몬스터 스칼렛').single;
      final violet = search('Pokemon Violet').single;
      expect(scarlet.id, '70010000053968');
      expect(scarlet.regularPrice, 64800);
      expect(violet.id, '70010000053973');
      expect(violet.regularPrice, 64000);
      expect(search('실드').single.id, '70010000026252');
      expect(search('Vengeance').single.id, '70010000064455');
      final unknown = search('신규 게임').single;
      expect(unknown.id, 'catalog:unresolved-switch2');
      expect(unknown.platform, GamePlatform.switch2);
      expect(unknown.priceAt(now), isNull);
      expect(unknown.storeUrl, isNull);
      expect(unknown.detailsUrl, endsWith('/kr/games/switch2/example/'));
      final restored = GameItem.fromJson(
        unknown.withName('공식 한글 제목').withPrice(null, now).toJson(),
      );
      expect(restored.detailsUrl, unknown.detailsUrl);
      expect(search('판매 종료').single.detailsUrl, isNull);
      dio.close();
    },
  );

  test(
    'shared placeholder IDs never merge unrelated metadata-only games',
    () async {
      final records = [
        {
          'sys': {'id': 'labo-1'},
          'nsuid': '0001',
          'title': '로봇 키트',
        },
        {
          'sys': {'id': 'labo-2'},
          'nsuid': '0001',
          'title': '드라이브 키트',
        },
      ];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.path, '/kr/api/software');
            handler.resolve(
              Response(
                requestOptions: options,
                data: {'items': records, 'total': records.length},
              ),
            );
          },
        ),
      );
      final repository = NintendoGameRepository(
        dio,
        KoreanTitleResolver(dio, MemoryStore()),
      );
      final games = await repository.fetchCatalog();
      expect(games.map((g) => g.id), ['catalog:labo-1', 'catalog:labo-2']);
      expect(games.every((g) => g.regularPrice == null), isTrue);
      dio.close();
    },
  );

  test(
    'store information excludes malformed links and preserves official HTTPS pages',
    () {
      for (final url in [
        'javascript:alert(1)',
        'https://user:pass@www.nintendo.com/kr/',
        'http://example.com',
        'no-route',
        'https://%',
      ]) {
        expect(catalogSourceUrl(url), isNull);
      }
      expect(
        catalogSourceUrl('/kr/switch/sv/'),
        'https://www.nintendo.com/kr/switch/sv/',
      );
    },
  );
}
