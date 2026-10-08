import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/game_item.dart';

abstract class LocalStore {
  List<GameItem> readGames();
  List<GameItem> readFavorites();
  DateTime? get cachedAt;
  Future<void> saveGames(List<GameItem> games, DateTime at);
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
    final value = cache.get('games', defaultValue: <dynamic>[]);
    return value is List ? _decode(value) : [];
  }

  @override
  List<GameItem> readFavorites() => _decode(favorites.values);
  @override
  DateTime? get cachedAt => parseDate(cache.get('updated_at'));
  @override
  Future<void> saveGames(List<GameItem> games, DateTime at) => cache.putAll({
    'games': games.map((g) => g.toJson()).toList(),
    'updated_at': at.toIso8601String(),
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
