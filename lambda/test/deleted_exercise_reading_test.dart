import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/menu_popover.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';
import 'package:lambda/shared/widgets/undo_redo_buttons.dart';

/// A deleted exercise's reading in the past-session viewer (2026-10-14):
/// the set containers draw red with red text and are inert — the deletion is
/// a fact being shown, and the exercise-level Restore is the way back — and
/// the trash button stands on its own, lit while there is something in it
/// and grey while not.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required bool deleted,
    bool readOnly = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionSetRow(
          mode: SetRowMode.history,
          exerciseId: 'ex1',
          displayIndex: 1,
          isDraft: false,
          initialWeightText: '40',
          initialRepsText: '5',
          initialVariationId: null,
          hasNotes: false,
          deleted: deleted,
          readOnly: readOnly,
          onCommit: (_, _, {bool immediate = false}) async {},
          onVariationChanged: (_) {},
          onNotesSave: (_) {},
          onDelete: () async {},
          onDuplicate: (_) {},
          variationOptions: [
            DropdownOption<String?>(label: 'No Variation', value: null),
          ],
          allVariations: const [],
          findSimilarVariations: (_) => const [],
          submitNewVariation:
              (_, {required String exerciseId, String? useExistingId}) async =>
                  null,
        ),
      ),
    ),
  );

  /// The set container's own decoration, found by the fill it wears — the
  /// row's chrome among the several Containers a text field draws.
  BoxDecoration? decorationFilled(WidgetTester tester, Color fill) {
    for (final c in tester.widgetList<Container>(
      find.descendant(
        of: find.byType(SessionSetRow),
        matching: find.byType(Container),
      ),
    )) {
      final d = c.decoration;
      if (d is BoxDecoration && d.color == fill) return d;
    }
    return null;
  }

  Color? cellColor(WidgetTester tester, String text) => tester
      .widget<TextField>(
        find.ancestor(of: find.text(text), matching: find.byType(TextField)),
      )
      .style
      ?.color;

  testWidgets('a deleted row draws the danger treatment — container and '
      'text', (tester) async {
    await pumpRow(tester, deleted: true);

    final decoration = decorationFilled(tester, AppColors.dangerBg);
    expect(decoration, isNotNull, reason: 'the container fill');
    final edge = (decoration!.border! as Border).top;
    expect(edge.color, AppColors.danger, reason: 'the container edge');
    expect(
      edge.width,
      1.2,
      reason:
          'the shared deletedBox recipe — the exercise selector\'s '
          'deleted name wears the same fill, edge and width',
    );
    expect(
      cellColor(tester, '5'),
      AppColors.danger,
      reason: 'the values read red too — the deletion is the row',
    );
    expect(cellColor(tester, '40'), AppColors.danger);
  });

  testWidgets('an ordinary row keeps its neutral surface', (tester) async {
    await pumpRow(tester, deleted: false);

    expect(
      decorationFilled(tester, AppColors.surfaceHigh),
      isNotNull,
      reason: 'the row sits on the card tier, as every row does',
    );
    expect(decorationFilled(tester, AppColors.dangerBg), isNull);
    expect(cellColor(tester, '5'), AppColors.primary);
  });

  testWidgets('a deleted row is inert even in edit mode — no duplicate or '
      'delete drawer', (tester) async {
    // The deletion is shown, not acted on: the way back is the exercise's
    // Restore button, and a dead swipe would suggest otherwise. The note
    // drawer (a read-only look at what the set said) still appears, as it
    // does for every read-only row.
    await pumpRow(tester, deleted: true, readOnly: false);

    final swipe = tester.widget<SwipeActions>(find.byType(SwipeActions));
    final icons = [for (final a in swipe.actions) a.icon];
    expect(icons, [
      Icons.sticky_note_2_outlined,
    ], reason: 'note only — never duplicate or delete');
  });

  testWidgets('the trash button stands alone, greyed while empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DeletedExercisesButton(
              deletedExercises: const [],
              onPickDeletedExercise: (_) {},
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.restore_from_trash));
    expect(
      icon.color,
      AppColors.muted,
      reason: 'nothing to work through — the slot waits greyed',
    );
    await tester.tap(find.byIcon(Icons.restore_from_trash));
    await tester.pumpAndSettle();
    expect(find.byType(MenuPopover), findsNothing);
  });

  testWidgets('the trash menu reports the row and wears the requested '
      'glyph — the viewer\'s eye', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DeletedExercisesButton(
              deletedExercises: const ['Bench Press', 'Back Squat'],
              rowIcon: Icons.visibility_outlined,
              onPickDeletedExercise: picked.add,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.restore_from_trash)).color,
      AppColors.primary,
      reason: 'there is something in the slot — it lights',
    );

    await tester.tap(find.byIcon(Icons.restore_from_trash));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);

    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();
    expect(
      picked,
      [1],
      reason:
          'the row tapped reports its own index — the live screen '
          'restores on it, the viewer views',
    );
    expect(
      find.byIcon(Icons.visibility_outlined),
      findsNWidgets(2),
      reason: 'each row wears the glyph the caller asked for',
    );
  });
}
