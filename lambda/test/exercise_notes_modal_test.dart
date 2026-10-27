import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/exercise_note.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/features/session/view/exercise_notes_modal.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/readable_text.dart';

/// In-memory fake of [ExerciseNoteRepository] so the modal can be driven in a widget
/// test without PowerSync. Tracks the same invariants the real repo enforces
/// (exclusive pin per exercise, soft-delete via is_active).
class FakeExerciseNoteRepo implements ExerciseNoteRepository {
  final List<ExerciseNote> notes = [];
  int _calls = 0;

  @override
  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async =>
      List.of(notes);

  @override
  Future<Map<String, List<ExerciseNote>>> fetchNotesForExercises(
    String userId,
    List<String> exerciseIds,
  ) async => {};

  @override
  Future<ExerciseNote> createNote(
    String userId,
    String exerciseId,
    String text, {
    String? sessionId,
  }) async {
    final note = ExerciseNote(
      exerciseNoteId: 'l${++_calls}',
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: DateTime(2026, 1, _calls),
    );
    notes.add(note);
    return note;
  }

  @override
  Future<void> setPinned(
    String userId,
    String exerciseId,
    String exerciseNoteId,
    bool pinned,
  ) async {
    if (pinned) {
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].exerciseId == exerciseId) {
          notes[i] = _with(notes[i], pinned: false);
        }
      }
    }
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].exerciseNoteId == exerciseNoteId) {
        notes[i] = _with(notes[i], pinned: pinned);
      }
    }
  }

  @override
  Future<void> deleteNote(String exerciseNoteId) async {
    notes.removeWhere((l) => l.exerciseNoteId == exerciseNoteId);
  }

  @override
  Future<void> updateNote(
    String userId,
    String exerciseId,
    String exerciseNoteId,
    String text,
  ) async {
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].exerciseNoteId == exerciseNoteId) {
        notes[i] = _with(notes[i], text: text);
      }
    }
  }

  ExerciseNote _with(ExerciseNote l, {bool? pinned, String? text}) => ExerciseNote(
    exerciseNoteId: l.exerciseNoteId,
    userId: l.userId,
    exerciseId: l.exerciseId,
    text: text ?? l.text,
    pinned: pinned ?? l.pinned,
    createdDate: l.createdDate,
    sessionId: l.sessionId,
  );
}

/// The label a [Semantics] widget declares, read off the widget rather than a
/// formed semantics node — a lone annotation that opens no node of its own is
/// still a label the screen reader reaches.
bool _hasSemanticsLabel(WidgetTester tester, String label) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .any((s) => s.properties.label == label);

