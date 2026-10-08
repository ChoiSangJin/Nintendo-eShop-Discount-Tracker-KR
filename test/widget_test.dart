import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:switch_sale_tracker/main.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
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
    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 게임'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
