import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'support/fakes.dart';

void main() {
  test(
    'Hive persists wishlist, game cache and Korean titles across reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('eshop-hive-test-');
      Hive.init(dir.path);
      Future<HiveLocalStore> open() async => HiveLocalStore(
        await Hive.openBox<dynamic>('cache'),
        await Hive.openBox<dynamic>('favorites'),
        await Hive.openBox<dynamic>('titles'),
      );
      try {
        final store = await open();
        final game = exampleGame();
        await store.cache.putAll({
          'games': [game.toJson()],
          'updated_at': DateTime.utc(2026, 10, 7).toIso8601String(),
        });
        expect(store.catalogComplete, isFalse);
        expect(store.readGames(), hasLength(1));
        await store.cache.put('catalog_snapshot_v2', {
          'games': [game.toJson()],
          'updated_at': DateTime.utc(2026, 10, 8).toIso8601String(),
          'catalog_at': DateTime.utc(2026, 10, 8).toIso8601String(),
        });
        // The previous "complete" snapshot omitted placeholder/paired products.
        expect(store.catalogComplete, isFalse);
        expect(store.catalogFetchedAt, isNull);
        expect(store.readGames(), hasLength(1));
        await store.saveFavorite(game);
        await store.saveGames([game], DateTime.utc(2026, 10, 8));
        await store.saveKoreanTitle(game.id, '공식 한국어 제목');
        await Hive.close();
        final restored = await open();
        expect(restored.readFavorites().single.id, game.id);
        expect(restored.readGames().single.name, game.name);
        expect(restored.catalogComplete, isTrue);
        expect(restored.catalogFetchedAt, DateTime.utc(2026, 10, 8));
        expect(restored.cachedAt, DateTime.utc(2026, 10, 8));
        expect(restored.readKoreanTitle(game.id), '공식 한국어 제목');
        await restored.removeFavorite(game.id);
        expect(restored.readFavorites(), isEmpty);
        await restored.cache.put('catalog_snapshot_v3', {
          'games': [
            game.toJson(),
            {'id': 42},
          ],
          'updated_at': DateTime.utc(2026, 10, 8).toIso8601String(),
        });
        expect(restored.catalogComplete, isFalse);
        expect(restored.readGames(), hasLength(1));
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
