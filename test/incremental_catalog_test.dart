import 'package:dio/dio.dart' hide ProgressCallback;
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  for (final failPrices in [false, true]) {
    test(
      'partial catalog updates known IDs, adds new IDs and preserves missing games even when prices ${failPrices ? 'fail' : 'succeed'}',
      () async {
        final oldAt = DateTime.now().toUtc().subtract(const Duration(days: 4));
        final store = MemoryStore();
        await store.saveGames([
          exampleGame(id: '70010000000001', name: '이전 제목'),
          exampleGame(id: '70010000000002', name: '이번에 누락된 기존 게임'),
        ], oldAt);
        final dio = Dio();
        var priceCalls = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.uri.path == '/kr/api/software') {
                h.resolve(
                  Response(
                    requestOptions: o,
                    data: {
                      'total': 3,
                      'items': [
                        {
                          'sys': {'id': 'existing'},
                          'nsuid': '70010000000001',
                          'title': '변경된 공식 제목',
                          'publisher': '새 배급사',
                        },
                        {
                          'sys': {'id': 'new'},
                          'nsuid': '70010000000003',
                          'title': '신규 게임',
                          'releaseDate': '2027-01-01',
                        },
                        {
                          'sys': {'id': 'new'},
                          'nsuid': '70010000000003',
                          'title': '신규 게임',
                          'releaseDate': '2027-01-01',
                        },
                      ],
                    },
                  ),
                );
              } else {
                priceCalls++;
                // Metadata is durable before any price response, including first prices.
                expect(store.games.map((g) => g.id).toSet(), {
                  '70010000000001',
                  '70010000000002',
                  '70010000000003',
                });
                expect(store.games.first.name, '변경된 공식 제목');
                expect(store.games.first.regularPrice, 50000);
                expect(store.catalogFetchedAt, oldAt);
                expect(store.cachedAt, oldAt);
                expect(store.catalogRefreshFailed, isTrue);
                expect(store.catalogCheckedAt!.isAfter(oldAt), isTrue);
                if (failPrices) {
                  h.reject(DioException(requestOptions: o));
                } else {
                  final ids = (o.queryParameters['ids'] as String).split(',');
                  h.resolve(
                    Response(
                      requestOptions: o,
                      data: {
                        'prices': ids
                            .map(
                              (id) => {
                                'title_id': id,
                                'regular_price': {'raw_value': '60000'},
                                'discount_price': {'raw_value': '30000'},
                              },
                            )
                            .toList(),
                      },
                    ),
                  );
                }
              }
            },
          ),
        );
        final controller = GameListController(
          NintendoGameRepository(dio, KoreanTitleResolver(dio, store)),
          store,
        );
        await controller.refresh(force: false);
        expect(priceCalls, 1);
        expect(controller.state.games, hasLength(3));
        expect(store.games, hasLength(3));
        expect(store.games.first.name, '변경된 공식 제목');
        expect(store.games.first.publisher, '새 배급사');
        expect(store.games[1].name, '이번에 누락된 기존 게임');
        expect(store.catalogFetchedAt, oldAt);
        expect(controller.state.catalogRefreshFailed, isTrue);
        expect(controller.state.error, failPrices ? isNotNull : isNull);
        expect(store.cachedAt, failPrices ? oldAt : isNot(oldAt));
        controller.dispose();
        final restored = GameListController(FakeRepository(), store);
        expect(restored.state.games, hasLength(3));
        expect(restored.state.catalogRefreshFailed, isTrue);
        restored.dispose();
        dio.close();
      },
    );
  }
  test(
    'partial metadata with no previous catalog is persisted before first price failure',
    () async {
      final store = MemoryStore();
      final repo = _PartialRepository(store);
      final controller = GameListController(repo, store);
      await controller.refresh(fullCatalog: true);
      expect(controller.state.games.single.name, '확인된 신작');
      expect(store.games.single.name, '확인된 신작');
      expect(store.cachedAt, isNull);
      expect(store.catalogFetchedAt, isNull);
      expect(store.catalogCheckedAt, isNotNull);
      expect(store.catalogRefreshFailed, isTrue);
      expect(store.catalogComplete, isTrue);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    },
  );
}

class _PartialRepository extends FakeRepository {
  _PartialRepository(this.store);
  final MemoryStore store;
  @override
  Future<List<GameItem>> fetchCatalog({
    List<GameItem>? metadata,
    ProgressCallback? onProgress,
    MetadataCallback? onMetadata,
  }) async {
    await onMetadata!(
      CatalogUpdate([
        exampleGame(name: '확인된 신작').withPrice(null, DateTime.now()),
      ], complete: false),
    );
    expect(store.games.single.name, '확인된 신작');
    throw StateError('첫 가격 조회 실패');
  }
}
