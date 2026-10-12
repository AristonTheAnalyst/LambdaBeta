import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/slide_tab_bar.dart';

/// The shared tab strip — and the one thing on it that is not a label: the
/// dot a strip wears on a tab that still holds something the user has not
/// dealt with. The review landing is the first wearer (2026-10-10): an
/// unreviewed workout or a goal without its status report puts the accent dot
/// beside that half's label, and clearing the work is how the tab goes quiet.
///
/// A strip asked for no dots must draw none — every other caller is that, and
/// a stray dot would claim unfinished business nobody asked about.
void main() {
  /// The dots the bar is actually drawing, matched on what a dot is — a
  /// small accent circle — rather than a key, so this fails if one ever stops
  /// being one.
  Finder dots() => find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final decoration = w.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color == AppColors.accent;
  });

  Future<void> pump(
    WidgetTester tester, {
    Set<int> dotTabs = const {},
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SlideTabBar(
          tabs: const ['Workouts', 'Goals'],
          activeIndex: 0,
          onTap: (_) {},
          dotTabs: dotTabs,
        ),
      ),
    ),
  );

  testWidgets('a strip with nothing pending is labels alone', (tester) async {
    await pump(tester);

    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
    expect(dots(), findsNothing);
  });

  testWidgets('a dot rides right of the label it marks', (tester) async {
    await pump(tester, dotTabs: {1});

    expect(dots(), findsOneWidget);
    expect(
      tester.getCenter(dots()).dx,
      greaterThan(tester.getCenter(find.text('Goals')).dx),
      reason: 'the dot belongs to the label it sits beside, not the strip',
    );
  });

  testWidgets('both halves can be marked at once', (tester) async {
    await pump(tester, dotTabs: {0, 1});

    expect(dots(), findsNWidgets(2));
    expect(
      tester.getCenter(dots().at(0)).dx,
      lessThan(tester.getCenter(find.text('Goals')).dx),
      reason: 'each dot stands at its own label',
    );
  });
}
