import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/korean_title_resolver.dart';
import '../../data/datasources/local_store.dart';
import '../../data/repositories/game_repository.dart';
import '../../domain/models/game_item.dart';
import '../../domain/models/popularity_index.dart';

final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError(),
);
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Accept-Language': 'ko-KR,ko;q=0.9',
      },
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return NintendoGameRepository(
    dio,
    KoreanTitleResolver(dio, ref.watch(localStoreProvider)),
  );
});
final gameListProvider =
    StateNotifierProvider<GameListController, GameListState>(
      (ref) => GameListController(
        ref.watch(gameRepositoryProvider),
        ref.watch(localStoreProvider),
      ),
    );

enum GameSort {
  popular('인기순'),
  discount('높은 할인율순'),
  price('최저 가격순'),
  newest('최신 출시순');

  const GameSort(this.label);
  final String label;
}

class GameListState {
  const GameListState({
    this.games = const [],
    this.favorites = const {},
    this.total,
    this.nextOffset = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.cached = true,
    this.updatedAt,
    this.error,
    this.storageError,
    this.catalogFallback = false,
    this.query = '',
    this.loadingPopularity = false,
    this.popularityError,
  });
  final List<GameItem> games;
  final Map<String, GameItem> favorites;
  final int? total;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool cached;
  final DateTime? updatedAt;
  final String? error;
  final String? storageError;
  final bool catalogFallback;
  final String query;
  final bool loadingPopularity;
  final String? popularityError;

  GameListState copyWith({
    List<GameItem>? games,
    Map<String, GameItem>? favorites,
    int? total,
    int? nextOffset,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    bool? cached,
    DateTime? updatedAt,
    String? error,
    bool clearError = false,
    String? storageError,
    bool clearStorageError = false,
    bool? catalogFallback,
    String? query,
    bool? loadingPopularity,
    String? popularityError,
    bool clearPopularityError = false,
  }) => GameListState(
    games: games ?? this.games,
    favorites: favorites ?? this.favorites,
    total: total ?? this.total,
    nextOffset: nextOffset ?? this.nextOffset,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    cached: cached ?? this.cached,
    updatedAt: updatedAt ?? this.updatedAt,
    error: clearError ? null : error ?? this.error,
    storageError: clearStorageError ? null : storageError ?? this.storageError,
    catalogFallback: catalogFallback ?? this.catalogFallback,
    query: query ?? this.query,
    loadingPopularity: loadingPopularity ?? this.loadingPopularity,
    popularityError: clearPopularityError
        ? null
        : popularityError ?? this.popularityError,
  );
}

class GameListController extends StateNotifier<GameListState> {
  GameListController(this.repository, this.store)
    : super(
        GameListState(
          games: store.readGames(),
          favorites: {for (final game in store.readFavorites()) game.id: game},
          updatedAt: store.cachedAt,
        ),
      );
  final GameRepository repository;
  final LocalStore store;
  int _generation = 0;
  final Set<String> _favoriteWrites = {};
  Timer? _searchDebounce;
  PopularityIndex? _popularity;

