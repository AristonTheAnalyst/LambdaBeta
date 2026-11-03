import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/keyboard_dismiss.dart';

/// The app's two dismissal wrappers. `KeyboardDismissOnTap` is wired once, at
/// the app root, so these cases stand for every text field in the app: a tap
/// on empty space lowers the keyboard, while a tap that operates a control —
/// or another text field — keeps it (2026-10-20).
///
/// The harness wires the widget the way `LambdaApp` does: `MaterialApp.builder`
/// wraps the navigator child, so routes and sheets are descendants too.
Widget _harness({
  required FocusNode first,
  required FocusNode second,
  VoidCallback? onAct,
}) {
  return MaterialApp(
    builder: (context, child) => KeyboardDismissOnTap(child: child!),
    home: Scaffold(
      body: Column(
        children: [
          TextField(key: const ValueKey('a'), focusNode: first),
          TextField(key: const ValueKey('b'), focusNode: second),
          TextButton(
            key: const ValueKey('act'),
            onPressed: onAct ?? () {},
            child: const Text('act'),
          ),
          Expanded(
            // Empty space: nothing here owns a gesture.
            child: Container(key: const ValueKey('empty')),
          ),
        ],
      ),
    ),
  );
}

/// A scrollable page under the root wrapper — the session page's shape: a
/// field at the top, more rows than fit.
Widget _scrollingHarness({
  required FocusNode field,
  ScrollController? controller,
}) {
  return MaterialApp(
    builder: (context, child) => KeyboardDismissOnTap(child: child!),
    home: Scaffold(
      body: ListView(
        controller: controller,
        children: [
          TextField(key: const ValueKey('a'), focusNode: field),
          for (var i = 0; i < 30; i++)
            SizedBox(height: 60, child: Text('row $i')),
        ],
      ),
    ),
  );
}

void main() {
  late FocusNode first;
  late FocusNode second;

  setUp(() {
    first = FocusNode();
    second = FocusNode();
  });

  tearDown(() {
    first.dispose();
    second.dispose();
  });

  /// Blank space is injected at coordinates, not through a finder: a bare
  /// `Container` is correctly *not* in the hit-test path itself — the root
  /// `GestureDetector` with `HitTestBehavior.opaque` is what receives the tap.
  Future<void> tapBlank(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('empty'))));
    await tester.pump();
  }

  testWidgets('a tap on blank space dismisses the keyboard', (tester) async {
    await tester.pumpWidget(_harness(first: first, second: second));
    await tester.showKeyboard(find.byKey(const ValueKey('a')));
    expect(first.hasFocus, isTrue, reason: 'the field is up, as in a set cell');

    await tapBlank(tester);

    expect(
      first.hasFocus,
      isFalse,
      reason: 'the whole point: empty space is a way out of the keyboard',
    );
  });

  testWidgets('a tap on another field transfers focus, never dismisses first', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(first: first, second: second));
    await tester.showKeyboard(find.byKey(const ValueKey('a')));
    expect(first.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();

    expect(
      second.hasFocus,
      isTrue,
      reason:
          'the field wins the arena over the root — if the root had won, '
          'this field would not hold focus (only one recognizer wins)',
    );
    expect(
      first.hasFocus,
      isFalse,
      reason:
          'focus moved directly between the cells, with no trip through '
          '"no focus" — that is what keeps the keyboard from blinking',
    );
  });

  testWidgets('a tap that acts runs its callback and keeps the keyboard', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _harness(first: first, second: second, onAct: () => taps++),
    );
    await tester.showKeyboard(find.byKey(const ValueKey('a')));

    await tester.tap(find.byKey(const ValueKey('act')));
    await tester.pump();

    expect(taps, 1, reason: 'a control is not empty space');
    expect(
      first.hasFocus,
      isTrue,
      reason:
          'Material buttons never request focus, so the field keeps the '
          'keyboard — exactly what a pill tap in the session does today',
    );
  });

  testWidgets('a drag is not a tap', (tester) async {
    await tester.pumpWidget(_scrollingHarness(field: first));
    await tester.showKeyboard(find.byKey(const ValueKey('a')));
    expect(first.hasFocus, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(
      scrollable.position.pixels,
      greaterThan(0),
      reason: 'the list really scrolled, so this is the gesture under test',
    );
    expect(
      first.hasFocus,
      isTrue,
      reason:
          'scrolling to read a later set must not lower the keyboard — the '
          'scrollable wins the arena on movement, and the default '
          '`ScrollViewKeyboardDismissBehavior.manual` keeps it that way',
    );
  });

  testWidgets('a blank tap with nothing focused is harmless', (tester) async {
    await tester.pumpWidget(_harness(first: first, second: second));

    await tapBlank(tester);

    expect(tester.takeException(), isNull);
    expect(first.hasFocus, isFalse);
    expect(second.hasFocus, isFalse);
  });

  testWidgets('a blank tap inside a sheet dismisses without closing it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissOnTap(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        key: const ValueKey('sheetField'),
                        focusNode: first,
                      ),
                      // Blank sheet space — inside the sheet, never the
                      // barrier (a barrier tap would pop the sheet).
                      const SizedBox(key: ValueKey('sheetBlank'), height: 200),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byKey(const ValueKey('sheetField')));
    expect(first.hasFocus, isTrue);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('sheetBlank'))),
    );
    await tester.pumpAndSettle();

    expect(
      first.hasFocus,
      isFalse,
      reason: 'the sheet is covered by the app root too',
    );
    expect(
      find.byKey(const ValueKey('sheetField')),
      findsOneWidget,
      reason:
          'the tap was inside the sheet — the keyboard goes away, the sheet '
          'stays (the add-exercise picker\'s exact situation)',
    );
  });

  group('KeyboardDismissOnScroll', () {
    testWidgets('a user drag dismisses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeyboardDismissOnScroll(
              child: ListView(
                children: [
                  TextField(key: const ValueKey('a'), focusNode: first),
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byKey(const ValueKey('a')));
      expect(first.hasFocus, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(
        first.hasFocus,
        isFalse,
        reason: 'the profile page deliberately lowers the keyboard on a drag',
      );
    });

    testWidgets('a programmatic scroll does not', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeyboardDismissOnScroll(
              child: ListView(
                controller: controller,
                children: [
                  TextField(key: const ValueKey('a'), focusNode: first),
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byKey(const ValueKey('a')));

      controller.jumpTo(100);
      await tester.pump();

      expect(
        first.hasFocus,
        isTrue,
        reason:
            'the framework\'s ensureVisible (revealing a focused field above '
            'the keyboard) is programmatic — it has no dragDetails and must '
            'not steal focus from the field being edited',
      );
    });
  });
}
