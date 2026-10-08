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
        await store.saveFavorite(game);
        await store.saveGames([game], DateTime.utc(2026, 10, 8));
        await store.saveKoreanTitle(game.id, '공식 한국어 제목');
        await Hive.close();
        final restored = await open();
        expect(restored.readFavorites().single.id, game.id);
        expect(restored.readGames().single.name, game.name);
        expect(restored.cachedAt, DateTime.utc(2026, 10, 8));
        expect(restored.readKoreanTitle(game.id), '공식 한국어 제목');
        await restored.removeFavorite(game.id);
        expect(restored.readFavorites(), isEmpty);
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
