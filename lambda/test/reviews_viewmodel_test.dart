import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/reviews/viewmodel/reviews_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// The Reviews tab's two jobs: list the user's reviews with the open one
/// reachable, and open a pass correctly — starting writes the row over the
/// picked set and goals; resuming writes nothing.
///
/// The fakes make "nothing was written" assertable rather than merely
/// unobservable: `beginReview` is recorded when called and unexercised
/// repository members throw, so a resume that reached for an insert would
/// surface as a failed resume instead of a silent second row.
void main() {
  late FakeProgramHistoryRepository history;
  late FakePlannedSessions planned;
  late FakeProgramRepository programs;
  late FakeExercises exercises;

  ProgramReview review({
    String id = 'r1',
    String? programId,
    String? sessionIdsJson = '["s1"]',
    String? goalIdsJson,
    String? title,
    DateTime? completedDate,
    String outcome = kOutcomeReviewed,
    Map<String, DateTime> reviewed = const {},
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    programId: programId,
    sessionIdsJson: sessionIdsJson,
    goalIdsJson: goalIdsJson,
    title: title,
    kind: kReviewKindReview,
    outcome: completedDate == null ? null : outcome,
    completedDate: completedDate,
    reviewedSessionsJson: reviewed.isEmpty
        ? null
        : jsonEncode({
            for (final e in reviewed.entries)
              e.key: e.value.toIso8601String(),
          }),
    createdDate: DateTime(2026, 1, 1),
  );

  PlannedSession workout(String id, String name) =>
      PlannedSession(sessionId: id, userId: 'u1', name: name);

  ReviewsViewModel build() => ReviewsViewModel(
    userId: 'u1',
    historyRepository: history,
    plannedRepository: planned,
    programRepository: programs,
    exerciseRepository: exercises,
  );

  setUp(() {
    history = FakeProgramHistoryRepository();
    planned = FakePlannedSessions();
    programs = FakeProgramRepository();
    exercises = FakeExercises();
  });

  test('load pins open reviews first and names every set', () async {
    history.reviews = [
      review(
        id: 'done-new',
        sessionIdsJson: '["s2"]',
        completedDate: DateTime(2026, 2, 5),
      ),
      review(id: 'open', sessionIdsJson: '["s1","s2"]'),
      review(
        id: 'done-old',
        sessionIdsJson: '["s1"]',
        completedDate: DateTime(2026, 2, 1),
      ),
    ];
    planned.reviewableRows = [
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
      (
        session: workout('s2', 'Push'),
        lastLogged: DateTime(2026, 2, 6),
        finished: 0,
        lastReview: null,
      ),
    ];

    final vm = build();
    await vm.load();

    expect(
      [for (final e in vm.state.value.entries) e.review.reviewId],
      ['open', 'done-new', 'done-old'],
    );
    final open = vm.state.value.entries.first;
    expect(open.sessionIds, ['s1', 's2']);
    expect(open.workoutNames, ['Legs', 'Push']);
    expect(open.total, 2);
    expect(open.reviewedCount, 0);
    expect(vm.state.value.open.single.review.reviewId, 'open');
    expect(vm.state.value.completed.length, 2);
  });

  test('an untitled open review is named by its workouts, and ticks count',
      () async {
    history.reviews = [
      review(
        id: 'open',
        sessionIdsJson: '["s1","s2"]',
        reviewed: {'s1': DateTime(2026, 2, 7)},
      ),
    ];
    planned.reviewableRows = [
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
      (
        session: workout('s2', 'Push'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];

    final vm = build();
    await vm.load();

    final entry = vm.state.value.entries.single;
    expect(entry.label, 'Legs · Push');
    expect(entry.reviewedCount, 1);
  });

  test('a program review resolves its set through the program links', () async {
    history.reviews = [
      review(id: 'legacy', programId: 'p1', sessionIdsJson: '["s1","s2"]'),
    ];
    planned.links = [
      PlannedSessionProgram(
        plannedSessionProgramId: 'l1',
        programId: 'p1',
        plannedSessionId: 's1',
        userId: 'u1',
      ),
    ];
    planned.reviewableRows = [
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
      (
        session: workout('s2', 'Push'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];

    final vm = build();
    await vm.load();

    // s2 is not in the program any more, so it drops from the resolved set —
    // the same rule `sessionsIn` applies everywhere.
    expect(vm.state.value.entries.single.sessionIds, ['s1']);
    expect(vm.state.value.entries.single.workoutNames, ['Legs']);
  });

  test('starting a review writes a standalone row over the picked set and '
      'goals', () async {
    history.setCheckpoint = DateTime(2026, 2, 1);

    final started = await build().startReview(
      sessionIds: ['s1', 's2'],
      goalIds: ['g1'],
      title: 'End of block 1',
    );

    final call = history.beginCalls.single;
    expect(call.userId, 'u1');
    expect(call.programId, isNull);
    expect(call.sessionIds, ['s1', 's2']);
    expect(call.goalIds, ['g1']);
    expect(call.title, 'End of block 1');

    expect(started, isNotNull);
    expect(started!.sessionIds, ['s1', 's2']);
    expect(started.sinceDate, DateTime(2026, 2, 1));
    expect(started.achievements, isNull);

    // The window question was asked about the set, not about a program.
    expect(history.setScopes.single, ['s1', 's2']);
  });

  test('a failed start reports the error rather than a half-open pass',
      () async {
    history.failBegin = true;

    final vm = build();
    final started = await vm.startReview(sessionIds: ['s1']);

    expect(started, isNull);
    expect(vm.state.value.error, 'Could not start the review.');
    expect(vm.state.value.entries, isEmpty);
  });

  test('resuming opens the pass that exists without beginning a second one',
      () async {
    history.reviews = [
      review(
        id: 'open',
        sessionIdsJson: '["s1","s2"]',
        goalIdsJson: '["g1"]',
        title: 'Mid block',
      ),
    ];
    history.setCheckpoint = DateTime(2026, 2, 1);

    final vm = build();
    await vm.load();
    final started = await vm.resumeReview(history.reviews.single);

    expect(history.beginCalls, isEmpty);
    expect(history.baselineCalls, ['open']);
    expect(started!.review.reviewId, 'open');
    expect(started.sessionIds, ['s1', 's2']);
    expect(started.sinceDate, DateTime(2026, 2, 1));
  });

  test('the picker is dressed in the loader order, never re-sorted', () async {
    planned.reviewableRows = [
      (
        session: workout('s2', 'Push'),
        lastLogged: DateTime(2026, 2, 6),
        finished: 3,
        lastReview: DateTime(2026, 2, 1),
      ),
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];

    final rows = await build().reviewableWorkouts();

    // The loader's order is the answer's order — the picker never re-sorts —
    // and each row states the loader's count in the one wording the picker
    // and the scope sheet share: with a review to measure from, "since last
    // review"; with none, the plain count.
    expect([for (final r in rows) r.sessionId], ['s2', 's1']);
    expect(rows.first.label, 'Push');
    expect(rows.first.lastLogged, DateTime(2026, 2, 6));
    expect(rows.first.sinceReview, isTrue);
    expect(rows.first.finishedLabel, '3 workouts finished since last review');
    expect(rows.last.sinceReview, isFalse);
    expect(rows.last.finishedLabel, '0 workouts finished');
    expect(rows.last.sinceReviewLabel, 'No reviews yet');
  });

  test('the window line counts the days since the last review', () async {
    // The label underneath the days math, pinned at the boundaries: none at
    // all, today, one day, and the plain count in between.
    planned.reviewableRows = [
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: DateTime.now().subtract(const Duration(days: 12)),
      ),
      (
        session: workout('s2', 'Push'),
        lastLogged: null,
        finished: 0,
        lastReview: DateTime.now(),
      ),
      (
        session: workout('s3', 'Pull'),
        lastLogged: null,
        finished: 0,
        lastReview: DateTime.now().subtract(const Duration(days: 1)),
      ),
      (
        session: workout('s4', 'Arms'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];

    final rows = await build().reviewableWorkouts();

    expect(rows[0].sinceReviewLabel, '12 days since last review');
    expect(rows[1].sinceReviewLabel, 'Last review today');
    expect(rows[2].sinceReviewLabel, '1 day since last review');
    expect(rows[3].sinceReviewLabel, 'No reviews yet');
  });

  test('a reviewable goal is its name and its target, apart', () async {
    // The two halves the rows draw as their own elements — never the joined
    // "name — target" string the library's rows still use (2026-10-10). The
    // name is live-first: the exercise's name now, not the text captured when
    // the goal was written.
    programs.goals = [
      const Goal(
        goalId: 'g1',
        userId: 'u1',
        exerciseId: 'e1',
        text: 'old bench note',
        targetWeight: 100,
        targetReps: 5,
      ),
    ];
    exercises.details = {
      'e1': const ExerciseDetail(
        exercise: CustomExercise(
          exerciseId: 'e1',
          userId: 'u1',
          name: 'Bench Press',
        ),
      ),
    };

    final goals = await build().reviewableGoals();

    expect(goals.single.goalId, 'g1');
    expect(goals.single.exerciseName, 'Bench Press');
    expect(goals.single.target, '100 kg × 5 reps');
  });

  test('cancel deletes the open row and reloads without it', () async {
    history.reviews = [
      review(id: 'open', sessionIdsJson: '["s1"]'),
      review(
        id: 'done',
        sessionIdsJson: '["s2"]',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    planned.reviewableRows = [
      (
        session: workout('s1', 'Legs'),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];

    final vm = build();
    await vm.load();
    expect(vm.state.value.open, hasLength(1));

    final cancelled = await vm.cancelReview('open');

    expect(cancelled, isTrue);
    expect(history.deletedReviews, ['open']);
    // The reload is part of the write's contract: the list shows what the row
    // now is, and the completed sibling is untouched.
    expect(vm.state.value.open, isEmpty);
    expect(
      [for (final e in vm.state.value.entries) e.review.reviewId],
      ['done'],
    );
  });

  test('a failed cancel keeps the row and says so', () async {
    history.reviews = [review(id: 'open', sessionIdsJson: '["s1"]')];

    final vm = build();
    await vm.load();
    history.failDelete = true;

    final cancelled = await vm.cancelReview('open');

    expect(cancelled, isFalse);
    expect(vm.state.value.error, 'Could not cancel the review.');
    expect(vm.state.value.open, hasLength(1));
  });
}
