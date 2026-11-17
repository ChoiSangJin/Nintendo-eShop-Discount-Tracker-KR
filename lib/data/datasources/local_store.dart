import 'dart:convert';
import '../services/catalog_database.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/game_item.dart';

abstract class LocalStore {
  List<GameItem> readGames();
  List<GameItem> readFavorites();
  bool get catalogComplete;
  DateTime? get cachedAt;
  DateTime? get catalogFetchedAt;
  DateTime? get catalogCheckedAt;
  bool get catalogRefreshFailed;
  Future<void> saveGames(
    List<GameItem> games,
    DateTime? at, {
    DateTime? catalogAt,
    DateTime? catalogCheckedAt,
    bool catalogRefreshFailed = false,
  });
  Future<void> saveFavorite(GameItem game);
  Future<void> removeFavorite(String id);
  String? readKoreanTitle(String id);
  Future<void> saveKoreanTitle(String id, String title);
}

abstract interface class CoordinatedStore {
  Future<bool> beginCollection();
  Future<void> endCollection();
  Future<DateTime?> get lastAutomaticAttempt;
  Future<void> recordAutomaticAttempt(DateTime at);
}

class HiveLocalStore implements LocalStore, CoordinatedStore {
  HiveLocalStore(this.cache, this.favorites, this.titles, {this.database});
  final CatalogDatabase? database;
  dynamic get _snapshot =>
      database?.snapshot ?? cache.get('catalog_snapshot_v3');
  Future<void> _writeSnapshot(Map<String, dynamic> value) => database == null
      ? cache.put('catalog_snapshot_v3', value)
      : database!.save(value);

  @override
  Future<bool> beginCollection() async =>
      await database?.acquire(DateTime.now().toUtc()) ?? true;
  @override
  Future<void> endCollection() async => database?.release();
  @override
  Future<DateTime?> get lastAutomaticAttempt async =>
      await database?.lastAttempt;
  @override
  Future<void> recordAutomaticAttempt(DateTime at) async =>
      database?.recordAttempt(at);

  Future<void> close() async {
    await cache.close();
    await favorites.close();
    await titles.close();
    await database?.close();
  }

  final Box<dynamic> cache;
  final Box<dynamic> favorites;
  final Box<dynamic> titles;

  static Future<HiveLocalStore> open({bool background = false}) async {
    // Background-only boxes never open the foreground's Hive files.
    await Hive.initFlutter(background ? 'daily_worker' : null);
    final database = await CatalogDatabase.open();
    final store = HiveLocalStore(
      await Hive.openBox<dynamic>('sales_cache_v1'),
      await Hive.openBox<dynamic>('favorites_v1'),
      await Hive.openBox<dynamic>('korean_titles_v1'),
      database: database,
    );
    if (database.snapshot == null && !background) {
      final legacy = store.cache.get('catalog_snapshot_v3');
      if (legacy is Map) await database.save(Map<String, dynamic>.from(legacy));
    }
    if (!background) await store.seedCatalog();
    return store;
  }

  /// Only the live-verified release snapshot can seed a missing/partial cache.
  /// Preserve its original timestamps and never overwrite a complete user cache.
  Future<void> seedCatalog({AssetBundle? bundle}) async {
    if (catalogComplete) return;
    try {
      final data = jsonDecode(
        await (bundle ?? rootBundle).loadString('assets/data/catalog.json'),
      );
      if (data is! Map ||
          data['version'] != 1 ||
          data['prices_verified'] != false ||
          data['games'] is! List) {
        return;
      }
      final raw = data['games'] as List;
      final games = _decode(raw);
      final catalogAt = parseDate(data['catalog_at']);
      if (catalogAt == null ||
          games.isEmpty ||
          raw.length != data['product_count'] ||
          games.length != raw.length ||
          games.map((g) => g.id).toSet().length != raw.length ||
          games.any(
            (g) =>
                g.priceCheckedAt != null ||
                g.regularPrice != null ||
                g.discountPrice != null,
          )) {
        return;
      }
      await _writeSnapshot({
        'games': raw,
        'metadata_only': true,
        'catalog_at': catalogAt.toIso8601String(),
      });
    } on Object {
      // Asset or storage failures must still allow a normal live collection.
    }
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
    final snapshot = _snapshot ?? cache.get('catalog_snapshot_v2');
    final value = snapshot is Map
        ? snapshot['games']
        : cache.get('games', defaultValue: <dynamic>[]);
    return value is List ? _decode(value) : [];
  }

  @override
  List<GameItem> readFavorites() => _decode(favorites.values);
  @override
  DateTime? get cachedAt {
    final snapshot = _snapshot ?? cache.get('catalog_snapshot_v2');
    return parseDate(
      snapshot is Map ? snapshot['updated_at'] : cache.get('updated_at'),
    );
  }

  @override
  DateTime? get catalogFetchedAt {
    final snapshot = _snapshot;
    return snapshot is Map ? parseDate(snapshot['catalog_at']) : null;
  }

  @override
  DateTime? get catalogCheckedAt {
    final snapshot = _snapshot;
    return snapshot is Map
        ? parseDate(snapshot['catalog_checked_at']) ?? catalogFetchedAt
        : null;
  }

  @override
  bool get catalogRefreshFailed {
    final snapshot = _snapshot;
    return snapshot is Map && snapshot['catalog_refresh_failed'] == true;
  }

  @override
  bool get catalogComplete {
    final snapshot = _snapshot;
    if (snapshot is! Map || snapshot['games'] is! List) {
      return false;
    }
    final raw = snapshot['games'] as List;
    final decoded = _decode(raw);
    if (cachedAt == null &&
        !(snapshot['metadata_only'] == true &&
            catalogCheckedAt != null &&
            decoded.every(
              (g) =>
                  g.priceCheckedAt == null &&
                  g.regularPrice == null &&
                  g.discountPrice == null,
            ))) {
      return false;
    }
    return raw.isNotEmpty &&
        decoded.length == raw.length &&
        decoded.map((g) => g.id).toSet().length == raw.length;
  }

  @override
  Future<void> saveGames(
    List<GameItem> games,
    DateTime? at, {
    DateTime? catalogAt,
    DateTime? catalogCheckedAt,
    bool catalogRefreshFailed = false,
  }) => _writeSnapshot({
    'games': games.map((g) => g.toJson()).toList(),
    'updated_at': at?.toIso8601String(),
    'catalog_at': (catalogAt ?? (catalogRefreshFailed ? null : at))
        ?.toIso8601String(),
    'catalog_checked_at': (catalogCheckedAt ?? catalogAt ?? at)
        ?.toIso8601String(),
    'metadata_only': at == null,
    'catalog_refresh_failed': catalogRefreshFailed,
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
