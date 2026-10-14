import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// The commit-class contract the debounce is built on (2026-10-13).
///
/// The row itself does not debounce — it passes each commit through with the
/// `immediate` flag that says which class it belongs to, and the VMs merge
/// the debounce-eligible ones. What is pinned here is that classification:
/// a keystroke commit is debounce-eligible, a blur commit and the registered
/// flush handle are not — the safety net that keeps navigation from ever
/// losing a typed value — and drafts keep their blur-only rule.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required bool isDraft,
    required Future<void> Function(bool isDraft, SetRowFieldValues values, {bool immediate})
        onCommit,
    void Function(Future<void> Function())? onRegister,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSetRow(
            mode: SetRowMode.live,
            exerciseId: 'ex1',
            displayIndex: 1,
            isDraft: isDraft,
            initialWeightText: '',
            initialRepsText: '',
            initialVariationId: null,
            hasNotes: false,
            onCommit: onCommit,
            onVariationChanged: (_) {},
            onNotesSave: (_) {},
            onDelete: () async {},
            onDuplicate: (_) {},
            onRegisterCommit: onRegister,
            onUnregisterCommit: (_) {},
            variationOptions: [
              DropdownOption<String?>(label: 'No Variation', value: null),
            ],
            allVariations: const [],
            findSimilarVariations: (_) => const [],
            submitNewVariation: (_, {required String exerciseId, String? useExistingId}) async => null,
          ),
        ),
      ),
    );
  }

  // The grid order is reps first, then kilos — the first TextField is the
  // REPS cell, which is what these tests type into.
  Finder repsField() => find.byType(TextField).first;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(repsField(), text);
    await tester.pump();
  }

  Future<void> unfocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  testWidgets('keystroke commits carry immediate false, one per keystroke', (
    tester,
  ) async {
    final commits = <({bool immediate, String? reps})>[];
    await pumpRow(
      tester,
      isDraft: false,
      onCommit: (isDraft, v, {bool immediate = false}) async {
        commits.add((immediate: immediate, reps: v.reps));
      },
    );

    await type(tester, '1');
    await type(tester, '10');
    await type(tester, '100');

    // Three keystrokes, three commits, all debounce-eligible — the caller
    // merges them into one write; the row must not decide that itself.
    expect(commits.length, 3);
    expect(commits.map((c) => c.immediate), everyElement(isFalse));
    expect(commits.last.reps, '100');
  });

  testWidgets('blur commits immediately', (tester) async {
    final commits = <({bool immediate, String? reps})>[];
    await pumpRow(
      tester,
      isDraft: false,
      onCommit: (isDraft, v, {bool immediate = false}) async {
        commits.add((immediate: immediate, reps: v.reps));
      },
    );

    await type(tester, '40');
    expect(commits, hasLength(1));
    // Move focus away — the focus-loss listener fires the immediate commit.
    await unfocus(tester);

    expect(commits, hasLength(2));
    expect(commits.last.immediate, isTrue,
        reason: 'blur is the safety net — it must never be debounced');
    expect(commits.last.reps, '40');
  });

  testWidgets('the registered flush handle commits immediately', (tester) async {
    final commits = <({bool immediate, String? reps})>[];
    late Future<void> Function() flush;
    await pumpRow(
      tester,
      isDraft: false,
      onCommit: (isDraft, v, {bool immediate = false}) async {
        commits.add((immediate: immediate, reps: v.reps));
      },
      onRegister: (h) => flush = h,
    );

    await type(tester, '60');
    await flush();
    await tester.pump();

    expect(commits, hasLength(2));
    expect(commits.last.immediate, isTrue,
        reason: 'tab switches, page changes, lifecycle and session end all '
            'flush through this handle — it writes now');
  });

  testWidgets('draft rows still commit only on blur', (tester) async {
    final commits = <({bool immediate, String? reps})>[];
    await pumpRow(
      tester,
      isDraft: true,
      onCommit: (isDraft, v, {bool immediate = false}) async {
        commits.add((immediate: immediate, reps: v.reps));
      },
    );

    await type(tester, '10');
    expect(commits, isEmpty,
        reason: 'a keystroke must not materialize a draft mid-typing');

    await unfocus(tester);
    expect(commits, hasLength(1));
    expect(commits.single.immediate, isTrue);
  });
}
