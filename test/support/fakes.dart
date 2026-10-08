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
}) => GameItem(
  id: id,
  name: name,
  originalName: name,
  genres: genres,
  regularPrice: regular,
  discountPrice: discount,
  releaseDate: releaseDate,
  discountEnd: end,
  priceCheckedAt: DateTime.now().toUtc(),
);

class MemoryStore implements LocalStore {
  List<GameItem> games = [];
  final Map<String, GameItem> favorites = {};
  final Map<String, String> titles = {};
  bool failWrites = false;
  @override
  DateTime? cachedAt;
  @override
  List<GameItem> readGames() => games;
  @override
  List<GameItem> readFavorites() => favorites.values.toList();
  @override
  Future<void> saveGames(List<GameItem> games, DateTime at) async {
    if (failWrites) throw StateError('Storage full');
    this.games = games;
    cachedAt = at;
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
  List<GamePage> pages = [
    GamePage([exampleGame()], 1, 1),
  ];
  final List<int> offsets = [];
  Object? failure;
  List<GameItem> refreshed = [];
  List<GamePage> searchPages = [];
  final List<String> queries = [];
  Map<String, int> popularity = {};
  @override
  Future<GamePage> searchPage(String query, int offset) async {
    queries.add(query);
    if (failure != null) throw failure!;
    return searchPages.firstWhere(
      (page) => page.nextOffset > offset,
      orElse: () => const GamePage([], 0, 0),
    );
  }

  @override
  Future<PopularityIndex> fetchPopularity() async {
    if (failure != null) throw failure!;
    return PopularityIndex(popularity);
  }

  @override
  Future<GamePage> fetchPage(int offset) async {
    offsets.add(offset);
    if (failure != null) throw failure!;
    return pages.firstWhere(
      (page) => page.nextOffset > offset,
      orElse: () => const GamePage([], 0, 0),
    );
  }

  @override
  Future<List<GameItem>> refreshPrices(List<GameItem> games) async {
    refreshed = games;
    return games
        .map(
          (g) => g.withPrice({
            'regular_price': {'raw_value': '50000'},
            'discount_price': {'raw_value': '20000'},
          }, DateTime.now().toUtc()),
        )
        .toList();
  }

  @override
  Future<List<GameItem>> localize(List<GameItem> games) async => games;
}
