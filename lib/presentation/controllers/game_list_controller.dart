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
    this.loading = true,
    this.cached = true,
    this.complete = false,
    this.updatedAt,
    this.error,
    this.storageError,
    this.query = '',
    this.loadingPopularity = false,
    this.popularityError,
    this.progress,
    this.savingFavorite = false,
  });
  final List<GameItem> games;
  final Map<String, GameItem> favorites;
  final bool loading, cached, complete, loadingPopularity, savingFavorite;
  final DateTime? updatedAt;
  final String? error, storageError, popularityError;
  final String query;
  final CatalogProgress? progress;
  bool get busy => loading || loadingPopularity || savingFavorite;
  GameListState copyWith({
    List<GameItem>? games,
    Map<String, GameItem>? favorites,
    bool? loading,
    bool? cached,
    bool? complete,
    DateTime? updatedAt,
    String? error,
    bool clearError = false,
    String? storageError,
    bool clearStorageError = false,
    String? query,
    bool? loadingPopularity,
    String? popularityError,
    bool clearPopularityError = false,
    CatalogProgress? progress,
    bool? savingFavorite,
  }) => GameListState(
    games: games ?? this.games,
    favorites: favorites ?? this.favorites,
    loading: loading ?? this.loading,
    cached: cached ?? this.cached,
    complete: complete ?? this.complete,
    updatedAt: updatedAt ?? this.updatedAt,
    error: clearError ? null : error ?? this.error,
    storageError: clearStorageError ? null : storageError ?? this.storageError,
    query: query ?? this.query,
    loadingPopularity: loadingPopularity ?? this.loadingPopularity,
    popularityError: clearPopularityError
        ? null
        : popularityError ?? this.popularityError,
    progress: progress ?? this.progress,
    savingFavorite: savingFavorite ?? this.savingFavorite,
  );
}

class GameListController extends StateNotifier<GameListState> {
  GameListController(this.repository, this.store)
    : super(
        GameListState(
          games: store.readGames(),
          complete: store.catalogComplete,
          favorites: {for (final g in store.readFavorites()) g.id: g},
          updatedAt: store.cachedAt,
        ),
      );
  final GameRepository repository;
  final LocalStore store;
  static const cacheLifetime = Duration(minutes: 15);
  final Set<String> _favoriteWrites = {};
  PopularityIndex? _popularity;
  bool _refreshing = false;
  DateTime? _catalogAt;
  void setQuery(String value) => state = state.copyWith(query: value.trim());
  List<GameItem> _ranked(List<GameItem> games) => _popularity == null
      ? games
      : games
            .map((g) => g.withPopularityRank(_popularity!.rankFor(g)))
            .toList();

  Future<void> loadPopularity() async {
    if (state.busy) return;
    state = state.copyWith(loadingPopularity: true, clearPopularityError: true);
    try {
      _popularity = await repository.fetchPopularity();
      if (!mounted) return;
      state = state.copyWith(
        games: _ranked(state.games),
        favorites: {
          for (final g in _ranked(state.favorites.values.toList())) g.id: g,
        },
      );
      await _saveCache();
    } on Object {
      if (mounted) {
        state = state.copyWith(
          popularityError: '미국 공식 인기 목록을 불러오지 못했습니다. 저장된 순위를 우선 표시합니다.',
        );
      }
    } finally {
      if (mounted) state = state.copyWith(loadingPopularity: false);
    }
  }

