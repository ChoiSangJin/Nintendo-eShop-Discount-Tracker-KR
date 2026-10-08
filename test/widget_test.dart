import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:switch_sale_tracker/main.dart';
import 'dart:async';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/widgets/game_card.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/widgets/game_platform_badge.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'discount/platform selection composes before paging and resets cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository()
        ..games = [
          for (var i = 0; i < 23; i++)
            exampleGame(
              id: '${70010000000000 + i}',
              name: '테스트 ${i.toString().padLeft(2, '0')}',
              regular: 20000,
              discount: 10000,
              hardware: i == 22
                  ? 'Nintendo Switch 2 Edition'
                  : i.isEven
                  ? 'Nintendo Switch 2'
                  : 'Nintendo Switch',
            ),
          exampleGame(
            id: '70010000000100',
            name: '40퍼센트',
            regular: 20000,
            discount: 12000,
            hardware: 'Nintendo Switch 2',
          ),
          exampleGame(
            id: '70010000000101',
            name: '60퍼센트',
            regular: 20000,
            discount: 8000,
          ),
          exampleGame(
            id: '70010000000102',
            name: '정가 게임',
            regular: 20000,
            discount: null,
            hardware: 'Nintendo Switch 2',
          ),
        ];
      final store = MemoryStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            gameRepositoryProvider.overrideWithValue(repo),
          ],
          child: const TrackerApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      expect(find.text('5개 표시 · 2페이지'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discount-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '50%대'));
      await tester.pumpAndSettle();
      expect(find.text('20개 표시 · 1페이지'), findsOneWidget);
      expect(find.text('한국 공식 할인 게임 23개 발견'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discount-filter-button')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('할인율 50%대 ▾'), findsOneWidget);
      expect(find.text('한국 공식 할인 게임 23개 발견'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('platform-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Switch 2'));
      await tester.pumpAndSettle();
      expect(find.text('12개 표시 · 1페이지'), findsOneWidget);
      expect(find.text('한국 공식 할인 게임 12개 발견'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '다음').first,
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.platform,
        GamePlatform.switch2,
      );
      await tester.enterText(find.byType(TextField), '테스트 00');
      await tester.pumpAndSettle();
      expect(find.text('1개 표시 · 1페이지'), findsOneWidget);
      await tester.tap(find.byTooltip('관심 게임에 추가').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('관심 게임'));
      await tester.pumpAndSettle();
      expect(find.text('할인율 전체 ▾'), findsOneWidget);
      expect(find.text('기종 전체 ▾'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('platform-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Switch 1'));
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 게임이 없어요'), findsOneWidget);
      await tester.ensureVisible(find.text('검색·필터 초기화'));
      await tester.tap(find.text('검색·필터 초기화'));
      await tester.pumpAndSettle();
      expect(find.text('테스트 00'), findsOneWidget);
      expect(repo.catalogCalls, 1);
      expect(store.games, hasLength(26));
      expect(store.readFavorites(), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Switch 2 Edition has a red platform badge in cards and details',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final game = exampleGame(hardware: 'Nintendo Switch 2 Edition');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameCard(
              game: game,
              favorite: false,
              onFavorite: () {},
              now: DateTime.now(),
            ),
          ),
        ),
      );
      Color? badgeColor() =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byType(GamePlatformBadge).last,
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(find.text('Switch 2 Edition'), findsOneWidget);
      expect(badgeColor(), const Color(0xffe60012));
      await tester.tap(find.text(game.name));
      await tester.pumpAndSettle();
      expect(find.byType(GamePlatformBadge), findsNWidgets(2));
      expect(badgeColor(), const Color(0xffe60012));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'price exclusion precedes sorting/paging but preserves full search and favorites',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository()
        ..games = [
          for (var i = 0; i < 21; i++)
            exampleGame(
              id: '${70010000000000 + i}',
              name: '표시 게임 $i',
              regular: 10000,
              discount: 5000 + i,
            ),
          for (final price in [1000, 3000, 4999])
            exampleGame(
              id: '${70010000001000 + price}',
              name: '제외 게임 $price',
              regular: 10000,
              discount: price,
            ),
          exampleGame(id: '70010000009000', name: '경계 999', discount: 999),
          exampleGame(id: '70010000009001', name: '무료 게임', discount: 0),
          exampleGame(
            id: '70010000009002',
            name: '정가 게임',
            regular: 3000,
            discount: null,
          ),
        ];
      final store = MemoryStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            gameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const TrackerApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('한국 공식 할인 게임 23개 발견'), findsOneWidget);
      expect(find.text('판매가 1,000~4,999원 게임 제외'), findsOneWidget);
      expect(find.text('20개 표시 · 1페이지'), findsOneWidget);
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '무료 게임',
      );
      expect(find.text('제외 게임 1000'), findsNothing);
      expect(store.games, hasLength(27));
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      expect(find.text('3개 표시 · 2페이지'), findsOneWidget);
      expect(repository.catalogCalls, 1);
      await tester.tap(find.byType(DropdownButton<GameSort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('최저 가격순').last);
      await tester.pumpAndSettle();
      expect(find.text('20개 표시 · 1페이지'), findsOneWidget);
      expect(find.text('한국 공식 할인 게임 23개 발견'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '제외 게임');
      await tester.pumpAndSettle();
      expect(find.text('3개 표시 · 1페이지'), findsOneWidget);
      expect(find.text('제외 게임 1000'), findsOneWidget);
      expect(find.text('판매가 1,000~4,999원 게임 제외'), findsNothing);
      await tester.tap(find.byTooltip('관심 게임에 추가').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('관심 게임'));
      await tester.pumpAndSettle();
      expect(find.text('제외 게임 1000'), findsOneWidget);
      expect(store.readFavorites().single.discountPrice, 1000);
      expect(store.games, hasLength(27));
      expect(repository.catalogCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    '20-item pages are globally sorted and navigating makes no requests',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository()
        ..games = List.generate(
          48,
          (i) => exampleGame(
            id: '${70010000000000 + i}',
            name: '게임 ${i.toString().padLeft(2, '0')}',
            discount: i < 24 ? 25000 : 10000,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(MemoryStore()),
            gameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const TrackerApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('20개 표시 · 1페이지'), findsOneWidget);
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '게임 24',
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -12000));
      await tester.pumpAndSettle();
      expect(repository.catalogCalls, 1);
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      expect(repository.catalogCalls, 1);
      expect(find.text('20개 표시 · 2페이지'), findsOneWidget);
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '게임 44',
      );
      await tester.tap(find.text('이전').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '게임 24',
      );
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      expect(find.text('8개 표시 · 3페이지'), findsOneWidget);
      final next = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '다음').first,
      );
      expect(next.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'local full-catalog search shows non-sale Pokémon aliases and clearing restores sales',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository()
        ..games = [
          exampleGame(),
          exampleGame(
            id: '70010000000002',
            name: 'Pokémon Champions',
            discount: null,
            regular: 64800,
          ),
        ];
      final store = MemoryStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            gameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const TrackerApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '포켓몬');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.catalogCalls, 1);
      expect(find.text('Pokémon Champions'), findsOneWidget);
      expect(find.text('₩64,800'), findsOneWidget);
      expect(find.text('-50%'), findsNothing);
      expect(store.games, hasLength(2));
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('테스트 게임'), findsOneWidget);
      expect(find.text('Pokémon Champions'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('popular sort explains US source and prioritizes ranked games', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRepository()
      ..games = [
        exampleGame(id: '70010000000001', name: '높은 할인', discount: 6000),
        exampleGame(id: '70010000000002', name: '높은 인기', discount: 25000),
      ]
      ..popularity = {'70010000000002': 1};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(MemoryStore()),
          gameRepositoryProvider.overrideWithValue(repository),
        ],
        child: const TrackerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<GameSort>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('인기순').last);
    await tester.pumpAndSettle();
    expect(find.text('미국 공식 Best Sellers 기준 · 순위가 확인된 게임 우선'), findsOneWidget);
    expect(
      tester.widget<GameCard>(find.byType(GameCard).first).game.name,
      '높은 인기',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'loading blocks entire app, back and navigation; failure releases barrier',
    (tester) async {
      final repo = FakeRepository()..pending = Completer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(MemoryStore()),
            gameRepositoryProvider.overrideWithValue(repo),
          ],
          child: const TrackerApp(),
        ),
      );
      await tester.pump();
      repo.progress!(const CatalogProgress('전체 게임 가격 확인 중', 30, 100));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('global-loading-barrier')),
        findsOneWidget,
      );
      expect(find.text('30 / 100'), findsOneWidget);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      await tester.tap(find.byTooltip('앱 정보'), warnIfMissed: false);
      await tester.tap(find.text('관심 게임'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(AboutDialog), findsNothing);
      expect(find.text('마음에 담은 게임'), findsNothing);
      repo.pending!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('global-loading-barrier')),
        findsNothing,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      await tester.tap(find.text('관심 게임'));
      await tester.pumpAndSettle();
      expect(find.text('마음에 담은 게임'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('small screen with large text has no layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(MemoryStore()),
          gameRepositoryProvider.overrideWithValue(FakeRepository()),
        ],
        child: const TrackerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('discount-filter-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('discount-filter-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '50%대'));
    await tester.tap(find.widgetWithText(ChoiceChip, '50%대'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('platform-filter-button')),
    );
    await tester.tap(find.byKey(const ValueKey('platform-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Switch 2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('할인율·기종 필터 초기화'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('loads Korean game, favorite toggle and wishlist navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          gameRepositoryProvider.overrideWithValue(FakeRepository()),
        ],
        child: const TrackerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('테스트 게임'), findsOneWidget);
    expect(find.text('₩25,000'), findsOneWidget);
    await tester.tap(find.byTooltip('관심 게임에 추가'));
    await tester.pumpAndSettle();
    expect(store.readFavorites(), hasLength(1));
    await tester.tap(find.text('관심 게임'));
    await tester.pumpAndSettle();
    expect(find.text('마음에 담은 게임'), findsOneWidget);
    expect(find.text('테스트 게임'), findsOneWidget);
    await tester.tap(find.byTooltip('관심 게임에서 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('관심 있는 할인 게임을 추가해 보세요'), findsOneWidget);
    expect(store.readFavorites(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed initial load shows a retry and recovers', (tester) async {
    final repository = FakeRepository()..failure = StateError('Offline');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(MemoryStore()),
          gameRepositoryProvider.overrideWithValue(repository),
        ],
        child: const TrackerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('재시도'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('재시도'), findsOneWidget);
    repository.failure = null;
    await tester.ensureVisible(find.text('재시도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 게임'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
