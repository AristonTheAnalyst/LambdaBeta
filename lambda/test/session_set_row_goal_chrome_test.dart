import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// The goal chrome on a set row (2026-10-20): the set that achieved a goal
/// fills green with a green outline and badges `G` where a PR badges `PR`.
/// A set that is BOTH draws as the goal — one chrome, one badge — while the
/// PR still counts everywhere PRs are counted, which is exactly why the row
/// keeps [SessionSetRow.isPr] true and only the DRAWING defers.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    bool isGoal = false,
    bool isPr = false,
    bool deleted = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSetRow(
            mode: SetRowMode.history,
            exerciseId: 'ex1',
            displayIndex: 1,
            isDraft: false,
            initialWeightText: '100',
            initialRepsText: '5',
            initialVariationId: null,
            hasNotes: false,
            isPr: isPr,
            isGoal: isGoal,
            deleted: deleted,
            readOnly: true,
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
                (
                  _, {
                  required String exerciseId,
                  String? useExistingId,
                }) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The container the row's chrome is drawn on — the only one on the screen
  /// filled with [fill].
  BoxDecoration rowDecoration(WidgetTester tester, Color fill) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == fill,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('a goal set fills green, outlines green, and badges G', (
    tester,
  ) async {
    await pumpRow(tester, isGoal: true);

    final decoration = rowDecoration(tester, AppColors.successBg);
    expect((decoration.border! as Border).top.color, AppColors.success);
    expect(find.byKey(const ValueKey('goal')), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr')), findsNothing);
  });

  testWidgets('a PR set keeps the accent chrome when no goal met it', (
    tester,
  ) async {
    await pumpRow(tester, isPr: true);

    final decoration = rowDecoration(tester, AppColors.accentBg);
    expect((decoration.border! as Border).top.color, AppColors.accent);
    expect(find.byKey(const ValueKey('pr')), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
  });

  testWidgets('a set that is both draws as the goal, and badges G not PR', (
    tester,
  ) async {
    await pumpRow(tester, isGoal: true, isPr: true);

    rowDecoration(tester, AppColors.successBg); // goal fill, not accent
    expect(find.byKey(const ValueKey('goal')), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr')), findsNothing);
    expect(find.text('PR'), findsNothing);
  });

  testWidgets('a deleted row outranks the goal chrome — red, inert, numbered', (
    tester,
  ) async {
    await pumpRow(tester, isGoal: true, isPr: true, deleted: true);

    final decoration = rowDecoration(tester, AppColors.dangerBg);
    expect(decoration.border!.top.color, AppColors.danger);
    expect(find.byKey(const ValueKey('goal')), findsNothing);
    expect(find.byKey(const ValueKey('pr')), findsNothing);
    expect(find.byKey(const ValueKey('set-1')), findsOneWidget);
  });
}
