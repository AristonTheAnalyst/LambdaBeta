import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/menu_popover.dart';
import 'package:lambda/shared/widgets/undo_redo_buttons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The undo/redo pair and its trash slot (2026-10-13). The pair is the
/// ordinary case; the slot is the live session's deleted planned exercises —
/// a MENU of them, so a restore picks the one meant, not merely the last one
/// deleted.
///
/// What is pinned here is the slot's three states (absent, greyed, a menu)
/// and the menu's own contract: every deleted exercise on it, most recently
/// deleted first, the row tapped reporting its index, and the menu left
/// standing after a restore so the rest can be worked through — closing
/// itself only when the list runs out.
void main() {
  Future<void> pumpPair(
    WidgetTester tester, {
    List<String> deleted = const [],
    void Function(int index)? onRestore,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: UndoRedoButtons(
            canUndo: false,
            canRedo: false,
            onUndo: () {},
            onRedo: () {},
            deletedExercises: deleted,
            onPickDeletedExercise: onRestore,
          ),
        ),
      ),
    ),
  );

  testWidgets('with no restore callback the pair stands alone', (tester) async {
    // The planner's and the logs viewer's headers: they keep the plain pair.
    await pumpPair(tester);

    expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
    expect(find.byIcon(LucideIcons.redo2), findsOneWidget);
    expect(find.byIcon(LucideIcons.rotateCcw), findsNothing);
    expect(find.byType(MenuPopover), findsNothing);
  });

  testWidgets('the trash slot is grey and inert while nothing is deleted', (
    tester,
  ) async {
    await pumpPair(tester, onRestore: (_) {});

    final trash = tester.widget<Icon>(find.byIcon(LucideIcons.rotateCcw));
    expect(
      trash.color,
      AppColors.muted,
      reason: 'nothing to restore — the slot waits greyed',
    );
    expect(
      find.byType(MenuPopover),
      findsNothing,
      reason: 'no menu hangs off a slot with nothing in it',
    );

    await tester.tap(find.byIcon(LucideIcons.rotateCcw));
    await tester.pumpAndSettle();
    expect(
      find.byType(MenuPopover),
      findsNothing,
      reason: 'a tap on the dead slot opens nothing',
    );
  });

  testWidgets('the menu lists every deleted exercise and reports the row '
      'tapped', (tester) async {
    final picked = <int>[];
    await pumpPair(
      tester,
      deleted: const ['Bench Press', 'Back Squat'],
      onRestore: picked.add,
    );

    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.rotateCcw)).color,
      AppColors.primary,
      reason: 'there is something in the slot — it lights',
    );

    await tester.tap(find.byIcon(LucideIcons.rotateCcw));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(
      find.text('Back Squat'),
      findsOneWidget,
      reason: 'the list is the whole list, not just the newest',
    );

    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();
    expect(
      picked,
      [1],
      reason:
          'the row tapped reports its own index — the second entry '
          'here, which the old single-restore button could not reach',
    );
    expect(
      find.text('Back Squat'),
      findsOneWidget,
      reason: 'the menu stays up: the rest of the list is still work',
    );
  });

  testWidgets('restoring the last one takes the menu down with it', (
    tester,
  ) async {
    // The slot swaps from a menu to the greyed button the moment the list
    // empties, and the panel's portal goes with it — no empty panel left
    // hanging over the session.
    await tester.pumpWidget(const MaterialApp(home: _Host()));

    await tester.tap(find.byIcon(LucideIcons.rotateCcw));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);

    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bench Press'),
      findsOneWidget,
      reason: 'the one restored leaves the menu',
    );
    expect(find.byType(MenuPopover), findsOneWidget);

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(
      find.byType(MenuPopover),
      findsNothing,
      reason: 'list empty — the slot falls back to the greyed button',
    );
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.rotateCcw)).color,
      AppColors.muted,
    );
  });
}

/// Stands in for the live session: the restore callback empties the list the
/// way the VM's does (each restore takes its entry out).
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> names = ['Bench Press', 'Back Squat'];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: UndoRedoButtons(
        canUndo: false,
        canRedo: false,
        onUndo: () {},
        onRedo: () {},
        deletedExercises: names,
        onPickDeletedExercise: (index) =>
            setState(() => names = [...names]..removeAt(index)),
      ),
    ),
  );
}
