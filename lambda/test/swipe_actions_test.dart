import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

/// The swipe drawer the whole app uses (2026-10-23).
///
/// The drawing and the gesture rules were designed in the PR Lab and promoted
/// here: circles that scale in one slot at a time, full-strength paint (no
/// fade anywhere), one drawer open app-wide, and any tap elsewhere closing
/// the open row. The screens only supply actions, so these tests hold the
/// contract directly on [SwipeActions] — the lab's own copy keeps its tests
/// (`test/pr_lab_screen_test.dart`) for the layout experiments that stay
/// there.
void main() {
  /// The x-scale behind an action icon — 0 closed, 1 seated. The x-scale and
  /// not `getMaxScaleOnAxis()`: `Transform.scale` leaves the z axis at 1,
  /// which would make every circle measure 1 whatever its size.
  double scaleOf(WidgetTester tester, IconData icon) => tester
      .widget<Transform>(
        find
            .ancestor(of: find.byIcon(icon), matching: find.byType(Transform))
            .first,
      )
      .transform
      .entry(0, 0);

  SwipeAction action(IconData icon, Color color, Color foreground) =>
      SwipeAction(
        icon: icon,
        color: color,
        foreground: foreground,
        onTap: () {},
      );

  Widget harness({
    required List<SwipeAction> actions,
    double width = 320,
    double height = 52,
    Key? key,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          key: key,
          width: width,
          height: height,
          child: SwipeActions(
            actions: actions,
            child: Container(color: AppColors.surfaceHigh),
          ),
        ),
      ),
    ),
  );

  testWidgets('a swipe arrives one circle at a time, with no fade', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        actions: [
          action(Icons.copy_rounded, AppColors.accent, AppColors.accentText),
          action(Icons.sticky_note_2_outlined, AppColors.primary, AppColors.bg),
          action(Icons.delete_outline, AppColors.danger, AppColors.dangerText),
        ],
      ),
    );
    await tester.pump();

    // Closed: every circle is at zero, and nothing anywhere in the drawer
    // fades — the arrival is scale and only scale.
    for (final icon in [
      Icons.copy_rounded,
      Icons.sticky_note_2_outlined,
      Icons.delete_outline,
    ]) {
      expect(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(scaleOf(tester, icon), 0);
    }

    // Circles, not blocks — the action is a filled disc inside its slot, and
    // the glyph wears the ink the action was handed.
    final disc =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.byIcon(Icons.delete_outline),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(disc.shape, BoxShape.circle);
    expect(disc.color, AppColors.danger);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
      AppColors.dangerText,
    );

    // 52-tall row: the circle tops out at 40 (the row minus 8, capped), so a
    // tall row never draws an action bigger than the row that reveals it.
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.delete_outline),
              matching: find.byType(Container),
            )
            .first,
      ),
      const Size.square(40),
    );

    // The drawer opens from the trailing edge, so the delete circle arrives
    // over the first slot-width of travel while the other two wait at zero.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeActions)),
    );
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(tester, Icons.delete_outline), greaterThan(0.9));
    expect(scaleOf(tester, Icons.sticky_note_2_outlined), 0);
    expect(scaleOf(tester, Icons.copy_rounded), 0);

    // Second slot-width: the note circle's turn, copy still waiting.
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(tester, Icons.sticky_note_2_outlined), greaterThan(0.9));
    expect(scaleOf(tester, Icons.copy_rounded), 0);

    // Third: copy lands, all three seated in list order.
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(tester, Icons.copy_rounded), greaterThan(0.9));
    await gesture.up();
    await tester.pumpAndSettle();

    // Fully open: one 52pt slot between neighbouring circle centres, which
    // leaves 12 between 40 discs — one cluster, not three separate controls.
    final copyX = tester.getCenter(find.byIcon(Icons.copy_rounded)).dx;
    final noteX = tester
        .getCenter(find.byIcon(Icons.sticky_note_2_outlined))
        .dx;
    final deleteX = tester.getCenter(find.byIcon(Icons.delete_outline)).dx;
    expect(noteX - copyX, 52);
    expect(deleteX - noteX, 52);
  });

  testWidgets('opening one drawer closes the one already open', (tester) async {
    Widget row(String key, IconData icon) => SizedBox(
      key: ValueKey(key),
      width: 320,
      height: 52,
      child: SwipeActions(
        actions: [action(icon, AppColors.danger, AppColors.dangerText)],
        child: Container(color: AppColors.surfaceHigh),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row('row-a', Icons.delete_outline),
                const SizedBox(height: 12),
                row('row-b', Icons.flag),
              ],
            ),
          ),
        ),
      ),
    );

    // Open the first row.
    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-a'))),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester, Icons.delete_outline), 1);

    // Swiping the second row hands the stage over: the first goes back —
    // one drawer on screen at a time, without the screens wiring anything.
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-b'))),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester, Icons.flag), 1);
    expect(scaleOf(tester, Icons.delete_outline), 0);
  });

  testWidgets('a tap anywhere but the action circles puts the row back', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        actions: [
          action(Icons.delete_outline, AppColors.danger, AppColors.dangerText),
        ],
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeActions)),
    );
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester, Icons.delete_outline), 1);

    // A tap on the page, away from the row — the drawer was open and the
    // release travelled nowhere, so it counts as a tap and the row goes back.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(scaleOf(tester, Icons.delete_outline), 0);
  });

  testWidgets('tapping an action fires it and puts the row back', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(
      harness(
        actions: [
          SwipeAction(
            icon: Icons.delete_outline,
            color: AppColors.danger,
            foreground: AppColors.dangerText,
            onTap: () => fired++,
          ),
        ],
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeActions)),
    );
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester, Icons.delete_outline), 1);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(fired, 1);
    expect(
      scaleOf(tester, Icons.delete_outline),
      0,
      reason: 'the action was taken — the row it belonged to goes back',
    );
  });

  testWidgets('with no actions the child is passed through untouched', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeActions(actions: const [], child: const Text('plain row')),
        ),
      ),
    );

    expect(find.text('plain row'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SwipeActions),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
      reason:
          'no actions means no drawer layer — the child is the whole '
          'widget',
    );
  });
}
