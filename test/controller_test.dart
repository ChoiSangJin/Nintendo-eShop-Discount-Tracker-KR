import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  test(
    'whole catalog publishes only after completion; failure preserves snapshot',
    () async {
      final store = MemoryStore();
      await store.saveGames([exampleGame(name: '이전 전체 목록')], DateTime.now());
      final repo = FakeRepository()..pending = Completer();
      final controller = GameListController(repo, store);
      final refresh = controller.refresh();
      repo.progress!(const CatalogProgress('전체 게임 가격 확인 중', 30, 100));
      expect(controller.state.busy, isTrue);
      expect(controller.state.games.single.name, '이전 전체 목록');
      expect(store.games.single.name, '이전 전체 목록');
      repo.pending!.completeError(StateError('last price batch failed'));
      await refresh;
      expect(controller.state.busy, isFalse);
      expect(controller.state.error, isNotNull);
      expect(controller.state.complete, isTrue);
      expect(store.games.single.name, '이전 전체 목록');
      repo.pending = null;
      await controller.refresh();
      expect(controller.state.error, isNull);
      expect(controller.state.games.single.name, '테스트 게임');
      controller.dispose();
    },
  );
  test(
    'only complete fresh caches skip collection; manual refresh always collects',
    () async {
      final store = MemoryStore()
        ..games = [exampleGame()]
        ..cachedAt = DateTime.now();
      final repo = FakeRepository();
      final first = GameListController(repo, store);
      await first.refresh(force: false);
      expect(repo.catalogCalls, 1); // Legacy partial cache is not a whole list.
      first.dispose();
      final restored = GameListController(repo, store);
      await restored.refresh(force: false);
      expect(repo.catalogCalls, 1);
      await restored.refresh();
      expect(repo.catalogCalls, 2);
      restored.dispose();
    },
  );
  test(
    'automatic expired-price refresh reuses only recent complete metadata',
    () async {
      final store = MemoryStore();
      await store.saveGames(
        [exampleGame()],
        DateTime.now().subtract(const Duration(minutes: 20)),
        catalogAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final repo = FakeRepository();
      final controller = GameListController(repo, store);
      await controller.refresh(force: false);
      expect(repo.metadataReuse, [true]);
      expect(
        store.catalogFetchedAt!.isBefore(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
        isTrue,
      );
      await controller.refresh();
      expect(repo.metadataReuse, [true, false]);
      controller.dispose();
    },
  );
  test(
    'global ordering puts late 30% before early 10%; all page boundaries sorted',
    () {
      final now = DateTime.now();
      final games = List.generate(
        61,
        (i) => exampleGame(
          id: '${70010000000000 + i}',
          name: '게임 $i',
          regular: 10000,
          discount: i < 30 ? 9000 : 7000,
          releaseDate: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        ),
      );
      for (final sort in [GameSort.discount, GameSort.price, GameSort.newest]) {
        final sorted = filterAndSortGames(
          games,
          genre: '전체',
          query: '',
          sort: sort,
          now: now,
        );
        expect(sorted.first.id, isNot(games.first.id));
        for (var i = 1; i < sorted.length; i++) {
          if (sort == GameSort.discount) {
            expect(
              sorted[i - 1].discountRateAt(now),
              greaterThanOrEqualTo(sorted[i].discountRateAt(now)),
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
              sorted[i - 1].releaseDate!.isBefore(sorted[i].releaseDate!),
              isFalse,
            );
          }
        }
        expect(sorted.map((g) => g.id).toSet(), hasLength(61));
        expect(sorted.skip(60).take(20), hasLength(1));
      }
      final exact = filterAndSortGames(
        [
          exampleGame(id: '1', name: 'A', regular: 10000, discount: 6999),
          exampleGame(id: '2', name: 'Z', regular: 10000, discount: 6990),
        ],
        genre: '전체',
        query: '',
        sort: GameSort.discount,
        now: now,
      );
      expect(
        exact.first.name,
        'Z',
      ); // Both display 30%, exact rates still order correctly.
    },
  );
  test(
    'series queries match localized/English names and spacing without network',
    () async {
      final repo = FakeRepository()
        ..games = [
          exampleGame(
            id: '1',
            name: '페르소나3 포터블 (Persona 3 Portable)',
            discount: null,
          ),
          exampleGame(id: '2', name: '페르소나5 더 로열 (PERSONA5 THE ROYAL)'),
          exampleGame(id: '3', name: 'Persona 3 Reload', discount: null),
          exampleGame(id: '4', name: '다른 게임'),
        ];
      final store = MemoryStore();
      final controller = GameListController(repo, store);
      await controller.refresh();
      for (final query in ['페르소나', 'Persona', '페르소나 3', 'persona3']) {
        controller.setQuery(query);
        final found = filterAndSortGames(
          controller.state.games,
          genre: '전체',
          query: query,
          sort: GameSort.discount,
          now: DateTime.now(),
        );
        expect(found, hasLength(query.contains('3') ? 2 : 3));
      }
      expect(repo.catalogCalls, 1);
      expect(store.games, hasLength(4));
      controller.dispose();
    },
  );
  test(
    'popular sort ranks whole snapshot and retains ranks on source failure',
    () async {
      final repo = FakeRepository()
        ..games = [
          exampleGame(id: '1', name: '높은 할인', discount: 1000),
          exampleGame(id: '2', name: '높은 인기', discount: 40000),
        ]
        ..popularity = {'2': 1};
      final store = MemoryStore();
      final controller = GameListController(repo, store);
      await controller.refresh();
      await controller.loadPopularity();
      expect(
        filterAndSortGames(
          controller.state.games,
          genre: '전체',
          query: '',
          sort: GameSort.popular,
          now: DateTime.now(),
        ).first.id,
        '2',
      );
      repo.failure = StateError('offline');
      await controller.loadPopularity();
      expect(controller.state.busy, isFalse);
      expect(controller.state.popularityError, isNotNull);
      expect(controller.state.games.last.popularityRank, 1);
      expect(store.games.last.popularityRank, 1);
      controller.dispose();
    },
  );
  test(
    'favorite persists through removed catalog entries and restart; failed write rolls back',
    () async {
      final store = MemoryStore();
      final repo = FakeRepository();
      final controller = GameListController(repo, store);
      await controller.refresh();
      await controller.toggleFavorite(controller.state.games.single);
      repo.games = [exampleGame(id: '70010000000002')];
      await controller.refresh();
      expect(controller.state.favorites.values.single.discountPrice, 20000);
      expect(repo.refreshed.single.id, '70010000000001');
      controller.dispose();
      final restored = GameListController(repo, store);
      await restored.refresh(force: false);
      store.failWrites = true;
      await restored.toggleFavorite(restored.state.favorites.values.single);
      expect(restored.state.favorites, hasLength(1));
      expect(restored.state.storageError, isNotNull);
      expect(restored.state.busy, isFalse);
      store.failWrites = false;
      await restored.toggleFavorite(restored.state.favorites.values.single);
      expect(store.readFavorites(), isEmpty);
      restored.dispose();
    },
  );
}
