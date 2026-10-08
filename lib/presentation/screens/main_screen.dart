import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/game_item.dart';
import '../controllers/game_list_controller.dart';
import '../widgets/game_card.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});
  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  String _genre = '전체';
  String _query = '';
  GameSort _sort = GameSort.discount;
  final _search = TextEditingController();
  Timer? _clock;
  static const _pageSize = 20;
  int _page = 0;
  bool _paging = false;
  final _scroll = ScrollController();
  final _orderedIds = <String>[];

  void _resetPage() {
    _page = 0;
    _orderedIds.clear();
  }

  void _changeQuery(String value) {
    setState(() {
      _query = value;
      _resetPage();
    });
    if (_tab == 0) ref.read(gameListProvider.notifier).setQuery(value);
  }

  List<GameItem> _filtered(GameListState state) {
    final wishlist = _tab == 1;
    return filterAndSortGames(
      wishlist
          ? state.favorites.values
          : state.games.where(
              (g) =>
                  state.query.isNotEmpty ||
                  g.saleActiveAt(DateTime.now().toUtc()),
            ),
      genre: _genre,
      // Remote search understands related names and aliases. Do not remove
      // those matches by reapplying a literal substring filter.
      query: wishlist ? _query : '',
      sort: _sort,
      now: DateTime.now().toUtc(),
    );
  }

  List<GameItem> _ordered(GameListState state) {
    final filtered = _filtered(state);
    final byId = {for (final g in filtered) g.id: g};
    _orderedIds.removeWhere((id) => !byId.containsKey(id));
    final seen = _orderedIds.toSet();
    _orderedIds.addAll(filtered.where((g) => seen.add(g.id)).map((g) => g.id));
    // Keep already visited pages stable when the next batch arrives. Changing
    // search, genre, sort or refreshing starts a newly sorted traversal.
    return _orderedIds.map((id) => byId[id]!).toList();
  }

  Future<void> _refresh() async {
    setState(_resetPage);
    await ref.read(gameListProvider.notifier).refresh();
    if (mounted) setState(_resetPage);
  }

  Future<void> _goToPage(int page) async {
    if (_paging || page < 0) return;
    if (page <= _page) {
      setState(() => _page = page);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    final query = _query;
    final genre = _genre;
    final sort = _sort;
    final tab = _tab;
    final target = _ordered(ref.read(gameListProvider)).isEmpty ? 0 : page;
    setState(() => _paging = true);
    final controller = ref.read(gameListProvider.notifier);
    try {
      while (mounted) {
        final state = ref.read(gameListProvider);
        if (_query != query ||
            _genre != genre ||
            _sort != sort ||
            _tab != tab) {
          return;
        }
        final count = _ordered(state).length;
        if (count >= (target + 1) * _pageSize ||
            _tab == 1 ||
            !state.hasMore ||
            state.loading) {
          break;
        }
        await controller.loadMore();
        if (ref.read(gameListProvider).error != null) return;
      }
      if (mounted &&
          _ordered(ref.read(gameListProvider)).length > target * _pageSize) {
        setState(() => _page = target);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(gameListProvider.notifier).refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final last = ref.read(gameListProvider).updatedAt;
      if (last == null ||
          DateTime.now().toUtc().difference(last) >
              const Duration(minutes: 2)) {
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameListProvider);
    final controller = ref.read(gameListProvider.notifier);
    final now = DateTime.now().toUtc();
    final wishlist = _tab == 1;
    final allGames = _ordered(state);
    final page = allGames.isEmpty
        ? 0
        : _page.clamp(0, (allGames.length - 1) ~/ _pageSize);
    _page = page;
    final games = allGames.skip(page * _pageSize).take(_pageSize).toList();
    final canNext =
        !_paging &&
        !state.loading &&
        !state.loadingPopularity &&
        (allGames.length > (page + 1) * _pageSize ||
            (!wishlist && state.hasMore));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: const Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: Color(0xffe60012)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'SWITCH · 할인 트래커',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '앱 정보',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Switch 할인 트래커 KR',
              applicationVersion: '1.1.0',
              applicationIcon: const Icon(
                Icons.sports_esports_rounded,
                color: Color(0xffe60012),
                size: 40,
              ),
              children: const [
                Text(
                  '한국 Nintendo eShop 할인 탐색 · 관심 게임 저장\n\n'
                  '한국 eShop 및 한국 공식 스토어 정보를 사용합니다. 정식 한국어 제목이 확인되는 게임은 한국어로 표시합니다.\n\n'
                  'Nintendo와 제휴하지 않은 팬 앱입니다. Nintendo Switch 및 관련 상표는 Nintendo의 자산입니다.',
                ),
              ],
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scroll,
                key: PageStorageKey('tab_$_tab'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xff171a22),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'KR eSHOP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text(
                                  '한국 스토어 · 원화 가격',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff777881),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            wishlist ? '마음에 담은 게임' : '좋은 게임,\n더 좋은 가격.',
                            style: const TextStyle(
                              fontSize: 32,
                              height: 1.2,
                              color: Color(0xff171a22),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            wishlist
                                ? '${state.favorites.length}개의 관심 게임을 모아봤어요.'
                                : _query.trim().isNotEmpty
                                ? '전체 게임 검색 · 할인하지 않는 게임도 표시해요'
                                : '한국 공식 할인 게임 ${state.games.length}개 발견',
                            style: const TextStyle(
                              color: Color(0xff747680),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _search,
                            onChanged: _changeQuery,
                            decoration: InputDecoration(
                              hintText: '한국어·영어 게임명 검색',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '검색어 지우기',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () {
                                        _search.clear();
                                        _changeQuery('');
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children:
                            [
                                  '전체',
                                  '액션',
                                  'RPG',
                                  '어드벤처',
                                  '퍼즐',
                                  '시뮬레이션',
                                  '스포츠',
                                  '미분류',
                                ]
                                .map(
                                  (genre) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(genre),
                                      selected: _genre == genre,
                                      showCheckmark: false,
                                      onSelected: (_) => setState(() {
                                        _genre = genre;
                                        _resetPage();
                                      }),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        children: [
                          Text(
                            '${games.length}개 표시 · ${page + 1}페이지',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          DropdownButton<GameSort>(
                            value: _sort,
                            underline: const SizedBox.shrink(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _sort = value;
                                  _resetPage();
                                });
                                if (value == GameSort.popular) {
                                  unawaited(
                                    controller.loadPopularity().then((_) {
                                      if (mounted &&
                                          _sort == GameSort.popular) {
                                        setState(_resetPage);
                                      }
                                    }),
                                  );
                                }
                              }
                            },
                            items: GameSort.values
                                .map(
                                  (sort) => DropdownMenuItem(
                                    value: sort,
                                    child: Text(
                                      sort.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _pagination(page, canNext)),
                  if (_sort == GameSort.popular)
                    SliverToBoxAdapter(
                      child: _notice(
                        state.loadingPopularity
                            ? '미국 공식 인기 목록을 확인하는 중이에요'
                            : state.popularityError ??
                                  '미국 공식 Best Sellers 기준 · 순위가 확인된 게임 우선',
                        icon: Icons.trending_up_rounded,
                        action: state.popularityError == null
                            ? null
                            : () => unawaited(controller.loadPopularity()),
                      ),
                    ),
                  if (state.loading)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (state.cached && state.games.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _notice(
                        '저장된 조회 결과${state.updatedAt == null ? '' : ' · ${koreanDate(state.updatedAt!)}'}',
                        icon: Icons.history_rounded,
                      ),
                    ),
                  if (state.error != null)
                    SliverToBoxAdapter(
                      child: _notice(
                        state.error!,
                        action: () => unawaited(
                          !wishlist && state.hasMore && !state.cached
                              ? _goToPage(page + 1)
                              : _refresh(),
                        ),
                        icon: Icons.wifi_off_rounded,
                      ),
                    ),
                  if (state.storageError != null)
                    SliverToBoxAdapter(
                      child: _notice(
                        state.storageError!,
                        icon: Icons.storage_rounded,
                      ),
                    ),
                  if (games.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              wishlist
                                  ? Icons.favorite_border_rounded
                                  : Icons.travel_explore_rounded,
                              size: 54,
                              color: const Color(0xffbbb9b2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.loading
                                  ? _query.trim().isEmpty
                                        ? '할인 정보를 가져오는 중이에요'
                                        : '전체 게임을 검색하는 중이에요'
                                  : !wishlist && state.error != null
                                  ? '게임 정보를 불러오지 못했어요'
                                  : _query.isNotEmpty || _genre != '전체'
                                  ? '조건에 맞는 게임이 없어요'
                                  : wishlist
                                  ? '관심 있는 할인 게임을 추가해 보세요'
                                  : '현재 할인 게임이 없어요',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_query.isNotEmpty || _genre != '전체')
                              TextButton(
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _genre = '전체');
                                  _changeQuery('');
                                },
                                child: const Text('검색·필터 초기화'),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.crossAxisExtent >= 600
                              ? 2
                              : 1;
                          return SliverList.builder(
                            itemCount: (games.length / columns).ceil(),
                            itemBuilder: (context, row) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(columns * 2 - 1, (
                                  column,
                                ) {
                                  if (column.isOdd) {
                                    return const SizedBox(width: 18);
                                  }
                                  final index = row * columns + column ~/ 2;
                                  if (index >= games.length) {
                                    return const Expanded(child: SizedBox());
                                  }
                                  final game = games[index];
                                  return Expanded(
                                    child: GameCard(
                                      key: ValueKey(game.id),
                                      game: game,
                                      now: now,
                                      favorite: state.favorites.containsKey(
                                        game.id,
                                      ),
                                      onFavorite: () => unawaited(
                                        controller.toggleFavorite(game),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (games.isNotEmpty)
                    SliverToBoxAdapter(child: _pagination(page, canNext)),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Text(
                        '정렬은 불러온 게임 기준 · 이전 페이지 순서 유지\n비공식 팬 앱 · 한국 Nintendo eShop',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff8b8c94),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          _search.clear();
          setState(() {
            _tab = value;
            _genre = '전체';
          });
          _changeQuery('');
          controller.setQuery('');
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '할인 탐색',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: state.favorites.isNotEmpty,
              label: Text('${state.favorites.length}'),
              child: const Icon(Icons.favorite_border_rounded),
            ),
            selectedIcon: const Icon(Icons.favorite_rounded),
            label: '관심 게임',
          ),
        ],
      ),
    );
  }

  Widget _pagination(int page, bool canNext) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: page > 0 && !_paging
              ? () => unawaited(_goToPage(page - 1))
              : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('이전'),
        ),
        Text('${page + 1}페이지 · 20개씩', style: const TextStyle(fontSize: 12)),
        OutlinedButton.icon(
          onPressed: canNext ? () => unawaited(_goToPage(page + 1)) : null,
          icon: _paging
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          label: Text(_paging ? '찾는 중' : '다음'),
        ),
      ],
    ),
  );

  Widget _notice(
    String message, {
    VoidCallback? action,
    required IconData icon,
  }) => Container(
    margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffffeddc),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xff9c5625)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: Color(0xff8b4820)),
          ),
        ),
        if (action != null)
          TextButton(onPressed: action, child: const Text('재시도')),
      ],
    ),
  );
}
