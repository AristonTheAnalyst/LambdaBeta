import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/features/session/view/lessons_modal.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/readable_text.dart';

/// In-memory fake of [LessonRepository] so the modal can be driven in a widget
/// test without PowerSync. Tracks the same invariants the real repo enforces
/// (exclusive pin per exercise, soft-delete via is_active).
class FakeLessonRepo implements LessonRepository {
  final List<Lesson> lessons = [];
  int _calls = 0;

  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      List.of(lessons);

  @override
  Future<Map<String, List<Lesson>>> fetchLessonsForExercises(
    String userId,
    List<String> exerciseIds,
  ) async => {};

  @override
  Future<Lesson> createLesson(
    String userId,
    String exerciseId,
    String text, {
    String? sessionId,
  }) async {
    final lesson = Lesson(
      lessonId: 'l${++_calls}',
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: DateTime(2026, 1, _calls),
    );
    lessons.add(lesson);
    return lesson;
  }

  @override
  Future<void> setPinned(
    String userId,
    String exerciseId,
    String lessonId,
    bool pinned,
  ) async {
    if (pinned) {
      for (var i = 0; i < lessons.length; i++) {
        if (lessons[i].exerciseId == exerciseId) {
          lessons[i] = _with(lessons[i], pinned: false);
        }
      }
    }
    for (var i = 0; i < lessons.length; i++) {
      if (lessons[i].lessonId == lessonId) {
        lessons[i] = _with(lessons[i], pinned: pinned);
      }
    }
  }

  @override
  Future<void> deleteLesson(String lessonId) async {
    lessons.removeWhere((l) => l.lessonId == lessonId);
  }

  @override
  Future<void> updateLesson(
    String userId,
    String exerciseId,
    String lessonId,
    String text,
  ) async {
    for (var i = 0; i < lessons.length; i++) {
      if (lessons[i].lessonId == lessonId) {
        lessons[i] = _with(lessons[i], text: text);
      }
    }
  }