void main() {
  final repo = FakeExerciseNoteRepo();
  final listenable = ValueNotifier(0);
  final exerciseId = 'ex1';

  Future<void> addNote(String text) async {
    await repo.createNote('u1', exerciseId, text);
    listenable.value++;
  }

  Widget buildModal({
    String? sessionId,
    DateTime? sessionStartedAt,
    bool readOnly = false,
    DateTime? sinceLastReviewAt,
  }) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            child: const Text('open'),
            onPressed: () => showExerciseNotesModal(
              context,
              listenable: listenable,
              notesFor: (_) => List.of(repo.notes),
              loadNotesFor: (_) async {},
              addNote: (_, text) => addNote(text),
              toggleNotePin: (_, exerciseNoteId) async {
                await repo.setPinned(
                  'u1',
                  exerciseId,
                  exerciseNoteId,
                  !repo.notes
                      .firstWhere((l) => l.exerciseNoteId == exerciseNoteId)
                      .pinned,
                );
                listenable.value++;
              },
              deleteNote: (_, exerciseNoteId) async {
                await repo.deleteNote(exerciseNoteId);
                listenable.value++;
              },
              updateNote: (_, exerciseNoteId, text) async {
                await repo.updateNote('u1', exerciseId, exerciseNoteId, text);
                listenable.value++;
              },
              exerciseId: exerciseId,
              exerciseName: 'Test Exercise',
              sessionId: sessionId,
              sessionStartedAt: sessionStartedAt,
              readOnly: readOnly,
              sinceLastReviewAt: sinceLastReviewAt,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('pin clears other pins but never deletes the note', (
    tester,
  ) async {
    await addNote('note one');
    await addNote('note two');
    expect(repo.notes.length, 2, reason: 'both notes should be added');

    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // The modal shows both notes.
    expect(find.text('note one'), findsOneWidget);
    expect(find.text('note two'), findsOneWidget);

    // Pin "note two" via the pin button inside its row, regardless of the
    // modal's sort order.
    expect(find.byIcon(Icons.push_pin), findsNWidgets(2));
    final twoRow = find
        .ancestor(of: find.text('note two'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: twoRow, matching: find.byIcon(Icons.push_pin)),
    );
    await tester.pumpAndSettle();

    // Exclusive pin: note two pinned, note one unpinned — NOT deleted.
    final one = repo.notes.firstWhere((l) => l.text == 'note one');
    final two = repo.notes.firstWhere((l) => l.text == 'note two');
    expect(
      one.pinned,
      isFalse,
      reason:
          'pinning another must not delete/unpin-affect the first except clearing its pin',
    );
    expect(two.pinned, isTrue, reason: 'pinned note should be pinned');
    expect(
      repo.notes.length,
      2,
      reason: 'pinning must never delete a note',
    );
  });

  testWidgets(
    'tapping a note opens the inline editor and saves the new text',
    (tester) async {
      repo.notes.clear(); // isolate from the pin test's notes
      await addNote('note one');
      await tester.pumpWidget(buildModal());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text('note one'), findsOneWidget);

      // Tap the note text → inline editor prefilled with the current text.
      await tester.tap(find.text('note one'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('note one'),
        findsOneWidget,
        reason: 'editor should be prefilled with the note text',
      );

      // Save an edit → the row shows the new text, no stale copy remains.
      await tester.enterText(find.byType(TextField), 'note one (edited)');
      // Save's enabled state is derived from the text, so the frame a real
      // keystroke would paint has to happen before the tap lands.
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.notes.single.text, 'note one (edited)');
      expect(find.text('note one (edited)'), findsOneWidget);
      expect(find.text('note one'), findsNothing);
    },
  );

  testWidgets('Save stays inert until the note text differs', (tester) async {
    repo.notes.clear();
    await addNote('note one');
    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('note one'));
    await tester.pumpAndSettle();

    // Untouched → Save has nothing to write, so tapping it does nothing and
    // the editor stays open.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.notes.single.text, 'note one');
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'an inert Save must leave the editor open',
    );

    // Retyping the same words is still not a change.
    await tester.enterText(find.byType(TextField), 'note one');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.notes.single.text, 'note one');

    // A real difference writes.
    await tester.enterText(find.byType(TextField), 'note two');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.notes.single.text, 'note two');
  });

  testWidgets('a past session reads newest first — after it, its own date, '
      'then previously', (tester) async {
    repo.notes
      ..clear()
      ..addAll([
        ExerciseNote(
          exerciseNoteId: 'l-old',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Old cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 18),
          sessionId: 'prev',
        ),
        ExerciseNote(
          exerciseNoteId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        // Written two days after the record on the desk: not "previously"
        // (2026-10-23).
        ExerciseNote(
          exerciseNoteId: 'l-later',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Later cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 22),
          sessionId: 'next',
        ),
      ]);

    // A tall stage so all three groups lay out inside the fixed sheet.
    tester.view.physicalSize = const Size(1206, 5622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildModal(sessionId: 'w1', sessionStartedAt: DateTime(2026, 10, 20, 9)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('AFTER'), findsOneWidget);
    // A record's middle shelf is dated — it is not the reader's session.
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('THIS SESSION'), findsNothing);
    expect(find.text('PREVIOUSLY'), findsOneWidget);

    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously), reason: 'before and after never mix');

    expect(
      tester.getTopLeft(find.text('Later cue')).dy,
      greaterThan(after),
      reason: 'a note written after the record read is not "previously"',
    );
    expect(tester.getTopLeft(find.text('Later cue')).dy, lessThan(middle));
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      greaterThan(middle),
    );
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      lessThan(previously),
    );
    expect(tester.getTopLeft(find.text('Old cue')).dy, greaterThan(previously));
  });

  // ── Since last review (2026-10-26) ───────────────────────────────────────
  // A checkpoint behind the record splits the after-group: the notes
  // written since the last pass lead the sheet, and the ones written after
  // the session but no later than it keep `AFTER`.
  testWidgets('a review checkpoint splits the after-group', (tester) async {
    repo.notes
      ..clear()
      ..addAll([
        ExerciseNote(
          exerciseNoteId: 'l-old',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Old cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 18),
        ),
        ExerciseNote(
          exerciseNoteId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        // After the record on the desk, before the last review closed.
        ExerciseNote(
          exerciseNoteId: 'l-after',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue before the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 21),
        ),
        // After the last review closed — the pass's own window.
        ExerciseNote(
          exerciseNoteId: 'l-since',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue since the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 25),
        ),
      ]);

    // A tall stage so all four groups lay out inside the fixed sheet.
    tester.view.physicalSize = const Size(1206, 5622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildModal(
        sessionId: 'w1',
        sessionStartedAt: DateTime(2026, 10, 20, 9),
        sinceLastReviewAt: DateTime(2026, 10, 22),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('SINCE LAST REVIEW'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);

    final since = tester.getTopLeft(find.text('SINCE LAST REVIEW')).dy;
    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(since, lessThan(after), reason: 'the newer half leads the sheet');
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously));

    final sinceCue = tester.getTopLeft(find.text('Cue since the pass')).dy;
    final afterCue = tester.getTopLeft(find.text('Cue before the pass')).dy;
    expect(sinceCue, greaterThan(since));
    expect(sinceCue, lessThan(after));
    expect(afterCue, greaterThan(after));
    expect(afterCue, lessThan(middle));
  });

  testWidgets('without a checkpoint the three shelves stand', (tester) async {
    repo.notes
      ..clear()
      ..addAll([
        ExerciseNote(
          exerciseNoteId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        ExerciseNote(
          exerciseNoteId: 'l-since',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue since the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 25),
        ),
      ]);

    tester.view.physicalSize = const Size(1206, 5622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildModal(sessionId: 'w1', sessionStartedAt: DateTime(2026, 10, 20, 9)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('SINCE LAST REVIEW'), findsNothing);
    expect(find.text('AFTER'), findsOneWidget);
  });

  // The planner has no session on the desk (2026-10-26): there is no
  // after-group to split, so the checkpoint divides the whole shelf instead
  // — the pass still leads, and what came at or before it is `PREVIOUSLY`.
  testWidgets('with no session on the desk the checkpoint splits the whole '
      'shelf', (tester) async {
    repo.notes
      ..clear()
      ..addAll([
        ExerciseNote(
          exerciseNoteId: 'l-old',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue before the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 18),
        ),
        ExerciseNote(
          exerciseNoteId: 'l-since',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue since the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 25),
        ),
      ]);

    tester.view.physicalSize = const Size(1206, 5622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildModal(sinceLastReviewAt: DateTime(2026, 10, 22)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('SINCE LAST REVIEW'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    expect(
      find.text('AFTER'),
      findsNothing,
      reason: 'a plan has no session for "after the session" to mean',
    );
    expect(
      find.text('This session'),
      findsNothing,
      reason: 'and no session shelf either — the pass is the whole story',
    );

    final since = tester.getTopLeft(find.text('SINCE LAST REVIEW')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(since, lessThan(previously));
    expect(
      tester.getTopLeft(find.text('Cue since the pass')).dy,
      inExclusiveRange(since, previously),
    );
    expect(
      tester.getTopLeft(find.text('Cue before the pass')).dy,
      greaterThan(previously),
    );
  });

  testWidgets('the modal draws readable ink and type', (tester) async {
    await addNote('note one');
    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expectReadableText(tester, find.byType(MaterialApp));
  });

  // ── A friend's record (2026-10-23) ───────────────────────────────────────
  // The shelves read exactly as always — the notes are somebody else's, so
  // every write affordance is gone: no composer, no pin, no delete drawer,
  // no tap-to-edit.
  testWidgets('read-only: the shelves draw, the write affordances do not', (
    tester,
  ) async {
    repo.notes
      ..clear()
      ..addAll([
        ExerciseNote(
          exerciseNoteId: 'l-pin',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Pinned cue',
          pinned: true,
          createdDate: DateTime(2026, 10, 20),
        ),
        ExerciseNote(
          exerciseNoteId: 'l-plain',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Plain cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 19),
        ),
      ]);

    await tester.pumpWidget(buildModal(readOnly: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // The notes are all there.
    expect(find.text('Pinned cue'), findsOneWidget);
    expect(find.text('Plain cue'), findsOneWidget);
    expect(find.text('Exercise Notes'), findsOneWidget);

    // No composer.
    expect(_hasSemanticsLabel(tester, 'Add exercise note'), isFalse);
    expect(
      find.text('Save Note'),
      findsNothing,
      reason: 'a friend\'s notes are read, never added to',
    );

    // No swipe drawer, and no tap-to-edit — tapping the text stays a read.
    expect(find.byType(SwipeActions), findsNothing);
    await tester.tap(find.text('Plain cue'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // The pin shows its state instead of offering the action (accessibility
    // §5: no action to announce — the glyph reads what the note is). Tapping
    // it is inert, so the state stays the record's.
    expect(_hasSemanticsLabel(tester, 'Pinned note'), isTrue);
    expect(_hasSemanticsLabel(tester, 'Unpinned note'), isTrue);
    expect(_hasSemanticsLabel(tester, 'Unpin note'), isFalse);
    expect(_hasSemanticsLabel(tester, 'Pin note'), isFalse);
    final plainRow = find
        .ancestor(of: find.text('Plain cue'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: plainRow, matching: find.byIcon(Icons.push_pin)),
    );
    await tester.pumpAndSettle();
    expect(
      repo.notes.firstWhere((l) => l.text == 'Plain cue').pinned,
      isFalse,
      reason: 'a friend\'s note cannot be pinned',
    );

    // And nothing wrote.
    expect(repo.notes.length, 2);
    expect(
      repo.notes.firstWhere((l) => l.text == 'Plain cue').pinned,
      isFalse,
    );
  });

  testWidgets('read-only empty state does not point at an Add that is not '
      'there', (tester) async {
    repo.notes.clear();
    await tester.pumpWidget(buildModal(readOnly: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('No exercise notes yet.'), findsOneWidget);
    expect(
      find.textContaining('tap Add'),
      findsNothing,
      reason: 'the read-only shelf has no Add to tap',
    );
  });
}