  Future<void> refresh({bool force = true}) async {
    if (_refreshing || state.loadingPopularity || state.savingFavorite) return;
    final now = DateTime.now().toUtc();
    if (!force &&
        state.complete &&
        state.updatedAt != null &&
        now.difference(state.updatedAt!) >= Duration.zero &&
        now.difference(state.updatedAt!) < cacheLifetime) {
      state = state.copyWith(loading: false);
      return;
    }
    _refreshing = true;
    state = state.copyWith(
      loading: true,
      clearError: true,
      progress: const CatalogProgress('전체 게임 목록 확인 중', 0, 0),
    );
    try {
      final catalogAt = _catalogAt ?? store.catalogFetchedAt;
      final reuseMetadata =
          !force &&
          state.complete &&
          catalogAt != null &&
          now.difference(catalogAt) >= Duration.zero &&
          now.difference(catalogAt) < const Duration(hours: 24);
      final games = await repository.fetchCatalog(
        metadata: reuseMetadata ? state.games : null,
        onProgress: (progress) {
          if (mounted) state = state.copyWith(progress: progress);
        },
      );
      if (!mounted) return;
      if (games.isEmpty) throw const FormatException('전체 목록이 비어 있습니다.');
      _catalogAt = reuseMetadata ? catalogAt : DateTime.now().toUtc();
      final previousRanks = {
        for (final g in state.games) g.id: g.popularityRank,
      };
      final ranked = _popularity == null
          ? games.map((g) => g.withPopularityRank(previousRanks[g.id])).toList()
          : _ranked(games);
      state = state.copyWith(
        games: ranked,
        complete: true,
        cached: false,
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveCache();
      await _syncFavorites(ranked);
      if (!mounted) return;
      final ids = ranked.map((g) => g.id).toSet();
      final absent = state.favorites.values
          .where((g) => !ids.contains(g.id))
          .toList();
      if (absent.isNotEmpty) {
        try {
          await _syncFavorites(await repository.refreshPrices(absent));
        } on Object {
          if (mounted) {
            state = state.copyWith(
              error: '관심 게임 일부의 가격을 갱신하지 못했습니다. 마지막 조회 가격을 표시합니다.',
            );
          }
        }
      }
    } on Object catch (error) {
      if (mounted) {
        state = state.copyWith(
          cached: true,
          error: error is FormatException
              ? error.message
              : '전체 게임 정보를 불러오지 못했습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.',
        );
      }
    } finally {
      _refreshing = false;
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  Future<void> _saveCache() async {
    if (!state.complete || state.updatedAt == null) return;
    try {
      await store.saveGames(
        state.games,
        state.updatedAt!,
        catalogAt: _catalogAt ?? store.catalogFetchedAt,
      );
    } on Object {
      if (mounted) {
        state = state.copyWith(storageError: '조회 결과를 기기에 저장하지 못했습니다.');
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
    if (state.busy || _favoriteWrites.contains(game.id)) return;
    state = state.copyWith(savingFavorite: true);
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
      if (mounted) state = state.copyWith(savingFavorite: false);
    }
  }
}

List<GameItem> filterAndSortGames(
  Iterable<GameItem> source, {
  required String genre,
  required String query,
  required GameSort sort,
  required DateTime now,
  int? discountBand,
  GamePlatform? platform,
}) {
  assert(
    discountBand == null ||
        (discountBand >= 0 && discountBand <= 100 && discountBand % 10 == 0),
  );
  const aliases = {
    '액션': ['액션', 'action'],
    'RPG': ['rpg', '롤플레잉', 'role-playing'],
    '어드벤처': ['어드벤처', '어드벤쳐', 'adventure'],
    '퍼즐': ['퍼즐', 'puzzle'],
    '시뮬레이션': ['시뮬레이션', 'simulation'],
    '스포츠': ['스포츠', 'sports'],
  };
  final needle = normalizeSearch(query);
  final filtered = source.where((game) {
    final matchesName =
        needle.isEmpty ||
        normalizeSearch(game.name).contains(needle) ||
        normalizeSearch(game.originalName).contains(needle);
    final keys = aliases[genre] ?? [genre.toLowerCase()];
    final matchesGenre =
        genre == '전체' ||
        (genre == '미분류' && game.genres.isEmpty) ||
        game.genres.any(
          (g) => keys.any((key) => g.toLowerCase().contains(key)),
        );
    final matchesPlatform = platform == null || game.platform == platform;
    final matchesDiscount =
        discountBand == null ||
        (game.saleActiveAt(now) &&
            game.discountRateAt(now) ~/ 10 * 10 == discountBand);
    return matchesName && matchesGenre && matchesPlatform && matchesDiscount;
  }).toList();
  filtered.sort((a, b) {
    final result = switch (sort) {
      GameSort.popular => (a.popularityRank ?? 1 << 30).compareTo(
        b.popularityRank ?? 1 << 30,
      ),
      GameSort.discount => compareDiscount(a, b, now),
      GameSort.price => (a.priceAt(now) ?? 1 << 60).compareTo(
        b.priceAt(now) ?? 1 << 60,
      ),
      GameSort.newest => (b.releaseDate ?? DateTime(1970)).compareTo(
        a.releaseDate ?? DateTime(1970),
      ),
    };
    if (result != 0) return result;
    if (sort == GameSort.popular) {
      final discount = compareDiscount(a, b, now);
      if (discount != 0) return discount;
    }
    final name = a.name.compareTo(b.name);
    return name != 0 ? name : a.id.compareTo(b.id);
  });
  return filtered;
}

int compareDiscount(GameItem a, GameItem b, DateTime now) {
  final ar = a.regularPrice ?? 0, br = b.regularPrice ?? 0;
  final ad = a.saleActiveAt(now) && ar > 0 ? ar - a.discountPrice! : 0;
  final bd = b.saleActiveAt(now) && br > 0 ? br - b.discountPrice! : 0;
  return (bd * (ar > 0 ? ar : 1)).compareTo(ad * (br > 0 ? br : 1));
}

String normalizeSearch(String value) {
  var text = value.toLowerCase().replaceAll('é', 'e');
  const aliases = {
    '포켓몬스터': '포켓몬',
    'persona': '페르소나',
    'pokemon': '포켓몬',
    'pokémon': '포켓몬',
    'scarlet': '스칼렛',
    'violet': '바이올렛',
    'mario': '마리오',
    'zelda': '젤다',
    'animal crossing': '동물의숲',
  };
  for (final entry in aliases.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
}
