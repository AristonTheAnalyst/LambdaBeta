import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// The duplicate gesture end-to-end at the row level (2026-10-13): swipe the
/// row, tap the copy icon, and the caller receives the on-screen values —
/// with the on-screen text committed first, so the copy can never carry
/// stale seeds.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required String initialRepsText,
    required List<({bool immediate, String? weight, String? reps})> commits,
    required List<({String? weight, String? reps})> duplicates,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSetRow(
            mode: SetRowMode.live,
            exerciseId: 'ex1',
            displayIndex: 1,
            isDraft: false,
            initialWeightText: '',
            initialRepsText: initialRepsText,
            initialVariationId: null,
            hasNotes: false,
            onCommit: (isDraft, v, {bool immediate = false}) async {
              commits.add((
                immediate: immediate,
                weight: v.weight,
                reps: v.reps,
              ));
            },
            onVariationChanged: (_) {},
            onNotesSave: (_) {},
            onDelete: () async {},
            onDuplicate: (v) {
              duplicates.add((weight: v.weight, reps: v.reps));
            },
            onRegisterCommit: (_) {},
            onUnregisterCommit: (_) {},
            variationOptions: [
              DropdownOption<String?>(label: 'No Variation', value: null),
            ],
            allVariations: const [],
            findSimilarVariations: (_) => const [],
            submitNewVariation: (
              _, {
              required String exerciseId,
              String? useExistingId,
            }) async => null,
          ),
        ),
      ),
    );
  }

  testWidgets('swipe → duplicate carries the typed text, committed first', (
    tester,
  ) async {
    final commits = <({bool immediate, String? weight, String? reps})>[];
    final duplicates = <({String? weight, String? reps})>[];
    await pumpRow(
      tester,
      initialRepsText: '',
      commits: commits,
      duplicates: duplicates,
    );

    // Type a value (debounced commit NOT settled) then duplicate it.
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.pump();

    // Swipe the row left to reveal the drawer — starting from the
    // set-number handle (left edge), never from a text field: the fields
    // claim horizontal drags for cursor movement.
    final rowTopLeft = tester.getTopLeft(find.byType(SessionSetRow));
    final rowCenterY = tester.getCenter(find.byType(SessionSetRow)).dy;
    await tester.dragFrom(
      Offset(rowTopLeft.dx + 20, rowCenterY),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget,
        reason: 'the icon-only drawer shows the duplicate action');
    expect(find.text('Duplicate'), findsNothing,
        reason: 'labels are gone from swipe actions');

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(commits, isNotEmpty,
        reason: 'the on-screen text commits before the copy');
    expect(commits.last.immediate, isTrue,
        reason: 'the pre-copy commit is immediate, not debounced');
    expect(commits.last.reps, '10');
    expect(duplicates, hasLength(1));
    expect(duplicates.single.reps, '10',
        reason: 'the copy carries the text on screen, not the stale seeds');
  });

  testWidgets('an empty live row duplicates as an empty copy', (tester) async {
    final commits = <({bool immediate, String? weight, String? reps})>[];
    final duplicates = <({String? weight, String? reps})>[];
    await pumpRow(
      tester,
      initialRepsText: '',
      commits: commits,
      duplicates: duplicates,
    );

    // Swipe from the set-number handle (left edge) — a drag over the
    // fields is a cursor drag, not a swipe.
    final rowTopLeft = tester.getTopLeft(find.byType(SessionSetRow));
    final rowCenterY = tester.getCenter(find.byType(SessionSetRow)).dy;
    await tester.dragFrom(
      Offset(rowTopLeft.dx + 20, rowCenterY),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(duplicates, hasLength(1),
        reason: 'tapping Duplicate on a row is deliberate intent — an empty '
            'row copies as an empty row (the old guard made the button '
            'silently do nothing on planned ghost rows)');
    expect(duplicates.single.reps, isNull);
    expect(duplicates.single.weight, isNull);
  });
}
