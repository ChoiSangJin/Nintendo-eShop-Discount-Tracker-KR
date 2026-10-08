import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
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
