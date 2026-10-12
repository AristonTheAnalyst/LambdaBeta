import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/lab_mode.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/dev/lab/lab_database.dart';
import 'package:lambda/features/dev/lab/lab_seed.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';
import 'package:lambda/features/programs/model/program_content_diff.dart';
import 'package:lambda/features/session/model/pr_service.dart';
import 'package:powersync/powersync.dart';

/// Tests the dev flow lab's seed against a REAL PowerSync database, read back
/// through the same repositories the lab's screens use. Run with:
///
///   flutter test integration_test/lab_seed_test.dart -d macos
///
/// The lab's screens are the app's own, so there is no view model to fake and
/// nothing to stub: what the seed has to be right about is the data. Three
/// things are asserted here that the UI cannot easily show — that the seed
/// refuses to run outside the sandbox, that it builds both program shapes
/// complete enough to exercise the editors, and that the logged history is
/// real enough to derive PRs and goal verdicts from.
///
/// The seed runs with `labMode` set, so both REST-first repositories take
/// their local-only remote by default. That is itself under test: this
/// harness has no Supabase session, and a seed that still reached for
/// Supabase would fail here rather than write a fake program into a real
/// account.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_lab');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/lab.db');
    await db.initialize();
    ps.swapDatabase(db);
    labMode = true;
  });

  tearDown(() async {
    // A test that failed between enter() and leave() would otherwise leave
    // the next one pointed at the sandbox — a database this teardown is
    // about to close.
    LabDatabase.leave();
    labMode = false;
    await db.close();
    await dir.delete(recursive: true);
  });

  test('the seed refuses to run with the sandbox not in place', () async {
    // The guard in front of the seed's first write. Anything asserting this
    // has to be cheap and total — the alternative is a fake program in the
    // user's account, and this test is the proof that the cheap check is the
    // one that runs.
    labMode = false;
    await expectLater(seedLabWorld(userId), throwsStateError);
    expect(await labWorldExists(userId), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the seed builds both program shapes, ready to edit', () async {
    await seedLabWorld(userId);
    expect(await labWorldExists(userId), isTrue);

    final programs = ProgramRepository();
    final list = await programs.fetchPrograms(userId);
    expect(list.map((p) => p.name),
        containsAll(['SAMPLE · Gophy Program', 'SAMPLE · Lambda']));

    // The simple program: three workouts in order, each with real targets.
    final fullBody = list.firstWhere((p) => p.name == 'SAMPLE · Gophy Program');
    expect(fullBody.usesBlocks, isFalse);
    final workouts = await programs.fetchPlannedSessions(fullBody.programId);
    expect(workouts.map((s) => s.name), [
      'SAMPLE · Power Clean - Training A',
      'SAMPLE · Jump Training',
      'SAMPLE · Power Clean - Training B',
    ]);

    final planned = PlannedSessionRepository();
    final squatDay = workouts
        .firstWhere((s) => s.name == 'SAMPLE · Power Clean - Training A');
    final groups = await planned.fetchPlannedExercises(squatDay.sessionId);
    expect(groups.map((g) => g.exerciseName),
        ['Power Clean', 'Back Squat', 'Bench Press'],
        reason: 'exercise names hydrate from dim_exercise — a seed that wrote '
            'rows without their exercise ids would show three blank tabs');
    final squatSets = await planned.fetchPlannedSets(squatDay.sessionId);
    expect(squatSets, hasLength(11),
        reason: 'five power clean targets plus three each of squat and bench');
    final firstMovement = squatSets.take(5).toList();
    expect(firstMovement.map((s) => s.exerciseName), everyElement('Power Clean'),
        reason: 'targets hydrate the exercise through their parent group, the '
            'way the editor reads them');
    expect(firstMovement.map((s) => s.setNumber), [1, 2, 3, 4, 5]);
    expect(firstMovement.first.targetWeight, '80');
    expect(firstMovement.first.targetReps, '3');

    // The blocked program: two phases, two workouts each, each workout
    // placed in its own block.
    final strength = list.firstWhere((p) => p.name == 'SAMPLE · Lambda');
    expect(strength.usesBlocks, isTrue);
    final blocks = await programs.fetchBlocks(strength.programId);
    expect(blocks.map((b) => b.name),
        ['SAMPLE · Capacity Block', 'SAMPLE · Intensity Block']);
    final cycleWorkouts =
        await programs.fetchPlannedSessions(strength.programId);
    expect(cycleWorkouts, hasLength(4));
    final links = await planned.fetchProgramLinks(strength.programId);
    expect(links.map((l) => l.blockId).toSet(),
        blocks.map((b) => b.blockId).toSet(),
        reason: 'every workout of the blocked program has to sit in a block, '
            'or the block editor opens on an empty phase');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the sandbox goes in on open and the app\'s own comes back on close',
      () async {
    // The harness's own shortcut — lab mode on, the database already a
    // throwaway file — is the state the app is in AFTER the lab opens, not
    // before it. Undo it, to the state the app is really in when the card is
    // tapped.
    labMode = false;
    // The one dangerous move in the whole lab: while it is open, every
    // repository in the app is pointed somewhere else. Opening must put the
    // sandbox in place, and closing must hand back the EXACT database it
    // displaced — not merely some database.
    final appDatabase = ps.db;
    await LabDatabase.enter();
    expect(LabDatabase.isActive, isTrue);
    expect(identical(ps.db, appDatabase), isFalse);

    LabDatabase.leave();
    expect(LabDatabase.isActive, isFalse);
    expect(identical(ps.db, appDatabase), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('resetting empties the sandbox and leaves the app pointed at it',
      () async {
    labMode = false;
    await LabDatabase.enter();
    // The sandbox is a file that outlives the test process, so a run that died
    // before its own reset would hand this one a world it did not make. Start
    // from the premise the test is about: an empty sandbox, just filled.
    await LabDatabase.reset();
    await seedLabWorld(userId);
    expect(await labWorldExists(userId), isTrue);

    await LabDatabase.reset();

    expect(LabDatabase.isActive, isTrue,
        reason: 'the lab screen stays open across a reset — it rebuilds its '
            'library rather than closing');
    expect(await labWorldExists(userId), isFalse,
        reason: 'reset is the only way back to a clean sandbox, so it has to '
            'actually empty it');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the seed logs real history, and PRs can be derived from it',
      () async {
    await seedLabWorld(userId);

    final sessions = SessionRepository();
    final logged = await sessions.loadSessionsWithSets(userId);
    expect(logged, hasLength(5),
        reason: 'three passes of Training A plus one each of two workouts from '
            'the blocked program — the history has to span both programs, or '
            'the review picker is ordered by dates that all come from one');
    expect(logged.every((s) => s.sets.isNotEmpty), isTrue);
    expect(
      logged.map((s) => s.sets.length).reduce((a, b) => a + b),
      56,
      reason: '33 for Training A (3 × (5 + 3 + 3)) + 12 for the heavy squat '
          'day + 11 for the upper day — the past sessions the history pills '
          'read',
    );

    // The progression the seed writes is meant to be legible: 2.5kg heavier
    // every pass, which is exactly what the PR engine calls a frontier
    // extension. The upper day's 100kg at 8 reps joins in on reps — no
    // earlier set was that long.
    final prs = await PrService(sessionRepo: sessions).timeline(userId);
    final squatPrs = prs.where((e) => e.exerciseName == 'Back Squat').toList();
    expect(squatPrs, hasLength(4),
        reason: '112.5, 115 and 117.5kg at 5 reps each extend the frontier in '
            'turn, and 100kg at 8 reps beats the earlier 5s on reps — the lab '
            'needs a PR count that is real, not zero');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the seed orders the review picker by when things were last logged',
      () async {
    await seedLabWorld(userId);

    // The picker's one promise: last logged first, then newest created, and
    // the never-logged last. The three logged rows are one from each end of
    // the world — a simple program's workout, and one from each block of the
    // blocked program — so the order cannot be an artefact of one program.
    final rows = await PlannedSessionRepository().fetchReviewableRows(userId);
    expect(rows.take(3).map((r) => r.session.name), [
      'SAMPLE · Broad Jump Training',
      'SAMPLE · Power Clean - Training A',
      'SAMPLE · Sunday Training',
    ]);
    expect(rows.take(3).every((r) => r.lastLogged != null), isTrue);
    expect(rows.skip(3).every((r) => r.lastLogged == null), isTrue,
        reason: 'the four nobody has logged sort after the three that were');
    expect(rows, hasLength(7));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the seed writes goals as sets to beat, unattached to anything',
      () async {
    await seedLabWorld(userId);

    final options = await ProgramRepository().fetchGoalOptions(userId);
    expect(options, hasLength(3));
    expect(
      options.every((o) =>
          o.goal.programId == null &&
          o.goal.blockId == null &&
          o.programName == null &&
          o.blockName == null),
      isTrue,
      reason: 'a goal is a set to beat — nothing files one under a program or '
          'a block (2026-10-08), so there is no name for a chip to say',
    );
    expect(options.every((o) => o.goal.exerciseId != null), isTrue,
        reason: 'every goal names an exercise — a line of prose is not a set');

    // One goal carries notes and two do not: both faces of the sheet's notes
    // box are reachable in the sandbox without typing anything first.
    final withNotes = options.where((o) => o.goal.description != null).toList();
    expect(withNotes, hasLength(1));
    expect(withNotes.single.goal.targetWeight, 100,
        reason: 'the bench goal is the one the seed writes notes on');
    expect(withNotes.single.goal.description, isNotEmpty);

    // The three are the three states a goal can be in, judged by the real
    // engine against the real logged history.
    final outcomes = {
      for (final a in evaluateGoals(
        goals: [for (final o in options) o.goal],
        sets: await SessionRepository().loadPastSetsTimeline(userId),
        from: DateTime.now().toUtc().subtract(const Duration(days: 30)),
        to: DateTime.now().toUtc().add(const Duration(days: 1)),
      ))
        a.goal.targetWeight: a,
    };

    // 100 × 5 on plain bench: the best bench is 75 × 5, so a miss — with the
    // near-miss evidence attached rather than a blank.
    final bench = outcomes[100]!;
    expect(bench.achieved, isFalse);
    expect(bench.evidenceWeight, 75);

    // 75 × 3 on a power clean: the logged best is 77.5 × 3, so a hit — and
    // the evidence is the set that hit it, not the target.
    final clean = outcomes[75]!;
    expect(clean.achieved, isTrue);
    expect(clean.evidenceWeight, 77.5);
    expect(clean.evidenceReps, 3);

    // 180 × 5 on a trap bar deadlift: never trained, so no evidence at all —
    // the row's "Not attempted yet" case.
    final deadlift = outcomes[180]!;
    expect(deadlift.achieved, isFalse);
    expect(deadlift.evidenceWeight, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the seed finishes a standalone review through the real path',
      () async {
    await seedLabWorld(userId);

    // Written by beginReview → markWorkoutReviewed → completeReview, so a
    // broken program-less path fails here rather than on a list with nothing
    // in it.
    final history = ProgramHistoryRepository();
    final reviews = await history.fetchReviewsForUser(userId);
    expect(reviews, hasLength(1));

    final review = reviews.single;
    expect(review.programId, isNull, reason: 'standalone: no program');
    expect(review.title, 'SAMPLE · End of Capacity Block');
    expect(review.isCompleted, isTrue);
    expect(review.outcome, kOutcomeReviewed);
    expect(review.storedSessionIds, hasLength(2));
    expect(review.storedGoalIds, hasLength(2));
    expect(review.reviewedSessions.keys, review.storedSessionIds,
        reason: 'both workouts were ticked before it was finished');
    expect(review.hasSnapshot, isTrue,
        reason: 'finishing cuts the snapshot — the read-back is the review');

    // The snapshot is of the set, not of everything else that happened to
    // exist in the sandbox: two workouts, and the two goals that were picked.
    final content = scopedSnapshot(review)!;
    expect(content.sessions, hasLength(2));
    expect(content.goals, hasLength(2));

    // ...and it reads back as closed, so nothing offers to resume it.
    expect(review.isOpen, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
