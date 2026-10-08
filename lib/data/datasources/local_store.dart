import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/game_item.dart';

abstract class LocalStore {
  List<GameItem> readGames();
  List<GameItem> readFavorites();
  bool get catalogComplete;
  DateTime? get cachedAt;
  DateTime? get catalogFetchedAt;
  Future<void> saveGames(
    List<GameItem> games,
    DateTime at, {
    DateTime? catalogAt,
  });
  Future<void> saveFavorite(GameItem game);
  Future<void> removeFavorite(String id);
  String? readKoreanTitle(String id);
  Future<void> saveKoreanTitle(String id, String title);
}

class HiveLocalStore implements LocalStore {
  HiveLocalStore(this.cache, this.favorites, this.titles);
  final Box<dynamic> cache;
  final Box<dynamic> favorites;
  final Box<dynamic> titles;

  static Future<HiveLocalStore> open() async {
    await Hive.initFlutter();
    return HiveLocalStore(
      await Hive.openBox<dynamic>('sales_cache_v1'),
      await Hive.openBox<dynamic>('favorites_v1'),
      await Hive.openBox<dynamic>('korean_titles_v1'),
    );
  }

  List<GameItem> _decode(Iterable<dynamic> values) {
    final games = <GameItem>[];
    for (final value in values) {
      try {
        if (value is Map) {
          games.add(GameItem.fromJson(Map<String, dynamic>.from(value)));
        }
      } on Object {
        // A damaged cache item must not prevent access to the remaining favorites.
      }
    }
    return games;
  }

  @override
  List<GameItem> readGames() {
    final snapshot = cache.get('catalog_snapshot_v2');
    final value = snapshot is Map
        ? snapshot['games']
        : cache.get('games', defaultValue: <dynamic>[]);
    return value is List ? _decode(value) : [];
  }

  @override
  List<GameItem> readFavorites() => _decode(favorites.values);
  @override
  DateTime? get cachedAt {
    final snapshot = cache.get('catalog_snapshot_v2');
    return parseDate(
      snapshot is Map ? snapshot['updated_at'] : cache.get('updated_at'),
    );
  }

  @override
  DateTime? get catalogFetchedAt {
    final snapshot = cache.get('catalog_snapshot_v2');
    return snapshot is Map ? parseDate(snapshot['catalog_at']) : null;
  }

  @override
  bool get catalogComplete {
    final snapshot = cache.get('catalog_snapshot_v2');
    if (snapshot is! Map || snapshot['games'] is! List || cachedAt == null) {
      return false;
    }
    final raw = snapshot['games'] as List;
    final decoded = _decode(raw);
    return raw.isNotEmpty &&
        decoded.length == raw.length &&
        decoded.map((g) => g.id).toSet().length == raw.length;
  }

  @override
  Future<void> saveGames(
    List<GameItem> games,
    DateTime at, {
    DateTime? catalogAt,
  }) => cache.put('catalog_snapshot_v2', {
    'games': games.map((g) => g.toJson()).toList(),
    'updated_at': at.toIso8601String(),
    'catalog_at': (catalogAt ?? at).toIso8601String(),
  });
  @override
  Future<void> saveFavorite(GameItem game) =>
      favorites.put(game.id, game.toJson());
  @override
  Future<void> removeFavorite(String id) => favorites.delete(id);
  @override
  String? readKoreanTitle(String id) {
    final value = titles.get(id);
    return value is String ? value : null;
  }

  @override
  Future<void> saveKoreanTitle(String id, String title) =>
      titles.put(id, title);
}
