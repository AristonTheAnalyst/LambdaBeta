import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/menu_popover.dart';

/// A trigger standing [top] down a phone-sized screen, opening the long
/// nine-row menu a weight filter draws — the list that made a panel sliced by
/// the screen's bottom edge visible (2026-10-21).
Future<void> _pumpMenu(WidgetTester tester, {required double top}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: top,
              left: 12,
              child: MenuPopover(
                align: MenuPopoverAlign.start,
                trigger: (context, open) => GestureDetector(
                  onTap: open,
                  child: Container(
                    key: const ValueKey('trigger'),
                    width: 120,
                    height: 40,
                    color: const Color(0xFF222222),
                    alignment: Alignment.center,
                    child: const Text('open'),
                  ),
                ),
                contentBuilder: (context, dismiss) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 9; i++)
                      ChoiceRow(
                        label: 'Row $i',
                        active: i == 0,
                        onTap: dismiss,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a menu with room below opens downward', (tester) async {
    await _pumpMenu(tester, top: 100);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Row 0')).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const ValueKey('trigger'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a menu near the floor opens upward, fully on screen', (
    tester,
  ) async {
    await _pumpMenu(tester, top: 700);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('trigger'));
    final firstRow = find.text('Row 0');
    final lastRow = find.text('Row 8');
    // The whole panel stands above the trigger — Row 0 is its far end.
    expect(
      tester.getBottomLeft(firstRow).dy,
      lessThan(tester.getTopLeft(trigger).dy),
    );
    // And the whole panel is on screen, its long end included — a panel
    // clamped to a sliver of room reads as falling out of the screen.
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(firstRow).top, greaterThan(0));
    expect(tester.getRect(lastRow).bottom, lessThan(screenHeight));
    expect(tester.takeException(), isNull);
  });
}
