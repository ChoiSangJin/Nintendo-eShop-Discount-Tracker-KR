import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  test(
    'popularity discovers older sales without leaking them into unrelated searches',
    () async {
      final repo = FakeRepository()
        ..popularity = {'70010000000002': 1}
        ..popularGames = [
          exampleGame(id: '70010000000002', name: '인기 있는 오래된 게임'),
        ]
        ..searchPages = [
          GamePage([exampleGame(name: '포켓몬스터', discount: null)], 1, 1),
        ];
      final store = MemoryStore();
      final controller = GameListController(repo, store);
      await controller.refresh();
      controller.setPopularityEnabled(true);
      await controller.loadPopularity();
      expect(
        controller.state.games.map((g) => g.name),
        contains('인기 있는 오래된 게임'),
      );
      controller.setQuery('포켓몬');
      await controller.refresh();
      await controller.loadPopularity();
      expect(controller.state.games.single.name, '포켓몬스터');
      expect(store.games, hasLength(2));
      controller.setQuery('');
      await controller.refresh();
      expect(
        controller.state.games.map((g) => g.name),
        contains('인기 있는 오래된 게임'),
      );
      controller.dispose();
    },
  );
  test(
    'search includes full-price titles and cannot overwrite sales cache',
    () async {
      final store = MemoryStore();
      final repository = FakeRepository()
        ..searchPages = [
          GamePage([exampleGame(name: '포켓몬스터', discount: null)], 1, 1),
        ];
      final controller = GameListController(repository, store);
      await controller.refresh();
      controller.setQuery('포켓몬');
      await controller.refresh();
      expect(repository.queries, ['포켓몬']);
      expect(controller.state.games.single.discountPrice, isNull);
      expect(store.games.single.name, '테스트 게임');
      await controller.toggleFavorite(controller.state.games.single);
      controller.setQuery('');
      await controller.refresh();
      expect(controller.state.games.single.name, '테스트 게임');
      expect(controller.state.favorites, hasLength(1));
      controller.dispose();
    },
  );
  test(
    'superseded search responses never replace the latest results',
    () async {
      final repository = _DelayedSearchRepository();
      final controller = GameListController(repository, MemoryStore());
      controller.setQuery('마리오');
      final first = controller.refresh();
      controller.setQuery('포켓몬');
      final second = controller.refresh();
      repository.pending['포켓몬']!.complete(
        GamePage([exampleGame(name: '포켓몬스터')], 1, 1),
      );
      await second;
      repository.pending['마리오']!.complete(
        GamePage([exampleGame(name: '마리오')], 1, 1),
      );
      await first;
      expect(controller.state.query, '포켓몬');
      expect(controller.state.games.single.name, '포켓몬스터');
      controller.dispose();
    },
  );
  test(
    'popular sort uses confirmed rank, then discounts for unranked games',
    () async {
      final repository = FakeRepository()
        ..popularity = {'70010000000002': 2, '70010000000001': 8}
        ..pages = [
          GamePage(
            [
              exampleGame(id: '70010000000001', name: '첫번째', discount: 10000),
              exampleGame(id: '70010000000002', name: '두번째', discount: 40000),
              exampleGame(id: '70010000000003', name: '미확인', discount: 1000),
            ],
            3,
            3,
          ),
        ];
      final controller = GameListController(repository, MemoryStore());
      await controller.refresh();
      await controller.loadPopularity();
      final sorted = filterAndSortGames(
        controller.state.games,
        genre: '전체',
        query: '',
        sort: GameSort.popular,
        now: DateTime.now(),
      );
      expect(sorted.map((g) => g.name), ['두번째', '첫번째', '미확인']);
      expect(sorted.last.popularityRank, isNull);
      repository.failure = StateError('Offline');
      await controller.loadPopularity();
      expect(controller.state.popularityError, isNotNull);
      expect(controller.state.games.first.popularityRank, 8);
      controller.dispose();
    },
  );
  test(
    'favorite remains available after refresh, pagination and restart',
    () async {
      final store = MemoryStore();
      final repository = FakeRepository()
        ..pages = [
          GamePage([exampleGame(id: '70010000000001')], 2, 1),
          GamePage([exampleGame(id: '70010000000002')], 2, 2),
        ];
      final controller = GameListController(repository, store);
      await controller.refresh();
      await controller.toggleFavorite(controller.state.games.first);
      await controller.loadMore();
      expect(controller.state.games, hasLength(2));
      expect(repository.offsets, [0, 1]);
      expect(controller.state.hasMore, isFalse);
      repository.pages = [
        GamePage([exampleGame(id: '70010000000002')], 1, 1),
      ];
      await controller.refresh();
      expect(controller.state.favorites.keys, contains('70010000000001'));
      expect(repository.refreshed.single.id, '70010000000001');
      expect(controller.state.favorites.values.single.discountPrice, 20000);
      controller.dispose();
      final restored = GameListController(repository, store);
      expect(restored.state.favorites, hasLength(1));
      await restored.toggleFavorite(restored.state.favorites.values.single);
      expect(store.readFavorites(), isEmpty);
      restored.dispose();
    },
  );
  test(
    'offline failure preserves cached data and exposes retry state',
    () async {
      final store = MemoryStore()..games = [exampleGame()];
      final repository = FakeRepository()..failure = StateError('Offline');
      final controller = GameListController(repository, store);
      await controller.refresh();
      expect(controller.state.loading, isFalse);
      expect(controller.state.cached, isTrue);
      expect(controller.state.games, hasLength(1));
      expect(controller.state.error, isNotNull);
      repository.failure = null;
      await controller.refresh();
      expect(controller.state.error, isNull);
      expect(controller.state.cached, isFalse);
      controller.dispose();
    },
  );
  test('failed favorite writes never claim persistence', () async {
    final store = MemoryStore()..failWrites = true;
    final controller = GameListController(FakeRepository(), store);
    await controller.toggleFavorite(exampleGame());
    expect(controller.state.favorites, isEmpty);
    expect(controller.state.storageError, isNotNull);
    controller.dispose();
  });
  test('empty raw page cannot trigger endless pagination', () async {
    final repository = FakeRepository()..pages = [const GamePage([], 100, 0)];
    final controller = GameListController(repository, MemoryStore());
    await controller.refresh();
    expect(controller.state.hasMore, isFalse);
    await controller.loadMore();
    expect(repository.offsets, [0]);
    controller.dispose();
  });
}

class _DelayedSearchRepository extends FakeRepository {
  final pending = <String, Completer<GamePage>>{};
  @override
  Future<GamePage> searchPage(String query, int offset) {
    final completer = Completer<GamePage>();
    pending[query] = completer;
    return completer.future;
  }
}
