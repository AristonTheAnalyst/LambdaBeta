import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/exercise_target_picker.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';
import 'package:lambda/shared/widgets/user_name_text.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The variation cell is a full-width field, so the whole cell is the target
/// (2026-10-25). The dropdown's compact row is only as wide as its label and
/// chevron; before, a tap on the empty left or right of the box — either side
/// of the centred name — landed on the box and did nothing.
void main() {
  /// The box the dropdown is drawn in — the nearest Container around it.
  Finder variationBox() => find
      .ancestor(
        of: find.byType(DropdownSelect<String?>),
        matching: find.byType(Container),
      )
      .first;

  Finder rowLabel() => find.descendant(
    of: find.byType(DropdownSelect<String?>),
    matching: find.byType(UserNameText),
  );

  // A short name on purpose: the test font draws every glyph a square, so a
  // long one would fill the cell and leave no empty margin to tap.
  final options = [
    const DropdownOption<String?>(label: 'No Variation', value: null),
    const DropdownOption<String?>(label: 'Ab', value: 'v1'),
  ];

  Future<void> pumpSessionRow(WidgetTester tester, SetRowMode mode) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: SessionSetRow(
                mode: mode,
                exerciseId: 'ex1',
                displayIndex: 1,
                isDraft: false,
                initialWeightText: '100',
                initialRepsText: '5',
                initialVariationId: 'v1',
                hasNotes: false,
                isPr: false,
                isGoal: false,
                deleted: false,
                readOnly: false,
                onCommit: (_, _, {bool immediate = false}) async {},
                onVariationChanged: (_) {},
                onNotesSave: (_) {},
                onDelete: () async {},
                onDuplicate: (_) {},
                variationOptions: options,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A tap in the empty margin of the cell — between its left edge and the
  /// centred name — opens the picker.
  Future<void> tapCellMargin(WidgetTester tester) async {
    final rect = tester.getRect(variationBox());
    final label = tester.getRect(rowLabel());
    expect(
      label.left - rect.left,
      greaterThan(16),
      reason: 'the name is centred, so the cell has a real empty margin',
    );
    await tester.tapAt(rect.centerLeft + const Offset(8, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('a live row opens the picker from the empty left of the cell', (
    tester,
  ) async {
    await pumpSessionRow(tester, SetRowMode.live);
    await tapCellMargin(tester);

    expect(
      find.text('Choose variation'),
      findsOneWidget,
      reason: 'the whole cell is the field, not just the glyphs',
    );
  });

  testWidgets('the viewer edit row does the same', (tester) async {
    await pumpSessionRow(tester, SetRowMode.history);
    await tapCellMargin(tester);

    expect(find.text('Choose variation'), findsOneWidget);
  });

  testWidgets('the stretched row still centres its label and chevron', (
    tester,
  ) async {
    await pumpSessionRow(tester, SetRowMode.live);

    final box = tester.getRect(variationBox());
    final label = tester.getRect(rowLabel());
    final chevron = tester.getRect(
      find.descendant(
        of: find.byType(DropdownSelect<String?>),
        matching: find.byIcon(LucideIcons.chevronDown),
      ),
    );

    final groupCenter = (label.left + chevron.right) / 2;
    expect(
      (groupCenter - box.center.dx).abs(),
      lessThan(1.5),
      reason: 'stretching the field must not push its contents to an edge',
    );
  });

  testWidgets('the goal picker’s variation cell is the same field', (
    tester,
  ) async {
    final draft = ExerciseTargetDraft()
      ..exerciseId = 'ex1'
      ..variationId = 'v1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ExerciseTargetPicker(
              detailMap: {
                'ex1': ExerciseDetail(
                  exercise: CustomExercise(
                    exerciseId: 'ex1',
                    userId: 'u1',
                    name: 'Benchpress',
                  ),
                ),
              },
              variations: const [
                CustomVariation(
                  variationId: 'v1',
                  userId: 'u1',
                  name: 'Ab',
                ),
              ],
              draft: draft,
              onAdd: (_) async {},
              showNotes: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapCellMargin(tester);

    expect(find.text('Choose variation'), findsOneWidget);
  });
}
