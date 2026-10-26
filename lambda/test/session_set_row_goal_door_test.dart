import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// The goal door on a set row (2026-10-26): a set is where a target comes
/// from, so the row's own swipe drawer carries it — the live grid and a past
/// record alike.
///
/// The tests pin the places the door must NOT appear, because each of them
/// would write a goal nobody asked for: a draft row (nothing committed yet),
/// a deleted row (not performed work), and every surface that passes no
/// callback (a friend's record, the preview). They also pin that the door
/// sits at the leading end of the drawer, so the half-swipe still lands on
/// the two actions the thumb goes to mid-session.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    VoidCallback? onCreateGoal,
    SetRowMode mode = SetRowMode.live,
    bool isDraft = false,
    bool readOnly = false,
    bool deleted = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionSetRow(
          mode: mode,
          exerciseId: 'ex1',
          displayIndex: 1,
          isDraft: isDraft,
          initialWeightText: '100',
          initialRepsText: '3',
          initialVariationId: null,
          hasNotes: false,
          readOnly: readOnly,
          deleted: deleted,
          onCreateGoal: onCreateGoal,
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

  /// Swipe from the number cell — the left edge, never a text field (the
  /// fields claim horizontal drags for cursor movement).
  Future<void> swipeOpen(WidgetTester tester) async {
    final topLeft = tester.getTopLeft(find.byType(SessionSetRow));
    final centerY = tester.getCenter(find.byType(SessionSetRow)).dy;
    await tester.dragFrom(
      Offset(topLeft.dx + 20, centerY),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
  }

  final goalAction = find.byIcon(Icons.track_changes);

  testWidgets('a live row carries the goal door, and it fires', (
    tester,
  ) async {
    var opened = 0;
    await pumpRow(tester, onCreateGoal: () => opened++);
    await swipeOpen(tester);

    expect(goalAction, findsOneWidget);
    await tester.tap(goalAction);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('the door leads the drawer — the half-swipe keeps Note · '
      'Delete', (tester) async {
    await pumpRow(tester, onCreateGoal: () {});
    await swipeOpen(tester);

    expect(
      tester.getCenter(goalAction).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.copy_rounded)).dx),
      reason: 'goal arrives last, after the duplicate and the note',
    );
    expect(
      tester.getCenter(find.byIcon(Icons.sticky_note_2_outlined)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.delete_outline)).dx),
    );
  });

  testWidgets('a draft row has no goal to chase', (tester) async {
    await pumpRow(tester, onCreateGoal: () {}, isDraft: true);
    await swipeOpen(tester);

    expect(goalAction, findsNothing);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
  });

  testWidgets('a deleted row offers no goal — it is not performed work', (
    tester,
  ) async {
    await pumpRow(
      tester,
      onCreateGoal: () {},
      mode: SetRowMode.history,
      readOnly: true,
      deleted: true,
    );
    await swipeOpen(tester);

    expect(goalAction, findsNothing);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
  });

  testWidgets('a past record in view mode carries the door — a record is '
      'where a target comes from', (tester) async {
    var opened = 0;
    await pumpRow(
      tester,
      onCreateGoal: () => opened++,
      mode: SetRowMode.history,
      readOnly: true,
    );
    await swipeOpen(tester);

    expect(goalAction, findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.sticky_note_2_outlined)).dx,
      greaterThan(tester.getCenter(goalAction).dx),
      reason: 'Note is uncovered first — it stays the row\'s first action',
    );
    await tester.tap(goalAction);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('no callback, no door — the preview and a friend\'s record', (
    tester,
  ) async {
    await pumpRow(tester, mode: SetRowMode.history, readOnly: true);
    await swipeOpen(tester);

    expect(goalAction, findsNothing);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
  });
}
