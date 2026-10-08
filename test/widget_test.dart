import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:switch_sale_tracker/main.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/widgets/game_card.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    '20-item pages only load on Next and keep previous pages stable',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository()
        ..pages = [
          GamePage(
            List.generate(
              24,
              (i) => exampleGame(
                id: '${70010000000000 + i}',
                name: '게임 ${i.toString().padLeft(2, '0')}',
                discount: 25000,
              ),
            ),
            48,
            24,
          ),
          GamePage(
            List.generate(
              24,
              (i) => exampleGame(
                id: '${70010000000024 + i}',
                name: '게임 ${(i + 24).toString().padLeft(2, '0')}',
                discount: 10000,
              ),
            ),
            48,
            48,
          ),
        ];
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
        '게임 00',
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -12000));
      await tester.pumpAndSettle();
      expect(repository.offsets, [0]);
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음').first);
      await tester.pumpAndSettle();
      expect(repository.offsets, [0, 24]);
      expect(find.text('20개 표시 · 2페이지'), findsOneWidget);
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '게임 20',
      );
      await tester.tap(find.text('이전').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<GameCard>(find.byType(GameCard).first).game.name,
        '게임 00',
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
    'remote search shows non-sale Pokémon aliases and clearing restores sales',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository()
        ..searchPages = [
          GamePage(
            [
              exampleGame(
                name: 'Pokémon Champions',
                discount: null,
                regular: 64800,
              ),
            ],
            1,
            1,
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
      expect(repository.queries, ['포켓몬']);
      expect(find.text('Pokémon Champions'), findsOneWidget);
      expect(find.text('₩64,800'), findsOneWidget);
      expect(find.text('-50%'), findsNothing);
      expect(store.games.single.name, '테스트 게임');
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
      ..pages = [
        GamePage(
          [
            exampleGame(id: '70010000000001', name: '높은 할인', discount: 1000),
            exampleGame(id: '70010000000002', name: '높은 인기', discount: 25000),
          ],
          2,
          2,
        ),
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
