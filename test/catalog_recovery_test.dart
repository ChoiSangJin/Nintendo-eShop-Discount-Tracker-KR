import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  for (final metadataOffline in [false, true]) {
    test(
      'real repository recovers prices from verified cache when metadata ${metadataOffline ? 'is unavailable' : 'omits one record'}',
      () async {
        final at = DateTime.now().toUtc().subtract(const Duration(days: 4));
        final store = MemoryStore();
        await store.saveGames([exampleGame(name: '검증한 전체 목록')], at);
        final dio = Dio();
        var catalogCalls = 0, priceCalls = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.uri.path == '/kr/api/software') {
                catalogCalls++;
                if (metadataOffline) {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      response: Response(
                        requestOptions: options,
                        statusCode: 503,
                      ),
                    ),
                  );
                } else {
                  final record = {
                    'sys': {'id': 'duplicate'},
                    'nsuid': '70010000000002',
                    'title': '불완전한 새 목록',
                  };
                  handler.resolve(
                    Response(
                      requestOptions: options,
                      data: {
                        'total': 2,
                        'items': [record, record],
                      },
                    ),
                  );
                }
              } else {
                priceCalls++;
                expect(options.uri.host, 'api.ec.nintendo.com');
                expect(options.queryParameters['ids'], '70010000000001');
                handler.resolve(
                  Response(
                    requestOptions: options,
                    data: {
                      'prices': [
                        {
                          'title_id': '70010000000001',
                          'regular_price': {'raw_value': '50000'},
                          'discount_price': {'raw_value': '20000'},
                        },
                      ],
                    },
                  ),
                );
              }
            },
          ),
        );
        final controller = GameListController(
          NintendoGameRepository(dio, KoreanTitleResolver(dio, store)),
          store,
        );
        await controller.refresh(force: false);
        expect(catalogCalls, metadataOffline ? 1 : 2);
        expect(priceCalls, 1);
        expect(controller.state.games.single.name, '검증한 전체 목록');
        expect(controller.state.games.single.discountPrice, 20000);
        expect(controller.state.error, isNull);
        expect(controller.state.catalogRefreshFailed, isTrue);
        expect(store.games.single.id, '70010000000001');
        expect(store.catalogFetchedAt, at);
        expect(store.cachedAt!.isAfter(at), isTrue);
        expect(store.catalogRefreshFailed, isTrue);
        controller.dispose();
        dio.close();
      },
    );
  }

  test(
    'price response failure is not mistaken for a metadata error or retried against the old list',
    () async {
      final store = MemoryStore();
      final at = DateTime.now().toUtc().subtract(const Duration(days: 4));
      await store.saveGames([exampleGame()], at);
      final dio = Dio();
      var priceCalls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path == '/kr/api/software') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'total': 1,
                    'items': [
                      {
                        'sys': {'id': 'valid'},
                        'nsuid': '70010000000002',
                        'title': '새 전체 목록',
                      },
                    ],
                  },
                ),
              );
            } else {
              priceCalls++;
              handler.resolve(
                Response(requestOptions: options, data: {'prices': 'invalid'}),
              );
            }
          },
        ),
      );
      final controller = GameListController(
        NintendoGameRepository(dio, KoreanTitleResolver(dio, store)),
        store,
      );
      await controller.refresh(fullCatalog: true);
      expect(priceCalls, 1);
      expect(controller.state.error, isNotNull);
      expect(controller.state.catalogRefreshFailed, isFalse);
      expect(store.games.single.id, '70010000000001');
      expect(store.catalogFetchedAt, at);
      expect(store.cachedAt, at);
      controller.dispose();
      dio.close();
    },
  );
}
