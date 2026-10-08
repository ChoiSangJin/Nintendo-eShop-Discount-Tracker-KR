import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/widgets/game_filters.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets(
      'filter dialogs avoid system navigation and remain usable at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        int? discount;
        GamePlatform? platform;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => GameFilters(
                    discountBand: discount,
                    platform: platform,
                    onDiscountChanged: (value) =>
                        setState(() => discount = value),
                    onPlatformChanged: (value) =>
                        setState(() => platform = value),
                    onReset: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        void checkSafeBounds() {
          final bounds = tester.getRect(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(bounds.top, greaterThanOrEqualTo(24 + 24));
          expect(bounds.bottom, lessThanOrEqualTo(size.height - 48 - 24));
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byKey(const ValueKey('discount-filter-button')));
        await tester.pumpAndSettle();
        checkSafeBounds();
        final free = find.widgetWithText(ChoiceChip, '100%');
        await tester.ensureVisible(free);
        await tester.tap(free);
        await tester.pumpAndSettle();
        expect(discount, 100);
        await tester.tap(find.byKey(const ValueKey('discount-filter-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '닫기'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(discount, 100);

        await tester.tap(find.byKey(const ValueKey('platform-filter-button')));
        await tester.pumpAndSettle();
        checkSafeBounds();
        final switch2 = find.widgetWithText(ChoiceChip, 'Switch 2');
        await tester.ensureVisible(switch2);
        await tester.tap(switch2);
        await tester.pumpAndSettle();
        expect(platform, GamePlatform.switch2);
        await tester.tap(find.byKey(const ValueKey('platform-filter-button')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(platform, GamePlatform.switch2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
