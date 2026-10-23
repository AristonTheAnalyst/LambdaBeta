import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// The planned-value grammar on a live row (2026-10-23):
///
///   empty + target      → the target in `planned` ink — a GUIDE only
///   real value = plan   → `plannedText` ink on a solid `plannedFill` chip
///   real value ≠ plan   → neutral cell, `primary` ink
///
/// and the row itself wears the planned tint only while nothing on it
/// contradicts a parseable target.
void main() {
  PlannedSessionExerciseSet target({
    String? weight,
    String? reps,
    String? variationId,
    String? variationName,
  }) => PlannedSessionExerciseSet(
    plannedSetId: 'ps1',
    plannedExerciseId: 'pe1',
    plannedSessionId: 'pw1',
    userId: 'u1',
    setNumber: 1,
    targetWeight: weight,
    targetReps: reps,
    variationId: variationId,
    variationName: variationName,
  );

  Future<void> pumpRow(
    WidgetTester tester, {
    SetRowMode mode = SetRowMode.live,
    String initialWeightText = '',
    String initialRepsText = '',
    String? initialVariationId,
    bool hasNotes = false,
    bool deleted = false,
    PlannedSessionExerciseSet? plannedTarget,
    Future<void> Function(
      bool isDraft,
      SetRowFieldValues values, {
      bool immediate,
    })?
    onCommit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSetRow(
            mode: mode,
            exerciseId: 'ex1',
            displayIndex: 1,
            isDraft: false,
            initialWeightText: initialWeightText,
            initialRepsText: initialRepsText,
            initialVariationId: initialVariationId,
            hasNotes: hasNotes,
            deleted: deleted,
            plannedTarget: plannedTarget,
            onCommit:
                onCommit ??
                (isDraft, values, {bool immediate = false}) async {},
            onVariationChanged: (_) {},
            onNotesSave: (_) {},
            onDelete: () async {},
            onDuplicate: (_) {},
            variationOptions: [
              const DropdownOption<String?>(label: 'No Variation', value: null),
              const DropdownOption<String?>(label: 'Paused', value: 'v1'),
              const DropdownOption<String?>(label: 'Tempo', value: 'v2'),
            ],
            allVariations: const [],
            findSimilarVariations: (_) => const [],
            submitNewVariation:
                (
                  _, {
                  required String exerciseId,
                  String? useExistingId,
                }) async => null,
          ),
        ),
      ),
    );
  }

  TextField cell(WidgetTester tester, String name, {String m = 'live'}) =>
      tester.widget<TextField>(find.byKey(ValueKey('$m-set-1-$name')));

  Color ink(WidgetTester tester, String name, {String m = 'live'}) =>
      cell(tester, name, m: m).style!.color!;

  Color fill(WidgetTester tester, String name, {String m = 'live'}) =>
      cell(tester, name, m: m).decoration!.fillColor!;

  Color edge(WidgetTester tester, String name, {String m = 'live'}) =>
      ((cell(tester, name, m: m).decoration!.enabledBorder!
                  as OutlineInputBorder)
              .borderSide
              .color);

  Color hintInk(WidgetTester tester, String name, {String m = 'live'}) =>
      cell(tester, name, m: m).decoration!.hintStyle!.color!;

  BoxDecoration row(WidgetTester tester, {String m = 'live'}) =>
      tester
              .widget<Container>(
                find.byKey(ValueKey('session-set-row-$m-set-1')),
              )
              .decoration!
          as BoxDecoration;

  /// The chip's three signals: white ink, the solid fill, the planned edge.
  void expectChip(WidgetTester tester, String name, {String m = 'live'}) {
    expect(
      fill(tester, name, m: m),
      AppColors.plannedFill,
      reason: '$name fill',
    );
    expect(ink(tester, name, m: m), AppColors.plannedText, reason: '$name ink');
    expect(edge(tester, name, m: m), AppColors.planned, reason: '$name edge');
  }

  void expectPlainCell(WidgetTester tester, String name, {String m = 'live'}) {
    expect(fill(tester, name, m: m), AppColors.bg, reason: '$name fill');
    expect(ink(tester, name, m: m), AppColors.primary, reason: '$name ink');
    expect(edge(tester, name, m: m), AppColors.border, reason: '$name edge');
  }

  void expectPlannedRow(WidgetTester tester, {String m = 'live'}) {
    expect(row(tester, m: m).color, AppColors.plannedBg);
    expect(
      (row(tester, m: m).border! as Border).top.color,
      AppColors.planned.withValues(alpha: 0.35),
    );
  }

  void expectNeutralRow(WidgetTester tester, {String m = 'live'}) {
    expect(row(tester, m: m).color, AppColors.surfaceHigh);
    expect((row(tester, m: m).border! as Border).top.color, AppColors.border);
  }

  Future<void> typeInto(WidgetTester tester, String cellName, String text) async {
    await tester.enterText(find.byKey(ValueKey('live-set-1-$cellName')), text);
    await tester.pump();
  }

  testWidgets(
    'an adopted weight chips; the planned reps stay a blue guide',
    (tester) async {
      // Start wrote the plan's 60 as the real weight; reps were never
      // adopted — "8-12" is still only a suggestion on screen.
      await pumpRow(
        tester,
        initialWeightText: '60',
        plannedTarget: target(weight: '60', reps: '8-12'),
      );

      expectChip(tester, 'kg');
      expectPlainCell(tester, 'reps');
      expect(cell(tester, 'reps').decoration!.hintText, '8-12');
      expect(hintInk(tester, 'reps'), AppColors.planned);
      expectPlannedRow(tester);
    },
  );

  testWidgets('a rep count inside the range chips and keeps the row blue', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    await typeInto(tester, 'reps', '9');

    expectChip(tester, 'reps');
    expectChip(tester, 'kg');
    expectPlannedRow(tester);
  });

  testWidgets('a rep count outside the range retires the chip and the row', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    await typeInto(tester, 'reps', '15');

    expectPlainCell(tester, 'reps');
    expectChip(tester, 'kg');
    expectNeutralRow(tester);
  });

  testWidgets('a weight off the plan retires the chip and the row', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    await typeInto(tester, 'kg', '65');

    expectPlainCell(tester, 'kg');
    expectNeutralRow(tester);
  });

  testWidgets('reverting to the planned weight chips again and supersedes '
      'the stale write', (tester) async {
    final commits = <String?>[];
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(weight: '60', reps: '8-12'),
      onCommit: (isDraft, values, {bool immediate = false}) async {
        commits.add(values.weight);
      },
    );

    await typeInto(tester, 'kg', '65');
    await typeInto(tester, 'kg', '60');

    expectChip(tester, 'kg');
    expectPlannedRow(tester);
    expect(
      commits,
      ['65', '60'],
      reason:
          'typing back over the seed inside the settle window must still '
          'commit 60 — the stale 65 may not land behind a field reading 60',
    );
  });

  testWidgets('clearing the weight brings the plan back as a blue guide', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    await typeInto(tester, 'kg', '');

    expectPlainCell(tester, 'kg');
    expect(cell(tester, 'kg').decoration!.hintText, '60');
    expect(
      hintInk(tester, 'kg'),
      AppColors.planned,
      reason: 'the target is back to being a guide',
    );
    expectPlannedRow(tester);
  });

  testWidgets('a planned weight range never chips but keeps the row blue', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '65',
      plannedTarget: target(weight: '60-70', reps: '8-12'),
    );

    expectPlainCell(tester, 'kg');
    expectPlannedRow(tester);
  });

  testWidgets('a type beyond a planned weight range goes neutral', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '75',
      plannedTarget: target(weight: '60-70', reps: '8-12'),
    );

    expectPlainCell(tester, 'kg');
    expectNeutralRow(tester);
  });

  testWidgets('AMRAP constrains nothing — no chip, row stays blue', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '100',
      plannedTarget: target(weight: '100', reps: 'AMRAP'),
    );

    expectChip(tester, 'kg');

    await typeInto(tester, 'reps', '9');

    expectPlainCell(tester, 'reps');
    expectPlannedRow(tester);
  });

  testWidgets('a note never retires the row tint', (tester) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      hasNotes: true,
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    expectPlannedRow(tester);
  });

  testWidgets('a variation off the plan retires the row tint', (tester) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      initialVariationId: 'v2',
      plannedTarget: target(weight: '60', reps: '8-12', variationId: 'v1'),
    );

    expectNeutralRow(tester);
  });

  testWidgets('the planned variation keeps the tint', (tester) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      initialVariationId: 'v1',
      plannedTarget: target(weight: '60', reps: '8-12', variationId: 'v1'),
    );

    expectPlannedRow(tester);
  });

  testWidgets('a planned variation reads as a REAL value, not a guide', (
    tester,
  ) async {
    // A variation is categorical, not a target: the plan names the one the
    // set is performed with, so the cell draws it in the value ink even
    // before the row's first commit adopts it (2026-10-23). The guide blue
    // belongs to the kg/reps targets alone.
    await pumpRow(
      tester,
      initialWeightText: '60',
      plannedTarget: target(
        weight: '60',
        reps: '8-12',
        variationId: 'v1',
        variationName: 'Paused',
      ),
    );

    expect(
      tester.widget<Text>(find.text('Paused')).style!.color,
      AppColors.primary,
      reason:
          'a planned variation is the row\'s real value, never a guide — '
          'blue would say it is a suggestion to reach',
    );
    expectPlannedRow(tester);
  });

  testWidgets('a deleted row is one red surface and never chips', (
    tester,
  ) async {
    await pumpRow(
      tester,
      initialWeightText: '60',
      deleted: true,
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    expect(fill(tester, 'kg'), Colors.transparent);
    expect(ink(tester, 'kg'), AppColors.danger);
    expect((row(tester).border! as Border).top.color, AppColors.danger);
  });

  testWidgets('a deleted row still shows the plan as guides in its empty '
      'cells', (tester) async {
    // Deleting an exercise never erases what it was meant to do (2026-10-23):
    // an empty cell draws the target in the guide ink, and the plan's
    // variation shows in the same ink. The row stays one red surface — the
    // guide never becomes a chip.
    await pumpRow(
      tester,
      deleted: true,
      plannedTarget: target(
        weight: '60-70',
        reps: '8-12',
        variationId: 'v1',
        variationName: 'Paused',
      ),
    );

    expect(cell(tester, 'kg').decoration!.hintText, '60-70');
    expect(cell(tester, 'reps').decoration!.hintText, '8-12');
    expect(
      hintInk(tester, 'kg'),
      AppColors.planned,
      reason: 'the target is the guide, even on the red surface',
    );
    expect(
      fill(tester, 'kg'),
      Colors.transparent,
      reason: 'an empty cell is never a chip',
    );
    expect(ink(tester, 'kg'), AppColors.danger);
    expect(
      tester.widget<Text>(find.text('Paused')).style!.color,
      AppColors.planned,
      reason: 'the plan\'s variation is a guide too',
    );
  });

  testWidgets('only the live row chips — a planned-mode row never does', (
    tester,
  ) async {
    // The planner's fields ARE the targets; a target being numerically equal
    // to itself is not the "logged the plan" fact the chip speaks.
    await pumpRow(
      tester,
      mode: SetRowMode.planned,
      initialWeightText: '60',
      initialRepsText: '8-12',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    expectPlainCell(tester, 'kg', m: 'planned');
    expectPlainCell(tester, 'reps', m: 'planned');
    expectPlannedRow(tester, m: 'planned');
  });

  testWidgets('a history-mode row never chips', (tester) async {
    await pumpRow(
      tester,
      mode: SetRowMode.history,
      initialWeightText: '60',
      initialRepsText: '9',
      plannedTarget: target(weight: '60', reps: '8-12'),
    );

    expectPlainCell(tester, 'kg', m: 'history');
    expectPlainCell(tester, 'reps', m: 'history');
    expectNeutralRow(tester, m: 'history');
  });
}
