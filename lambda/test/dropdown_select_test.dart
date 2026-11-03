import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';

import 'support/readable_text.dart';

/// The variation picker opened from a set row is its own bottom sheet, and it
/// autofocuses its search field — so the keyboard is up from the first frame.
/// The sheet must fit the space the keyboard leaves it (2026-10-20: a fixed
/// list cap plus the sheet's own height cap added up to more than the
/// keyboard-aware viewport and overflowed the column).
void main() {
  /// A phone-sized viewport with the software keyboard up, the way the sheet
  /// meets it in the session.
  void phoneWithKeyboard(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
    addTearDown(tester.view.reset);
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDropdownPickerSheet<String>(
                context,
                options: [
                  for (var i = 0; i < 20; i++)
                    DropdownOption(label: 'Variation $i', value: 'v$i'),
                ],
                value: 'v0',
                searchable: true,
                onCreateNew: (_) {},
                onSelect: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('fits a phone viewport with the keyboard up', (tester) async {
    phoneWithKeyboard(tester);
    await openPicker(tester);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the picker autofocuses its search field, so the keyboard is up '
          'the moment it opens — its rows must scroll inside what is left, '
          'never overflow the column',
    );
    expect(find.text('Choose variation'), findsOneWidget);
  });

  testWidgets('fits with the keyboard down too', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await openPicker(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Choose variation'), findsOneWidget);
  });

  testWidgets('the list scrolls when there are more options than fit', (
    tester,
  ) async {
    phoneWithKeyboard(tester);
    await openPicker(tester);

    // Every option is reachable: the last one can be scrolled into view.
    await tester.scrollUntilVisible(
      find.text('Variation 19'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Variation 19'), findsOneWidget);
  });

  testWidgets('the picker draws readable ink and type', (tester) async {
    await openPicker(tester);
    expectReadableText(tester, find.byType(MaterialApp));
  });
}
