import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/features/programs/viewmodel/record_workout_viewmodel.dart';

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
}
