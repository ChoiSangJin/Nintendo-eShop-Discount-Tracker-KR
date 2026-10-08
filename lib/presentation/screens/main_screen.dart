import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        unawaited(ref.read(gameListProvider.notifier).refresh());
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameListProvider);
    final controller = ref.read(gameListProvider.notifier);
    final now = DateTime.now().toUtc();
    final wishlist = _tab == 1;
    final games = filterAndSortGames(
      wishlist ? state.favorites.values : state.games,
      genre: _genre,
      query: _query,
      sort: _sort,
      now: now,
    );
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
              applicationVersion: '1.0.0',
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
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (!wishlist &&
                    event.metrics.extentAfter < 400 &&
                    state.error == null &&
                    !state.loading &&
                    !state.loadingMore &&
                    state.hasMore) {
                  unawaited(controller.loadMore());
                }
                return false;
              },
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: CustomScrollView(
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
                                  : state.catalogFallback || state.total == null
                                  ? '한국 공식 할인 게임 ${state.games.length}개 발견'
                                  : '할인 목록 ${state.total}개 · ${state.games.length}개 불러옴',
                              style: const TextStyle(
                                color: Color(0xff747680),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _search,
                              onChanged: (value) =>
                                  setState(() => _query = value),
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
                                          setState(() => _query = '');
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
                                        onSelected: (_) =>
                                            setState(() => _genre = genre),
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
                              '${games.length}개 표시',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            DropdownButton<GameSort>(
                              value: _sort,
                              underline: const SizedBox.shrink(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sort = value);
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
                                ? controller.loadMore()
                                : controller.refresh(),
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
                                    ? '할인 정보를 가져오는 중이에요'
                                    : _query.isNotEmpty || _genre != '전체'
                                    ? '조건에 맞는 게임이 없어요'
                                    : wishlist
                                    ? '관심 있는 할인 게임을 추가해 보세요'
                                    : state.error != null
                                    ? '할인 정보를 불러오지 못했어요'
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
                                    setState(() {
                                      _query = '';
                                      _genre = '전체';
                                    });
                                  },
                                  child: const Text('검색·필터 초기화'),
                                ),
                              if (!wishlist && state.hasMore && !state.loading)
                                TextButton(
                                  onPressed: controller.loadMore,
                                  child: const Text('다음 게임 불러오기'),
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
                    if (!wishlist && games.isNotEmpty && state.hasMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: state.loadingMore
                              ? const Center(child: CircularProgressIndicator())
                              : OutlinedButton(
                                  onPressed: controller.loadMore,
                                  child: const Text('더 많은 할인 게임 찾아보기'),
                                ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Text(
                          '비공식 팬 앱 · 한국 Nintendo eShop',
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
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
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
