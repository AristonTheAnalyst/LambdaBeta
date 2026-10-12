import 'package:uuid/uuid.dart';

import '../../../core/powersync/database.dart' as ps;
import '../../../data/models/goal.dart';
import '../../../data/models/program_review.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lab_mode.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';

const _uuid = Uuid();

/// The sandbox's starting contents: two programs of each shape, their
/// workouts and targets, a few goals (sets to beat), a little logged history
/// on dates the review picker's ordering can be judged against, and one
/// finished standalone review.
///
/// Everything is written through the real repositories, into the lab's own
/// database (see [LabDatabase]); none of it exists anywhere else. The shapes
/// are familiar on purpose — the programs and workouts are named after the
/// ones in the user's own library, and the lifts are the ones they train — but
/// every name carries a `SAMPLE · ` prefix, so a screenshot of the lab can
/// never be read as the real plan. The world is small enough to walk end to
/// end in a couple of minutes.
///
/// Workout names are DISTINCT across both programs, because planned-session
/// names are unique per user and the repository rejects a duplicate: the two
/// blocks of the second program train the same weekly work, and its intensity
/// pair is named apart for exactly this reason.
Future<void> seedLabWorld(String userId) async {
  // The guard is the important line. The seed is the one place in the lab
  // that CREATES rows wholesale, and running it against the app's real
  // database would put a fake program in the user's account — so if the swap
  // did not happen, stop before the first write rather than find out later.
  if (!labMode) {
    throw StateError('The lab world seeds only into the sandbox database.');
  }

  final exercises = ExerciseRepository();
  final planned = PlannedSessionRepository();
  final programs = ProgramRepository();
  final sessions = SessionRepository();

  // ── The exercise library ────────────────────────────────────────────────
  // The lifts the user actually trains, by their real names: the workout
  // editor's picker, the history pills and the PR engine are all more legible
  // with exercises the eye recognizes.
  final lift = <String, String>{};
  for (final name in const [
    'Power Clean',
    'Back Squat',
    'Bench Press',
    'Trap Bar Deadlift',
    'Trap Bar Jump',
    'Broad Jump',
    'Overhead Press',
    'Single Leg RDL',
    'Nordic Curl',
    'Cable Row',
    'Pull-Up',
    'Calf Raise',
  ]) {
    lift[name] = (await exercises.createExercise(userId, name)).exerciseId;
  }
  final paused = (await exercises.createVariation(userId, 'Paused')).variationId;

  // One workout: its movements, each with its sets' shared target.
  Future<String> workout(
    List<_Movement> movements, {
    required String name,
    String? programId,
    String? blockId,
    int? sequenceOrder,
  }) async {
    final session = await planned.createPlannedSession(userId, name: name);
    for (var i = 0; i < movements.length; i++) {
      final m = movements[i];
      final group = await planned.createPlannedExercise(
        userId,
        session.sessionId,
        exerciseId: lift[m.exercise],
        exerciseOrder: i + 1,
      );
      for (var set = 1; set <= m.sets; set++) {
        await planned.createPlannedSet(
          userId,
          group.plannedExerciseId,
          plannedSessionId: session.sessionId,
          exerciseId: lift[m.exercise],
          variationId: m.variation,
          setNumber: set,
          targetWeight: m.weight,
          targetReps: m.reps,
        );
      }
    }
    if (programId != null) {
      await planned.createProgramLink(
        userId,
        programId: programId,
        plannedSessionId: session.sessionId,
        sequenceOrder: sequenceOrder,
        blockId: blockId,
      );
    }
    return session.sessionId;
  }

  /// Logs one finished session of [plannedSessionId] at [daysAgo] days back,
  /// every set at its group's target weight plus [bump].
  ///
  /// The one way history gets written here, so every logged workout looks like
  /// something the app produced rather than something inserted behind its
  /// back. The elapsed hour past the day line is deliberate: a session stamped
  /// exactly N days back measures a shade under N days, and every recency
  /// label in the app would then name a day that never happened.
  Future<void> log(
    String plannedSessionId,
    String name,
    List<_Movement> movements,
    int daysAgo, {
    double bump = 0,
  }) async {
    final date =
        DateTime.now().toUtc().subtract(Duration(days: daysAgo, hours: 1));
    final sessionId = await sessions.createSession(
      userId,
      plannedSessionId: plannedSessionId,
      plannedSessionName: name,
      preFeeling: 3 + daysAgo % 3,
    );
    await ps.safeExec(
      'UPDATE fact_session SET created_datetime = ?, end_datetime = ? '
      'WHERE session_id = ?',
      [
        date.toIso8601String(),
        date.add(const Duration(minutes: 55)).toIso8601String(),
        sessionId,
      ],
    );
    for (var i = 0; i < movements.length; i++) {
      final m = movements[i];
      final row = await sessions.insertSessionExercise(
        sessionId: sessionId,
        userId: userId,
        exerciseId: lift[m.exercise],
        exerciseOrder: i + 1,
      );
      final weight = double.parse(m.weight) + bump;
      for (var set = 1; set <= m.sets; set++) {
        await sessions.insertSet(
          sessionExerciseId: row.sessionExerciseId,
          sessionId: sessionId,
          userId: userId,
          setNumber: set,
          weight: weight,
          reps: [int.parse(m.reps)],
        );
      }
    }
  }

  // ── A simple program: three workouts, in order ──────────────────────────
  final fullBody = await programs.createProgram(
    userId,
    name: 'SAMPLE · Gophy Program',
    description: 'Three workouts, run as one list. Made for the lab.',
  );
  final squatDay = await workout(
    [
      _Movement('Power Clean', 5, '80', '3'),
      _Movement('Back Squat', 3, '120', '5'),
      _Movement('Bench Press', 3, '75', '5'),
    ],
    name: 'SAMPLE · Power Clean - Training A',
    programId: fullBody.programId,
    sequenceOrder: 0,
  );
  await workout(
    [
      _Movement('Broad Jump', 4, '0', '3'),
      _Movement('Trap Bar Jump', 3, '60', '5'),
      _Movement('Single Leg RDL', 3, '40', '8'),
    ],
    name: 'SAMPLE · Jump Training',
    programId: fullBody.programId,
    sequenceOrder: 1,
  );
  await workout(
    [
      _Movement('Power Clean', 6, '90', '2'),
      _Movement('Overhead Press', 4, '50', '5'),
      _Movement('Pull-Up', 3, '0', 'AMRAP'),
    ],
    name: 'SAMPLE · Power Clean - Training B',
    programId: fullBody.programId,
    sequenceOrder: 2,
  );

  // ── A blocked program: two phases, two workouts each ────────────────────
  final strength = await programs.createProgram(
    userId,
    name: 'SAMPLE · Lambda',
    description: 'Two blocks, worked in order. Made for the lab.',
    usesBlocks: true,
  );
  final volume = await programs.createProgramBlock(
    userId,
    programId: strength.programId,
    name: 'SAMPLE · Capacity Block',
    targetWeeks: 4,
  );
  final intensity = await programs.createProgramBlock(
    userId,
    programId: strength.programId,
    name: 'SAMPLE · Intensity Block',
    targetWeeks: 4,
  );
  await workout(
    [
      _Movement('Trap Bar Deadlift', 4, '140', '5'),
      _Movement('Nordic Curl', 3, '0', '6'),
      _Movement('Calf Raise', 3, '60', '12'),
    ],
    name: 'SAMPLE · Trap Bar Training',
    programId: strength.programId,
    blockId: volume.blockId,
    sequenceOrder: 0,
  );
  // Two of these hold their movements in a variable: the history below logs
  // them, and a logged session has to be the workout it claims to be.
  final upperVolume = [
    _Movement('Back Squat', 4, '100', '8'),
    _Movement('Bench Press', 4, '75', '8'),
    _Movement('Cable Row', 3, '60', '10'),
  ];
  final heavySquatDay = [
    _Movement('Broad Jump', 5, '0', '3'),
    _Movement('Trap Bar Jump', 4, '65', '4'),
    _Movement('Single Leg RDL', 3, '45', '6'),
  ];
  final upperVolumeId = await workout(
    upperVolume,
    name: 'SAMPLE · Sunday Training',
    programId: strength.programId,
    blockId: volume.blockId,
    sequenceOrder: 1,
  );
  final heavySquatId = await workout(
    heavySquatDay,
    name: 'SAMPLE · Broad Jump Training',
    programId: strength.programId,
    blockId: intensity.blockId,
    sequenceOrder: 0,
  );
  await workout(
    [
      _Movement('Back Squat', 5, '115', '3', variation: paused),
      _Movement('Bench Press', 5, '85', '3'),
      _Movement('Cable Row', 3, '65', '8'),
    ],
    name: 'SAMPLE · Sunday Intensity',
    programId: strength.programId,
    blockId: intensity.blockId,
    sequenceOrder: 1,
  );

  // ── Goals: sets to beat, unattached ─────────────────────────────────────
  // A goal in Lambda is a set — exercise, variation, weight, reps — and
  // nothing else. It belongs to no program or block (2026-10-08): a review
  // picks goals straight from the library, and so does the seed.
  //
  // The three cover the three states a goal can be in: one already hit (the
  // logged power clean reached 77.5 × 3, past the 75 × 3 asked), one missed
  // (the best bench is 75 × 5 against a 100 × 5 target), and one on an
  // exercise never trained at all (trap bar deadlift).
  // One carries notes and two do not, so both faces of the sheet's notes box
  // are reachable in the sandbox without typing.
  final benchGoal = _uuid.v4();
  await programs.createGoal(
    userId,
    Goal(
      goalId: benchGoal,
      userId: userId,
      exerciseId: lift['Bench Press'],
      text: 'Bench Press',
      description: 'Beltless, pause on the chest. Slow off the bottom, '
          'fast through the middle.',
      targetWeight: 100,
      targetReps: 5,
    ),
  );
  final cleanGoal = _uuid.v4();
  await programs.createGoal(
    userId,
    Goal(
      goalId: cleanGoal,
      userId: userId,
      exerciseId: lift['Power Clean'],
      text: 'Power Clean',
      targetWeight: 75,
      targetReps: 3,
    ),
  );
  await programs.createGoal(
    userId,
    Goal(
      goalId: _uuid.v4(),
      userId: userId,
      exerciseId: lift['Trap Bar Deadlift'],
      text: 'Trap Bar Deadlift',
      targetWeight: 180,
      targetReps: 5,
    ),
  );

  // ── Logged history, on dates ────────────────────────────────────────────
  // Three passes of Training A over the last fortnight, 2.5kg heavier each
  // time — enough to give the history pills and the PR engine something
  // truthful to say about an exercise the user will actually open.
  //
  // Then one pass each of two workouts from the OTHER program, on their own
  // dates. The dates are the point: the review picker is ordered by when a
  // workout was last logged, and a lab where everything was never logged — or
  // all logged the same afternoon — would show that order without ever
  // putting it under strain.
  //
  // Bodyweight movements stay out of [logged] on purpose: the bump is added to
  // every movement, and a broad jump is not 2.5kg heavier than a broad jump.
  final logged = [
    _Movement('Power Clean', 5, '72.5', '3'),
    _Movement('Back Squat', 3, '112.5', '5'),
    _Movement('Bench Press', 3, '70', '5'),
  ];
  for (var week = 0; week < 3; week++) {
    await log(
      squatDay,
      'SAMPLE · Power Clean - Training A',
      logged,
      13 - week * 5,
      bump: week * 2.5,
    );
  }
  await log(heavySquatId, 'SAMPLE · Broad Jump Training', heavySquatDay, 1);
  await log(upperVolumeId, 'SAMPLE · Sunday Training', upperVolume, 6);

  // ── One finished review, written the way the app writes one ─────────────
  // No program: workouts and goals picked straight from the library, which is
  // the shape the Reviews tab starts. Through the real repository end to end —
  // beginReview writes the row and records what it found, the ticks go on, and
  // completeReview cuts the snapshot and closes it. If the program-less path
  // ever breaks, the seed breaks with it: loudly, on the lab's first open,
  // rather than as a mystery on a list with nothing in it.
  final history = ProgramHistoryRepository();
  final reviewed = await history.beginReview(
    userId: userId,
    sessionIds: [squatDay, upperVolumeId],
    // The two the pass has something to say about: both workouts train their
    // exercises, so one goal reads hit and one reads missed.
    goalIds: [benchGoal, cleanGoal],
    title: 'SAMPLE · End of Capacity Block',
  );
  await history.markWorkoutReviewed(reviewed.reviewId, squatDay);
  await history.markWorkoutReviewed(reviewed.reviewId, upperVolumeId);
  await history.completeReview(
    reviewed.reviewId,
    userId: userId,
    outcome: kOutcomeReviewed,
    notes: 'Power clean moved well all block. Press stalled at the same weight '
        'twice — worth a look before the next one.',
  );
}

/// Whether the sandbox already holds a world — asked once on entry, and the
/// only thing standing between "open the lab" and "seed it again".
Future<bool> labWorldExists(String userId) async {
  final rows = await ps.db.getAll(
    'SELECT 1 FROM dim_program WHERE user_id = ? LIMIT 1',
    [userId],
  );
  return rows.isNotEmpty;
}

/// One exercise's place in a workout: how many sets, and the target every one
/// of them carries.
class _Movement {
  const _Movement(this.exercise, this.sets, this.weight, this.reps,
      {this.variation});

  final String exercise;
  final int sets;
  final String weight;
  final String reps;

  /// A variation id, when this movement is the one a variation is there to
  /// demonstrate.
  final String? variation;
}