  Lesson _with(Lesson l, {bool? pinned, String? text}) => Lesson(
    lessonId: l.lessonId,
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
  final repo = FakeLessonRepo();
  final listenable = ValueNotifier(0);
  final exerciseId = 'ex1';

  Future<void> addLesson(String text) async {
    await repo.createLesson('u1', exerciseId, text);
    listenable.value++;
  }

  Widget buildModal({
    String? sessionId,
    DateTime? sessionStartedAt,
    bool readOnly = false,
    DateTime? sinceLastReviewAt,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                child: const Text('open'),
                onPressed: () => showLessonsModal(
                  context,
                  listenable: listenable,
                  lessonsFor: (_) => List.of(repo.lessons),
                  loadLessonsFor: (_) async {},
                  addLesson: (_, text) => addLesson(text),
                  toggleLessonPin: (_, lessonId) async {
                    await repo.setPinned(
                      'u1',
                      exerciseId,
                      lessonId,
                      !repo.lessons
                          .firstWhere((l) => l.lessonId == lessonId)
                          .pinned,
                    );
                    listenable.value++;
                  },
                  deleteLesson: (_, lessonId) async {
                    await repo.deleteLesson(lessonId);
                    listenable.value++;
                  },
                  updateLesson: (_, lessonId, text) async {
                    await repo.updateLesson('u1', exerciseId, lessonId, text);
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

  testWidgets('pin clears other pins but never deletes the lesson', (
    tester,
  ) async {
    await addLesson('lesson one');
    await addLesson('lesson two');
    expect(repo.lessons.length, 2, reason: 'both lessons should be added');

    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // The modal shows both lessons.
    expect(find.text('lesson one'), findsOneWidget);
    expect(find.text('lesson two'), findsOneWidget);

    // Pin "lesson two" via the pin button inside its row, regardless of the
    // modal's sort order.
    expect(find.byIcon(Icons.push_pin), findsNWidgets(2));
    final twoRow = find
        .ancestor(of: find.text('lesson two'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: twoRow, matching: find.byIcon(Icons.push_pin)),
    );
    await tester.pumpAndSettle();

    // Exclusive pin: lesson two pinned, lesson one unpinned — NOT deleted.
    final one = repo.lessons.firstWhere((l) => l.text == 'lesson one');
    final two = repo.lessons.firstWhere((l) => l.text == 'lesson two');
    expect(
      one.pinned,
      isFalse,
      reason:
          'pinning another must not delete/unpin-affect the first except clearing its pin',
    );
    expect(two.pinned, isTrue, reason: 'pinned lesson should be pinned');
    expect(
      repo.lessons.length,
      2,
      reason: 'pinning must never delete a lesson',
    );
  });

  testWidgets(
    'tapping a lesson opens the inline editor and saves the new text',
    (tester) async {
      repo.lessons.clear(); // isolate from the pin test's lessons
      await addLesson('lesson one');
      await tester.pumpWidget(buildModal());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text('lesson one'), findsOneWidget);

      // Tap the lesson text → inline editor prefilled with the current text.
      await tester.tap(find.text('lesson one'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('lesson one'),
        findsOneWidget,
        reason: 'editor should be prefilled with the lesson text',
      );

      // Save an edit → the row shows the new text, no stale copy remains.
      await tester.enterText(find.byType(TextField), 'lesson one (edited)');
      // Save's enabled state is derived from the text, so the frame a real
      // keystroke would paint has to happen before the tap lands.
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.lessons.single.text, 'lesson one (edited)');
      expect(find.text('lesson one (edited)'), findsOneWidget);
      expect(find.text('lesson one'), findsNothing);
    },
  );

  testWidgets('Save stays inert until the lesson text differs', (tester) async {
    repo.lessons.clear();
    await addLesson('lesson one');
    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lesson one'));
    await tester.pumpAndSettle();

    // Untouched → Save has nothing to write, so tapping it does nothing and
    // the editor stays open.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.lessons.single.text, 'lesson one');
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'an inert Save must leave the editor open',
    );

    // Retyping the same words is still not a change.
    await tester.enterText(find.byType(TextField), 'lesson one');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.lessons.single.text, 'lesson one');

    // A real difference writes.
    await tester.enterText(find.byType(TextField), 'lesson two');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.lessons.single.text, 'lesson two');
  });

  testWidgets('a past session reads newest first — after it, its own date, '
      'then previously', (tester) async {
    repo.lessons
      ..clear()
      ..addAll([
        Lesson(
          lessonId: 'l-old',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Old cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 18),
          sessionId: 'prev',
        ),
        Lesson(
          lessonId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        // Written two days after the record on the desk: not "previously"
        // (2026-10-23).
        Lesson(
          lessonId: 'l-later',
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
      reason: 'a lesson written after the record read is not "previously"',
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
  // A checkpoint behind the record splits the after-group: the lessons
  // written since the last pass lead the sheet, and the ones written after
  // the session but no later than it keep `AFTER`.
  testWidgets('a review checkpoint splits the after-group', (tester) async {
    repo.lessons
      ..clear()
      ..addAll([
        Lesson(
          lessonId: 'l-old',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Old cue',
          pinned: false,
          createdDate: DateTime(2026, 10, 18),
        ),
        Lesson(
          lessonId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        // After the record on the desk, before the last review closed.
        Lesson(
          lessonId: 'l-after',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Cue before the pass',
          pinned: false,
          createdDate: DateTime(2026, 10, 21),
        ),
        // After the last review closed — the pass's own window.
        Lesson(
          lessonId: 'l-since',
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
    repo.lessons
      ..clear()
      ..addAll([
        Lesson(
          lessonId: 'l-here',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Elbows tucked',
          pinned: false,
          createdDate: DateTime(2026, 10, 20, 12),
          sessionId: 'w1',
        ),
        Lesson(
          lessonId: 'l-since',
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

  testWidgets('the modal draws readable ink and type', (tester) async {
    await addLesson('lesson one');
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
    repo.lessons
      ..clear()
      ..addAll([
        Lesson(
          lessonId: 'l-pin',
          userId: 'u1',
          exerciseId: exerciseId,
          text: 'Pinned cue',
          pinned: true,
          createdDate: DateTime(2026, 10, 20),
        ),
        Lesson(
          lessonId: 'l-plain',
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
      repo.lessons.firstWhere((l) => l.text == 'Plain cue').pinned,
      isFalse,
      reason: 'a friend\'s note cannot be pinned',
    );

    // And nothing wrote.
    expect(repo.lessons.length, 2);
    expect(repo.lessons.firstWhere((l) => l.text == 'Plain cue').pinned, isFalse);
  });

  testWidgets('read-only empty state does not point at an Add that is not '
      'there', (tester) async {
    repo.lessons.clear();
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
