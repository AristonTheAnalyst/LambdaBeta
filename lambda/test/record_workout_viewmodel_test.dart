import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/features/programs/viewmodel/record_workout_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// One workout's story is every frozen version of it (2026-10-26): the
/// current plan, then each completed review's end (its snapshot) and start
/// (its baseline), newest first. These tests are the rules the reader walks
/// on — what counts as a version, what order they come in, and which one the
/// eye and the marks are read against — with no database and no page.
void main() {
  ContentSet setOf(String weight) => ContentSet(
    plannedSetId: 'ps1',
    plannedExerciseId: 'pe1',
    plannedSessionId: 's1',
    userId: 'u1',
    setNumber: 1,
    targetWeight: weight,
    targetReps: '5',
  );

  ContentSession sessionOf(String weight, {String sessionId = 's1'}) =>
      ContentSession(
        sessionId: sessionId,
        userId: 'u1',
        name: 'Push Day',
        exercises: [
          ContentExercise(
            plannedExerciseId: 'pe1',
            plannedSessionId: sessionId,
            userId: 'u1',
            exerciseId: 'e1',
            exerciseOrder: 0,
            sets: [setOf(weight)],
          ),
        ],
      );

  ProgramContent docOf(String weight, {bool holdsWorkout = true}) =>
      ProgramContent(sessions: holdsWorkout ? [sessionOf(weight)] : const []);

  ProgramReview reviewOf({
    required String id,
    required DateTime started,
    DateTime? completed,
    ProgramContent? baseline,
    ProgramContent? snapshot,
    Map<String, String>? exerciseNotes,
    Map<String, String>? workoutNotes,
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    kind: kReviewKindReview,
    title: 'Pass $id',
    createdDate: started,
    completedDate: completed,
    outcome: completed == null ? null : kOutcomeReviewed,
    baselineContent: baseline?.encode(),
    snapshotContent: snapshot?.encode(),
    exerciseNotesJson: exerciseNotes == null ? null : jsonEncode(exerciseNotes),
    workoutNotesJson: workoutNotes == null ? null : jsonEncode(workoutNotes),
  );

  /// Three completed passes over the same workout, each starting where the
  /// last left off: 70 → 75 → 80 → 85.
  List<ProgramReview> threePasses() => [
    reviewOf(
      id: 'r1',
      started: DateTime(2026, 10, 1),
      completed: DateTime(2026, 10, 2),
      baseline: docOf('70'),
      snapshot: docOf('75'),
    ),
    reviewOf(
      id: 'r2',
      started: DateTime(2026, 10, 5),
      completed: DateTime(2026, 10, 6),
      baseline: docOf('75'),
      snapshot: docOf('80'),
    ),
    reviewOf(
      id: 'r3',
      started: DateTime(2026, 10, 8),
      completed: DateTime(2026, 10, 9),
      baseline: docOf('80'),
      snapshot: docOf('85'),
    ),
  ];

  group('assembleWorkoutVersions', () {
    test('reads newest first: each review\'s end before its own start', () {
      final versions = assembleWorkoutVersions(threePasses(), 's1');

      expect(
        [for (final v in versions) '${v.reviewId}.${v.side.name}'],
        ['r3.end', 'r3.start', 'r2.end', 'r2.start', 'r1.end', 'r1.start'],
      );
      // The values climb down the stack, which is what "newest first" means
      // when the story is progressive: the top of the stack is what stands.
      expect(
        [
          for (final v in versions)
            v.session!.exercises.first.sets.first.targetWeight,
        ],
        ['85', '80', '80', '75', '75', '70'],
      );
      // Each side carries the moment it was taken — the pass began, and the
      // review completed — and the walker is read off exactly this.
      expect(
        [for (final v in versions) v.date],
        [
          DateTime(2026, 10, 9),
          DateTime(2026, 10, 8),
          DateTime(2026, 10, 6),
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 2),
          DateTime(2026, 10, 1),
        ],
      );
    });

    test('a review that never held the workout is no part of its story', () {
      final other = reviewOf(
        id: 'r9',
        started: DateTime(2026, 10, 3),
        completed: DateTime(2026, 10, 4),
        baseline: docOf('1', holdsWorkout: false),
        snapshot: docOf('2', holdsWorkout: false),
      );
      // An open pass holds a baseline but no snapshot: nothing is frozen yet,
      // so nothing of it can be walked.
      final open = reviewOf(
        id: 'open',
        started: DateTime(2026, 10, 7),
        baseline: docOf('80'),
      );

      final versions = assembleWorkoutVersions([
        ...threePasses(),
        other,
        open,
      ], 's1');

      expect(versions, hasLength(6));
      expect(
        versions.map((v) => v.reviewId),
        everyElement(isNot(isIn(['r9', 'open']))),
      );
    });

    test('a workout the pass never found keeps its start, saying so', () {
      // Added after the baseline was taken: the start is a real version of
      // the story — the review's document simply does not hold the workout,
      // which is the start's whole truth.
      final added = reviewOf(
        id: 'r1',
        started: DateTime(2026, 10, 1),
        completed: DateTime(2026, 10, 2),
        baseline: docOf('0', holdsWorkout: false),
        snapshot: docOf('80'),
      );

      final versions = assembleWorkoutVersions([added], 's1');

      expect(versions, hasLength(2));
      expect(versions[1].side, WorkoutVersionSide.start);
      expect(
        versions[1].session,
        isNull,
        reason:
            'the document exists and does not hold the workout — a fact '
            'to say, not a version to drop',
      );
      expect(versions[0].session, isNotNull);
    });

    test('a row with no baseline contributes only its end', () {
      final legacy = reviewOf(
        id: 'r1',
        started: DateTime(2026, 10, 1),
        completed: DateTime(2026, 10, 2),
        snapshot: docOf('80'),
      );

      final versions = assembleWorkoutVersions([legacy], 's1');

      expect(versions, hasLength(1));
      expect(versions.single.side, WorkoutVersionSide.end);
    });

    test('raw date bounds keep the order — a review completed before another '
        'was started still reads newest first', () {
      // The passes are listed out of order on purpose: the read sorts, the
      // caller does not.
      final versions = assembleWorkoutVersions(
        threePasses().reversed.toList(),
        's1',
      );
      expect(versions.first.reviewId, 'r3');
      expect(versions.last.reviewId, 'r1');
    });

    test('notes ride the version the review produced, never its start', () {
      final withNotes = reviewOf(
        id: 'r1',
        started: DateTime(2026, 10, 1),
        completed: DateTime(2026, 10, 2),
        baseline: docOf('70'),
        snapshot: docOf('75'),
        exerciseNotes: const {'pe1': 'Elbows tucked'},
        workoutNotes: const {'s1': 'Moved well'},
      );

      final versions = assembleWorkoutVersions([withNotes], 's1');
      final end = versions.firstWhere((v) => v.side == WorkoutVersionSide.end);
      final start = versions.firstWhere(
        (v) => v.side == WorkoutVersionSide.start,
      );

      expect(end.exerciseNotes, {'pe1': 'Elbows tucked'});
      expect(end.workoutNote, 'Moved well');
      expect(
        start.exerciseNotes,
        isEmpty,
        reason: 'the plan as found had no notes of its own',
      );
      expect(start.workoutNote, isNull);
    });
  });

  group('RecordWorkoutViewModel', () {
    /// The full stack as the reader is handed it: the current plan on top,
    /// then the three passes' six frozen sides.
    List<WorkoutVersion> fullStack() => [
      WorkoutVersion(
        sessionId: 's1',
        side: WorkoutVersionSide.current,
        session: sessionOf('90'),
      ),
      ...assembleWorkoutVersions(threePasses(), 's1'),
    ];

    test('opens on the version it was handed, and the ends of the stack are '
        'inert rather than absent', () {
      // Index 1 is the newest review's end: the plan sits on top of the
      // stack, and the review this page was opened from is just under it.
      final vm = RecordWorkoutViewModel(versions: fullStack(), initialIndex: 1);

      expect(vm.value.version!.reviewId, 'r3');
      expect(vm.value.version!.side, WorkoutVersionSide.end);
      expect(vm.value.canStepNewer, isTrue);
      expect(vm.value.canStepOlder, isTrue);

      // All the way down: the last step lands on the oldest start and stops.
      for (var i = 0; i < 10; i++) {
        vm.stepOlder();
      }
      expect(vm.value.index, 6);
      expect(vm.value.canStepOlder, isFalse);
      expect(vm.value.version!.side, WorkoutVersionSide.start);
      expect(vm.value.version!.reviewId, 'r1');

      // And all the way up: the current plan is the top, and pressing past it
      // moves nothing.
      for (var i = 0; i < 10; i++) {
        vm.stepNewer();
      }
      expect(vm.value.index, 0);
      expect(vm.value.canStepNewer, isFalse);
      expect(vm.value.isCurrent, isTrue);
    });

    test('a negative index is "no record", not a version to draw', () {
      final vm = RecordWorkoutViewModel(
        versions: fullStack(),
        initialIndex: -1,
      );

      expect(vm.value.hasRecord, isFalse);
      expect(vm.value.version, isNull);
      expect(vm.value.canStepOlder, isFalse);
      expect(vm.value.canStepNewer, isFalse);
    });

    test('the eye flips to the other side of the review on screen, and has '
        'nothing to flip on the plan', () {
      final stack = fullStack();
      final vm = RecordWorkoutViewModel(versions: stack, initialIndex: 1);

      expect(vm.value.version!.reviewId, 'r3');
      expect(vm.value.version!.side, WorkoutVersionSide.end);
      expect(vm.value.sibling!.side, WorkoutVersionSide.start);
      expect(vm.value.canFlip, isTrue);

      vm.flip();
      expect(vm.value.index, 2);
      expect(vm.value.version!.side, WorkoutVersionSide.start);
      expect(vm.value.isStart, isTrue);

      vm.flip();
      expect(vm.value.index, 1);
      expect(vm.value.version!.side, WorkoutVersionSide.end);

      // The plan belongs to no review: no pair, no eye, nothing to flip.
      vm.stepNewer();
      expect(vm.value.isCurrent, isTrue);
      expect(vm.value.sibling, isNull);
      expect(vm.value.canFlip, isFalse);
      vm.flip();
      expect(vm.value.isCurrent, isTrue, reason: 'a no-op, not a fallback');
    });

    test('a pair one side does not hold offers no flip — a jump into "not '
        'there" would read as data gone missing', () {
      final stack = [
        WorkoutVersion(
          sessionId: 's1',
          side: WorkoutVersionSide.current,
          session: sessionOf('90'),
        ),
        ...assembleWorkoutVersions([
          reviewOf(
            id: 'r1',
            started: DateTime(2026, 10, 1),
            completed: DateTime(2026, 10, 2),
            baseline: docOf('0', holdsWorkout: false),
            snapshot: docOf('80'),
          ),
        ], 's1'),
      ];
      final vm = RecordWorkoutViewModel(versions: stack, initialIndex: 1);

      expect(vm.value.version!.reviewId, 'r1');
      expect(vm.value.sibling, isNotNull, reason: 'the version is still there');
      expect(vm.value.canFlip, isFalse);
      vm.flip();
      expect(vm.value.index, 1, reason: 'the eye stays put');
    });

    test('the marks read the other side; the plan reads the newest end', () {
      final vm = RecordWorkoutViewModel(versions: fullStack(), initialIndex: 1);

      expect(vm.value.markReference!.side, WorkoutVersionSide.start);
      expect(vm.value.markReference!.reviewId, 'r3');

      vm.flip();
      expect(vm.value.markReference!.side, WorkoutVersionSide.end);
      expect(vm.value.markReference!.reviewId, 'r3');

      // From the start (index 2) the plan is two steps up.
      vm.stepNewer();
      vm.stepNewer();
      expect(vm.value.isCurrent, isTrue);
      expect(
        vm.value.markReference!.reviewId,
        'r3',
        reason: 'the newest record is what the plan has drifted from',
      );
      expect(vm.value.markReference!.side, WorkoutVersionSide.end);
    });

    test('notes read on the version the review produced, not on its start or '
        'the plan', () {
      final withNotes = [
        reviewOf(
          id: 'r1',
          started: DateTime(2026, 10, 1),
          completed: DateTime(2026, 10, 2),
          baseline: docOf('70'),
          snapshot: docOf('75'),
          exerciseNotes: const {'pe1': 'Elbows tucked'},
          workoutNotes: const {'s1': 'Moved well'},
        ),
      ];
      final stack = [
        WorkoutVersion(
          sessionId: 's1',
          side: WorkoutVersionSide.current,
          session: sessionOf('90'),
        ),
        ...assembleWorkoutVersions(withNotes, 's1'),
      ];

      final vm = RecordWorkoutViewModel(versions: stack, initialIndex: 0);
      expect(vm.value.exerciseNotes, isEmpty);
      expect(vm.value.workoutNote, isNull);

      vm.stepOlder(); // r1 end
      expect(vm.value.exerciseNotes, {'pe1': 'Elbows tucked'});
      expect(vm.value.workoutNote, 'Moved well');

      vm.flip(); // r1 start
      expect(vm.value.exerciseNotes, isEmpty);
      expect(vm.value.workoutNote, isNull);
    });

    test('the exercise on screen is kept across a step — looking is not '
        'walking', () {
      final vm = RecordWorkoutViewModel(versions: fullStack(), initialIndex: 1);
      vm.selectExercise(1);
      expect(vm.value.active, 1);

      vm.stepOlder();
      expect(vm.value.active, 1);
      vm.flip();
      expect(vm.value.active, 1);
    });
  });

  // The record's floor is the session floor (2026-10-27): the same star, the
  // same trophy, bullseye and notes doors. They read live library context,
  // though the version on screen stays frozen — a PR landed today is still a
  // fact about the exercise the version names. These tests are what those
  // doors answer from, with the reads handed in.
  group('the floor\'s shelves', () {
    PastSetRow pastSet({
      required String id,
      double weight = 100,
      int reps = 5,
      DateTime? date,
      String exerciseId = 'e1',
    }) => PastSetRow(
      sessionExerciseSetId: id,
      sessionExerciseId: 'se-$id',
      sessionId: 'session-$id',
      userId: 'u1',
      exerciseId: exerciseId,
      setNumber: 1,
      weight: weight,
      reps: [reps],
      sessionCreatedDate: date ?? DateTime(2026, 10, 1),
    );

    Goal goalOf({
      required String id,
      num weight = 100,
      int reps = 5,
      String exerciseId = 'e1',
    }) => Goal(
      goalId: id,
      userId: 'u1',
      exerciseId: exerciseId,
      targetWeight: weight,
      targetReps: reps,
    );

    Lesson lessonOf(String id) => Lesson(
      lessonId: id,
      userId: 'u1',
      exerciseId: 'e1',
      text: 'Elbows tucked',
      pinned: false,
      createdDate: DateTime(2026, 10, 1),
    );

    List<WorkoutVersion> stack() => [
      WorkoutVersion(
        sessionId: 's1',
        side: WorkoutVersionSide.current,
        session: sessionOf('90'),
      ),
    ];

    test(
      'the doors answer from the timeline, the goals and the notes',
      () async {
        final vm = RecordWorkoutViewModel(
          versions: stack(),
          initialIndex: 0,
          userId: 'u1',
          timelineLoader: (_) async => [
            // Handed newest first on purpose: the shelf sorts its own copy.
            pastSet(id: 'b', weight: 110, reps: 3, date: DateTime(2026, 9, 2)),
            pastSet(id: 'a', weight: 100, reps: 5, date: DateTime(2026, 9, 1)),
          ],
          lessonRepository: _Lessons(
            byExercise: {
              'e1': [lessonOf('l1'), lessonOf('l2')],
            },
          ),
          programRepository: FakeProgramRepository(
            goals: [
              goalOf(id: 'g-met', weight: 100, reps: 5),
              goalOf(id: 'g-open', weight: 120, reps: 5),
            ],
          ),
        );

        expect(vm.prCountFor('e1'), 0, reason: 'quiet until the read lands');

        await vm.loadContext();

        expect(vm.prCountFor('e1'), 2);
        expect(
          [for (final e in vm.prHistoryFor('e1')) e.sessionExerciseSetId],
          ['a', 'b'],
          reason: 'oldest first — the trophy\'s shelf order on every floor',
        );
        expect(vm.lessonCountFor('e1'), 2);
        expect(vm.goalsForExercise('e1'), hasLength(2));
        expect(
          vm.openGoalsFor('e1'),
          1,
          reason: 'the 100 × 5 goal was met by the first set',
        );
        expect(vm.value.goalSetIds, {'a'});
        expect(vm.value.goalTimeline.first.sessionExerciseSetId, 'a');
      },
    );

    test(
      'a failed read leaves its shelf quiet — a door is never a blocker',
      () async {
        final vm = RecordWorkoutViewModel(
          versions: stack(),
          initialIndex: 0,
          userId: 'u1',
          timelineLoader: (_) async => throw StateError('offline'),
          lessonRepository: _Lessons(throwOnBatch: true),
          programRepository: _OfflineGoals(),
        );

        await vm.loadContext();

        expect(vm.prCountFor('e1'), 0);
        expect(vm.lessonCountFor('e1'), 0);
        expect(vm.openGoalsFor('e1'), 0);
        expect(vm.value.goalSetIds, isEmpty);
        // The version itself is untouched: the shelves are extras on a record.
        expect(vm.value.isCurrent, isTrue);
        expect(vm.value.exercises, hasLength(1));
      },
    );

    test(
      'the shelves are read once — a step or a flip never re-queries',
      () async {
        var reads = 0;
        final vm = RecordWorkoutViewModel(
          versions: stack(),
          initialIndex: 0,
          userId: 'u1',
          timelineLoader: (_) async {
            reads++;
            return [pastSet(id: 'a')];
          },
          lessonRepository: _Lessons(),
          programRepository: FakeProgramRepository(),
        );

        await vm.loadContext();
        await vm.loadContext();
        vm.stepOlder();
        vm.selectExercise(3);

        expect(reads, 1);
        expect(vm.value.goalTimeline, hasLength(1));
      },
    );

    test('without a user there is nothing to read — and no repository is '
        'built', () async {
      // A host test builds this VM with no account; the repositories open the
      // database as they are made, so touching one here would throw.
      final vm = RecordWorkoutViewModel(versions: stack(), initialIndex: 0);

      await vm.loadContext();
      await vm.loadLessonsFor('e1');

      expect(vm.value.allPrEvents, isEmpty);
      expect(vm.lessonCountFor('e1'), 0);
    });

    test('the note tile\'s shelf re-reads on demand', () async {
      final lessons = _Lessons();
      final vm = RecordWorkoutViewModel(
        versions: stack(),
        initialIndex: 0,
        userId: 'u1',
        timelineLoader: (_) async => const [],
        lessonRepository: lessons,
        programRepository: FakeProgramRepository(),
      );

      await vm.loadContext();
      expect(vm.lessonCountFor('e1'), 0);

      lessons.byExercise = {
        'e1': [lessonOf('l1')],
      };
      await vm.loadLessonsFor('e1');

      expect(vm.lessonCountFor('e1'), 1);
      expect(vm.lessonsFor('e1').single.lessonId, 'l1');
    });
  });

  // The finish's snapshot drops the group a pass removed, so the end has no
  // row of its own to mark (2026-10-27). The record draws it from the start's
  // frozen copy instead — red, with the sets it had — so the end says what is
  // gone while the start stays the plain baseline it was found as.
  group('the pass\'s removals', () {
    ContentExercise exerciseOf(String id, int order) => ContentExercise(
      plannedExerciseId: 'pe-$id',
      plannedSessionId: 's1',
      userId: 'u1',
      exerciseId: id,
      exerciseOrder: order,
      sets: [
        ContentSet(
          plannedSetId: 'ps-$id',
          plannedExerciseId: 'pe-$id',
          plannedSessionId: 's1',
          userId: 'u1',
          setNumber: 1,
          targetWeight: '50',
          targetReps: '10',
        ),
      ],
    );

    ContentSession side({required bool holdsKept}) => ContentSession(
      sessionId: 's1',
      userId: 'u1',
      name: 'Push Day',
      exercises: [exerciseOf('e1', 0), if (holdsKept) exerciseOf('e2', 1)],
    );

    ProgramContent doc({required bool holdsKept}) =>
        ProgramContent(sessions: [side(holdsKept: holdsKept)]);

    List<WorkoutVersion> stack({bool baselineHoldsWorkout = true}) =>
        assembleWorkoutVersions([
          reviewOf(
            id: 'r1',
            started: DateTime(2026, 10, 1),
            completed: DateTime(2026, 10, 2),
            baseline: baselineHoldsWorkout
                ? doc(holdsKept: true)
                : docOf('0', holdsWorkout: false),
            snapshot: doc(holdsKept: false),
          ),
        ], 's1');

    test('an end draws the group its start held and it does not, from the '
        'start\'s own copy', () {
      final vm = RecordWorkoutViewModel(versions: stack(), initialIndex: 0);
      final state = vm.value;

      expect(state.isStart, isFalse);
      expect(state.removedIds, {'pe-e2'});
      expect(
        [for (final e in state.exercises) e.exerciseId],
        ['e1', 'e2'],
        reason: 'the removed group keeps its plan place on the card',
      );
      // It carries the sets it had when the pass found it — what makes the
      // removal a fact with a shape, not just a name wearing a minus.
      expect(state.exercises.last.sets.single.targetWeight, '50');
      expect(state.exercises.last.sets.single.targetReps, '10');
    });

    test('a start has no removals to draw — it is what was found', () {
      final vm = RecordWorkoutViewModel(versions: stack(), initialIndex: 1);

      expect(vm.value.isStart, isTrue);
      expect(vm.value.removedIds, isEmpty);
      expect(
        [for (final e in vm.value.exercises) e.exerciseId],
        ['e1', 'e2'],
        reason: 'the group is simply there, as the baseline had it',
      );
    });

    test('a review that kept only its end has nothing to read a removal '
        'from', () {
      final legacy = reviewOf(
        id: 'r1',
        started: DateTime(2026, 10, 1),
        completed: DateTime(2026, 10, 2),
        snapshot: doc(holdsKept: false),
      );
      final vm = RecordWorkoutViewModel(
        versions: assembleWorkoutVersions([legacy], 's1'),
        initialIndex: 0,
      );

      expect(vm.value.removedIds, isEmpty);
      expect(
        [for (final e in vm.value.exercises) e.exerciseId],
        ['e1'],
        reason: 'with no start, the end is all the truth there is',
      );
    });

    test('a start that never held the workout knows no removals', () {
      final vm = RecordWorkoutViewModel(
        versions: stack(baselineHoldsWorkout: false),
        initialIndex: 0,
      );

      expect(vm.value.isStart, isFalse);
      expect(vm.value.removedIds, isEmpty);
    });

    test('the current plan draws no removals — no review holds it', () {
      final vm = RecordWorkoutViewModel(
        versions: [
          WorkoutVersion(
            sessionId: 's1',
            side: WorkoutVersionSide.current,
            session: side(holdsKept: false),
          ),
          ...stack(),
        ],
        initialIndex: 0,
      );

      expect(vm.value.isCurrent, isTrue);
      expect(vm.value.removedIds, isEmpty);
      expect([for (final e in vm.value.exercises) e.exerciseId], ['e1']);
    });
  });

  group('the card and the floor agree', () {
    test('exercises read in plan order, and the active one clamps', () {
      final session = ContentSession(
        sessionId: 's1',
        userId: 'u1',
        name: 'Push Day',
        exercises: [
          ContentExercise(
            plannedExerciseId: 'pe2',
            plannedSessionId: 's1',
            userId: 'u1',
            exerciseId: 'e2',
            exerciseOrder: 2,
            sets: const [],
          ),
          ContentExercise(
            plannedExerciseId: 'pe1',
            plannedSessionId: 's1',
            userId: 'u1',
            exerciseId: 'e1',
            exerciseOrder: 1,
            sets: const [],
          ),
        ],
      );
      final vm = RecordWorkoutViewModel(
        versions: [
          WorkoutVersion(
            sessionId: 's1',
            side: WorkoutVersionSide.current,
            session: session,
          ),
        ],
        initialIndex: 0,
      );

      expect([for (final e in vm.value.exercises) e.exerciseId], ['e1', 'e2']);
      expect(vm.value.activeExercise!.exerciseId, 'e1');

      vm.selectExercise(5);
      expect(
        vm.value.activeExercise!.exerciseId,
        'e2',
        reason: 'a shorter version must never land the card nowhere',
      );
    });
  });
}

/// The lesson shelves, handed in — what the note door reads and re-reads.
class _Lessons implements LessonRepository {
  _Lessons({this.byExercise = const {}, this.throwOnBatch = false});

  Map<String, List<Lesson>> byExercise;
  bool throwOnBatch;

  @override
  Future<Map<String, List<Lesson>>> fetchLessonsForExercises(
    String userId,
    List<String> exerciseIds,
  ) async {
    if (throwOnBatch) throw StateError('offline');
    return {
      for (final id in exerciseIds)
        if (byExercise[id] != null) id: byExercise[id]!,
    };
  }

  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      byExercise[exerciseId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A goal read that never answers — the door that cannot answer stays quiet.
class _OfflineGoals implements ProgramRepository {
  @override
  Future<List<({Goal goal, String? programName, String? blockName})>>
  fetchGoalOptions(String userId) async => throw StateError('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
