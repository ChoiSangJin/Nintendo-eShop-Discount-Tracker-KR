import 'dart:async';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/domain/models/popularity_index.dart';

GameItem exampleGame({
  String id = '70010000000001',
  String name = '테스트 게임',
  int? regular = 50000,
  int? discount = 25000,
  List<String> genres = const ['액션'],
  DateTime? releaseDate,
  DateTime? end,
  String hardware = 'Nintendo Switch',
}) => GameItem(
  id: id,
  name: name,
  originalName: name,
  genres: genres,
  regularPrice: regular,
  discountPrice: discount,
  releaseDate: releaseDate,
  discountEnd: end,
  hardware: hardware,
  priceCheckedAt: DateTime.now().toUtc(),
);

class MemoryStore implements LocalStore {
  List<GameItem> games = [];
  final Map<String, GameItem> favorites = {};
  final Map<String, String> titles = {};
  bool failWrites = false;
  @override
  bool catalogComplete = false;
  @override
  DateTime? cachedAt;
  @override
  DateTime? catalogFetchedAt;
  @override
  List<GameItem> readGames() => games;
  @override
  List<GameItem> readFavorites() => favorites.values.toList();
  @override
  Future<void> saveGames(
    List<GameItem> games,
    DateTime at, {
    DateTime? catalogAt,
  }) async {
    if (failWrites) throw StateError('Storage full');
    this.games = games;
    catalogComplete = true;
    cachedAt = at;
    catalogFetchedAt = catalogAt ?? at;
  }

  @override
  Future<void> saveFavorite(GameItem game) async {
    if (failWrites) throw StateError('Storage full');
    favorites[game.id] = game;
  }

  @override
  Future<void> removeFavorite(String id) async {
    if (failWrites) throw StateError('Storage full');
    favorites.remove(id);
  }

  @override
  String? readKoreanTitle(String id) => titles[id];
  @override
  Future<void> saveKoreanTitle(String id, String title) async {
    titles[id] = title;
  }
}

class FakeRepository implements GameRepository {
  List<GameItem> games = [exampleGame()];
  int catalogCalls = 0;
  final metadataReuse = <bool>[];
  Object? failure;
  List<GameItem> refreshed = [];
  Map<String, int> popularity = {};
  Completer<List<GameItem>>? pending;
  ProgressCallback? progress;
  @override
  Future<List<GameItem>> fetchCatalog({
    List<GameItem>? metadata,
    ProgressCallback? onProgress,
  }) async {
    catalogCalls++;
    metadataReuse.add(metadata != null);
    progress = onProgress;
    if (failure != null) throw failure!;
    return pending == null ? games : pending!.future;
  }

  @override
  Future<PopularityIndex> fetchPopularity() async {
    if (failure != null) throw failure!;
    return PopularityIndex(popularity);
  }

  @override
  Future<List<GameItem>> refreshPrices(
    List<GameItem> games, {
    ProgressCallback? onProgress,
  }) async {
    refreshed = games;
    if (failure != null) throw failure!;
    return games
        .map(
          (g) => g.withPrice({
            'regular_price': {'raw_value': '50000'},
            'discount_price': {'raw_value': '20000'},
          }, DateTime.now().toUtc()),
        )
        .toList();
  }
}