  void setQuery(String value) {
    final query = value.trim();
    if (query == state.query) return;
    _searchDebounce?.cancel();
    ++_generation; // Invalidate both pending search and pagination immediately.
    state = GameListState(
      query: query,
      games: query.isEmpty ? store.readGames() : const [],
      favorites: state.favorites,
      cached: query.isEmpty,
      updatedAt: query.isEmpty ? store.cachedAt : null,
      loadingPopularity: state.loadingPopularity,
      popularityError: state.popularityError,
    );
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(refresh()),
    );
  }

  Future<GamePage> _fetch(int offset) => state.query.isEmpty
      ? repository.fetchPage(offset)
      : repository.searchPage(state.query, offset);

  List<GameItem> _ranked(List<GameItem> games) => _popularity == null
      ? games
      : games
            .map((g) => g.withPopularityRank(_popularity!.rankFor(g)))
            .toList();

  Future<void> loadPopularity() async {
    if (state.loadingPopularity) return;
    state = state.copyWith(loadingPopularity: true, clearPopularityError: true);
    try {
      _popularity = await repository.fetchPopularity();
      if (!mounted) return;
      state = state.copyWith(
        games: _ranked(state.games),
        favorites: {
          for (final g in _ranked(state.favorites.values.toList())) g.id: g,
        },
        loadingPopularity: false,
      );
      await _saveCache();
    } on Object {
      if (mounted) {
        state = state.copyWith(
          loadingPopularity: false,
          popularityError: '미국 공식 인기 목록을 불러오지 못했습니다. 저장된 순위를 우선 표시합니다.',
        );
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _message(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 403 ||
          error.response?.statusCode == 429) {
        return 'eShop이 요청을 제한했습니다. 잠시 후 다시 시도해 주세요.';
      }
      return 'eShop에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.';
    }
    return 'eShop 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> refresh() async {
    _searchDebounce?.cancel();
    final generation = ++_generation;
    state = state.copyWith(loading: true, loadingMore: false, clearError: true);
    try {
      final page = await _fetch(0);
      if (!mounted || generation != _generation) return;
      final now = DateTime.now().toUtc();
      state = state.copyWith(
        games: _ranked(
          {for (final game in page.games) game.id: game}.values.toList(),
        ),
        total: page.total,
        catalogFallback: page.catalogFallback,
        nextOffset: page.nextOffset,
        hasMore: page.nextOffset > 0 && page.nextOffset < page.total,
        loading: false,
        cached: false,
        updatedAt: now,
      );
      await _saveCache();
      unawaited(_localize(page.games, generation));
      await _refreshFavorites(page.games, generation);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        state = state.copyWith(
          loading: false,
          error: _message(error),
          cached: state.query.isEmpty,
        );
      }
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final generation = _generation;
    final offset = state.nextOffset;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _fetch(offset);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        games: _ranked(
          {
            for (final game in [...state.games, ...page.games]) game.id: game,
          }.values.toList(),
        ),
        total: page.total,
        nextOffset: page.nextOffset,
        hasMore: page.nextOffset > offset && page.nextOffset < page.total,
        loadingMore: false,
      );
      await _saveCache();
      unawaited(_localize(page.games, generation));
      await _syncFavorites(page.games);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        state = state.copyWith(loadingMore: false, error: _message(error));
      }
    }
  }

  Future<void> _saveCache() async {
    // Search results must never replace the offline discount list.
    if (state.query.isNotEmpty) return;
    try {
      await store.saveGames(
        state.games,
        state.updatedAt ?? DateTime.now().toUtc(),
      );
    } on Object {
      if (mounted) {
        state = state.copyWith(storageError: '조회 결과를 기기에 저장하지 못했습니다.');
      }
    }
  }

  Future<void> _localize(List<GameItem> games, int generation) async {
    try {
      final localized = await repository.localize(games);
      if (!mounted || generation != _generation) return;
      final names = {for (final game in localized) game.id: game.name};
      state = state.copyWith(
        games: state.games
            .map(
              (game) => names.containsKey(game.id)
                  ? game.withName(names[game.id]!)
                  : game,
            )
            .toList(),
      );
      await _saveCache();
      await _syncFavorites(
        state.games.where((g) => names.containsKey(g.id)).toList(),
      );
    } on Object {
      // Original storefront names remain usable if title enrichment fails.
    }
  }

  Future<void> _refreshFavorites(List<GameItem> page, int generation) async {
    final ids = page.map((g) => g.id).toSet();
    final absent = state.favorites.values
        .where((g) => !ids.contains(g.id))
        .toList();
    await _syncFavorites(page);
    if (absent.isEmpty) return;
    try {
      final refreshed = await repository.refreshPrices(absent);
      if (!mounted || generation != _generation) return;
      await _syncFavorites(refreshed);
    } on Object {
      if (mounted && generation == _generation) {
        state = state.copyWith(
          error: '관심 게임 일부의 가격을 갱신하지 못했습니다. 마지막 조회 가격을 표시합니다.',
        );
      }
    }
  }

  Future<void> _syncFavorites(List<GameItem> games) async {
    for (final game in games) {
      if (!mounted ||
          !state.favorites.containsKey(game.id) ||
          _favoriteWrites.contains(game.id)) {
        continue;
      }
      // Preserve a previously verified Korean title when a price refresh uses
      // original metadata or completes before title enrichment.
      final old = state.favorites[game.id]!;
      final updated = hasHangul(old.name) && !hasHangul(game.name)
          ? game.withName(old.name)
          : game;
      try {
        _favoriteWrites.add(game.id);
        await store.saveFavorite(updated);
        if (mounted && state.favorites.containsKey(game.id)) {
          state = state.copyWith(
            favorites: {...state.favorites, game.id: updated},
          );
        }
      } on Object {
        if (mounted) {
          state = state.copyWith(storageError: '관심 게임 정보를 저장하지 못했습니다.');
        }
      } finally {
        _favoriteWrites.remove(game.id);
      }
    }
  }

  Future<void> toggleFavorite(GameItem game) async {
    if (_favoriteWrites.contains(game.id)) return;
    _favoriteWrites.add(game.id);
    final remove = state.favorites.containsKey(game.id);
    try {
      if (remove) {
        await store.removeFavorite(game.id);
      } else {
        await store.saveFavorite(game);
      }
      if (!mounted) return;
      final next = {...state.favorites};
      if (remove) {
        next.remove(game.id);
      } else {
        next[game.id] = game;
      }
      state = state.copyWith(favorites: next, clearStorageError: true);
    } on Object {
      if (mounted) {
        state = state.copyWith(storageError: '찜을 저장하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      _favoriteWrites.remove(game.id);
    }
  }
}

List<GameItem> filterAndSortGames(
  Iterable<GameItem> source, {
  required String genre,
  required String query,
  required GameSort sort,
  required DateTime now,
}) {
  const aliases = {
    '액션': ['액션', 'action'],
    'RPG': ['rpg', '롤플레잉', 'role-playing'],
    '어드벤처': ['어드벤처', '어드벤쳐', 'adventure'],
    '퍼즐': ['퍼즐', 'puzzle'],
    '시뮬레이션': ['시뮬레이션', 'simulation'],
    '스포츠': ['스포츠', 'sports'],
  };
  final needle = query.trim().toLowerCase();
  final filtered = source.where((game) {
    final matchesName =
        needle.isEmpty ||
        game.name.toLowerCase().contains(needle) ||
        game.originalName.toLowerCase().contains(needle);
    final keys = aliases[genre] ?? [genre.toLowerCase()];
    final matchesGenre =
        genre == '전체' ||
        (genre == '미분류' && game.genres.isEmpty) ||
        game.genres.any(
          (g) => keys.any((key) => g.toLowerCase().contains(key)),
        );
    return matchesName && matchesGenre;
  }).toList();
  filtered.sort((a, b) {
    final result = switch (sort) {
      GameSort.popular => (a.popularityRank ?? 1 << 30).compareTo(
        b.popularityRank ?? 1 << 30,
      ),
      GameSort.discount =>
        b.discountRateAt(now).compareTo(a.discountRateAt(now)),
      GameSort.price => (a.priceAt(now) ?? 1 << 60).compareTo(
        b.priceAt(now) ?? 1 << 60,
      ),
      GameSort.newest => (b.releaseDate ?? DateTime(1970)).compareTo(
        a.releaseDate ?? DateTime(1970),
      ),
    };
    if (result != 0) return result;
    if (sort == GameSort.popular) {
      final discount = b.discountRateAt(now).compareTo(a.discountRateAt(now));
      if (discount != 0) return discount;
    }
    return a.name.compareTo(b.name);
  });
  return filtered;
}
