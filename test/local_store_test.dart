import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'verified bundled catalog seeds first launch without replacing a complete cache or favorites',
    () async {
      final dir = await Directory.systemTemp.createTemp('eshop-seed-test-');
      Hive.init(dir.path);
      final store = HiveLocalStore(
        await Hive.openBox<dynamic>('seed-cache'),
        await Hive.openBox<dynamic>('seed-favorites'),
        await Hive.openBox<dynamic>('seed-titles'),
      );
      try {
        final body = await rootBundle.loadString('assets/data/catalog.json');
        final seed = jsonDecode(body) as Map<String, dynamic>;
        await store.saveFavorite(exampleGame());
        await store.seedCatalog();
        expect(store.catalogComplete, isTrue);
        expect(store.readGames().length, seed['product_count']);
        expect(store.readGames().length, greaterThan(4000));
        expect(store.cachedAt, isNull);
        expect(
          store.readGames().every(
            (g) =>
                g.priceCheckedAt == null &&
                g.regularPrice == null &&
                g.discountPrice == null,
          ),
          isTrue,
        );
        expect(
          store.catalogFetchedAt,
          DateTime.parse(seed['catalog_at'] as String),
        );
        expect(store.readFavorites(), hasLength(1));
        final existingAt = DateTime.utc(2026, 1, 1);
        await store.saveGames([exampleGame(name: '기존 전체 목록')], existingAt);
        await store.seedCatalog();
        expect(store.readGames().single.name, '기존 전체 목록');
        expect(store.cachedAt, existingAt);
        await store.cache.clear();
        await store.seedCatalog(
          bundle: _SeedBundle(jsonEncode({...seed, 'product_count': 0})),
        );
        expect(store.catalogComplete, isFalse);
        expect(store.readFavorites(), hasLength(1));
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );

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

class _SeedBundle extends CachingAssetBundle {
  _SeedBundle(this.body);
  final String body;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(body)));
}
