import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/features/programs/model/program_content_diff.dart';
import 'package:powersync/powersync.dart';

/// The standalone review — a pass over workouts and goals with no program in
/// the picture — against a REAL PowerSync SQLite DB. Run with:
///
///   flutter test integration_test/standalone_review_repo_test.dart -d macos
///
/// What makes this shape its own thing is the null `program_id`: every read
/// that used to resolve a review's ground through a program now has a second
/// route, and the failure mode of getting it wrong is quiet. A standalone row
/// that fell through to program resolution would snapshot a program that has
/// nothing to do with it, or one that does not exist; a `fetchDueItems` that
/// forgot the filter would ask the user to answer a review that was never
/// scheduled. Neither throws. Both are asserted against here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';

  late Directory dir;
  late PowerSyncDatabase db;
  late PlannedSessionRepository planned;
  late ProgramHistoryRepository history;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    planned = PlannedSessionRepository();
    history = ProgramHistoryRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a standalone review round-trips its set, its goals and its baseline',
      () async {
    // Two workouts, one of them in a program — membership is a label here, not
    // a scope: a review covers whatever the user picked.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );
    final bench = await planned.createPlannedExercise(
      userId,
      push.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );
    await planned.createPlannedSet(
      userId,
      bench.plannedExerciseId,
      plannedSessionId: push.sessionId,
      setNumber: 1,
      targetWeight: '70',
      targetReps: '5',
    );
    await _insertGoal(db, userId, programId, goalId: 'g1', text: 'Sleep');

    final review = await history.beginReview(
      userId: userId,
      // The whole point: no program.
      sessionIds: [push.sessionId, pull.sessionId],
      goalIds: ['g1'],
      title: 'End of block 1',
    );

    expect(review.isStandalone, isTrue);
    expect(review.programId, isNull);
    expect(review.title, 'End of block 1');

    // Stored, not merely held: `program_id` NULL is the shape, and the set and
    // the goals survive the round trip as written.
    final rows = await db.getAll(
      'SELECT program_id, session_ids_json, goal_ids_json, baseline_content '
      'FROM fact_program_review WHERE review_id = ?',
      [review.reviewId],
    );
    expect(rows.length, 1);
    expect(rows.single['program_id'], isNull);
    expect(
      jsonDecode(rows.single['session_ids_json'] as String),
      [push.sessionId, pull.sessionId],
      reason: 'the picked order is part of the record — a snapshot reproduces '
          'the set as it was chosen',
    );
    expect(jsonDecode(rows.single['goal_ids_json'] as String), ['g1']);
    expect(rows.single['baseline_content'], isNotNull);

    // Read back through a FRESH repository, and resolved with NO links passed:
    // a standalone set never falls through to program resolution, so an empty
    // link list must still yield the stored set.
    final read = await ProgramHistoryRepository().fetchReview(review.reviewId);
    expect(read!.isStandalone, isTrue);
    expect(read.storedSessionIds, [push.sessionId, pull.sessionId]);
    expect(read.storedGoalIds, ['g1']);
    expect(
      read.sessionsIn(const []),
      [push.sessionId, pull.sessionId],
      reason: 'null program_id resolves to the stored set — the block and '
          'session fallbacks below it are for legacy rows, not for this',
    );

    // The baseline is the set as found, cut at the moment the pass opened.
    expect(read.hasBaseline, isTrue);
    expect(
      read.baseline!.sessions.map((s) => s.sessionId),
      [push.sessionId, pull.sessionId],
    );
    expect(read.baseline!.goals.single.goalId, 'g1');
    expect(
      read.baseline!.sessions.first.exercises.single.sets.single.targetWeight,
      '70',
      reason: 'the baseline holds live rows, targets and all',
    );
  });

  test('the user-wide read returns both kinds, and the program read neither '
      'of the other', () async {
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );

    final programSide = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
      title: 'Program pass',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final standalone = await history.beginReview(
      userId: userId,
      sessionIds: [pull.sessionId],
      title: 'Library pass',
    );

    // The list the Reviews tab reads: everything the user has, newest first.
    final all = await history.fetchReviewsForUser(userId);
    expect(all.map((r) => r.reviewId), [
      standalone.reviewId,
      programSide.reviewId,
    ]);

    // The program timeline is still the program's: a standalone row has no
    // business on it, whatever else it covers.
    final forProgram = await history.fetchReviews(programId);
    expect(forProgram.map((r) => r.reviewId), [programSide.reviewId]);
  });

  test('finishing snapshots the set — a goal whose block was never walked '
      'stays in', () async {
    // The reason `contentInScope` takes the picked ids: a goal is reviewed
    // because it was PICKED, not because something in its block happened to be.
    // Narrowing by block membership alone would silently drop it, and a review
    // that lost one of its two halves reads as if it were never there.
    await _insertBlock(
      db,
      userId,
      programId,
      blockId: 'b1',
      name: 'Accumulation',
      order: 1,
    );
    // In the block, but NOT in the review.
    final untouched = await planned.createPlannedSession(userId, name: 'Legs');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: untouched.sessionId,
      sequenceOrder: 2,
      blockId: 'b1',
    );
    // In the review, and in no program at all.
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    await _insertGoal(
      db,
      userId,
      programId,
      goalId: 'g-block',
      blockId: 'b1',
      text: 'Squat 140',
    );
    await _insertGoal(
      db,
      userId,
      programId,
      goalId: 'g-loose',
      text: 'Sleep eight hours',
    );

    final review = await history.beginReview(
      userId: userId,
      sessionIds: [pull.sessionId],
      goalIds: ['g-block', 'g-loose'],
    );
    final done = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );

    final snapshot = done.snapshot!;
    expect(
      snapshot.sessions.map((s) => s.sessionId),
      [pull.sessionId],
      reason: 'exactly the set — nothing else that happened to exist',
    );
    expect(
      snapshot.goals.map((g) => g.goalId),
      ['g-block', 'g-loose'],
      reason: 'both were picked; one of them hangs off a block the review '
          'never touched, which is a reason to keep it, not to drop it',
    );

    // And the read-back narrows to the same ground: no program narrowing
    // sneaks in for a row that has no program.
    final narrowed = scopedSnapshot(done)!;
    expect(narrowed.goals, hasLength(2));
    expect(narrowed.sessions.single.sessionId, pull.sessionId);
  });

  test('a workout note round-trips, replaces and clears', () async {
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final review = await history.beginReview(
      userId: userId,
      sessionIds: [push.sessionId],
    );

    await history.setWorkoutNote(
      review.reviewId,
      push.sessionId,
      note: '  Whole session felt heavy  ',
    );

    // A fresh repository: the note lives on the row, not in this instance.
    final read = await ProgramHistoryRepository().fetchReview(review.reviewId);
    expect(
      read!.workoutNotes[push.sessionId],
      'Whole session felt heavy',
      reason: 'trimmed on the way in, like every note in the app',
    );

    // One workout, one note — the second replaces the first.
    await history.setWorkoutNote(
      review.reviewId,
      push.sessionId,
      note: 'Drop the back-off sets',
    );
    var reread = await history.fetchReview(review.reviewId);
    expect(reread!.workoutNotes[push.sessionId], 'Drop the back-off sets');
    expect(reread.workoutNotes, hasLength(1));

    // A blank note clears the entry, and the emptied document goes back to
    // NULL rather than lingering as '{}'.
    await history.setWorkoutNote(review.reviewId, push.sessionId, note: '   ');
    reread = await history.fetchReview(review.reviewId);
    expect(reread!.workoutNotes, isEmpty);
    final stored = await db.getAll(
      'SELECT workout_notes_json FROM fact_program_review '
      'WHERE review_id = ?',
      [review.reviewId],
    );
    expect(stored.single['workout_notes_json'], isNull);
  });

  test('a completed review takes no more ticks', () async {
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    final review = await history.beginReview(
      userId: userId,
      sessionIds: [push.sessionId, pull.sessionId],
    );

    await history.markWorkoutReviewed(review.reviewId, push.sessionId);
    await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );

    // A late Done — a queued tap, a second device — must not mutate a record
    // that has already been written.
    await history.markWorkoutReviewed(review.reviewId, pull.sessionId);
    final sealed = await history.fetchReview(review.reviewId);
    expect(sealed!.reviewedSessions.keys, [push.sessionId]);
  });

  test('cancelling deletes the open row and leaves the rest standing', () async {
    // The cancel writes one statement at one row: no children to unwind (the
    // ticks and notes are columns on it), and no neighbour touched.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');

    final kept = await history.beginReview(
      userId: userId,
      sessionIds: [push.sessionId],
      title: 'Kept',
    );
    final cancelled = await history.beginReview(
      userId: userId,
      sessionIds: [pull.sessionId],
      title: 'Cancelled',
    );

    await history.deleteReview(cancelled.reviewId);

    expect(
      await ProgramHistoryRepository().fetchReview(cancelled.reviewId),
      isNull,
      reason: 'the row is gone — not archived, not emptied',
    );
    expect(
      await history.fetchReview(kept.reviewId),
      isNotNull,
      reason: 'the statement addresses one review',
    );
    expect(
      (await history.fetchReviewsForUser(userId)).map((r) => r.reviewId),
      [kept.reviewId],
    );
  });

  test('the cancel never takes a record — a completed row survives the '
      'delete', () async {
    // The one place the SQL guard can be proven: local SQLite declares no
    // foreign keys and would delete whatever the statement names. A pass
    // completed on another device between the swipe and the statement is a
    // record by the time the DELETE lands, and it must stand.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final review = await history.beginReview(
      userId: userId,
      sessionIds: [push.sessionId],
    );
    await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeDismissed,
    );

    await history.deleteReview(review.reviewId);

    final survived = await history.fetchReview(review.reviewId);
    expect(survived, isNotNull);
    expect(survived!.completedDate, isNotNull);
  });

  test('a standalone pass chains to a program pass over the same workout',
      () async {
    // "Contains", across surfaces. The standalone walk reads EVERY review the
    // user has, so a program's checkpoint is a legitimate predecessor for a
    // library pass that covers one of its workouts — the two are answering the
    // same question about that workout, and the newer answer is the one to
    // compare against.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );

    final programPass = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
    );
    final finished = await history.completeReview(
      programPass.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2));
    final standalone = await history.beginReview(
      userId: userId,
      sessionIds: [push.sessionId, pull.sessionId],
    );

    final base = await history.comparisonBase(
      standalone,
      sessionId: push.sessionId,
    );
    expect(
      base!.completedDate,
      finished.completedDate,
      reason: 'the program pass looked at push, so it is the last word on it',
    );
    expect(
      base.content.sessions.map((s) => s.sessionId),
      contains(push.sessionId),
      reason: 'the base is the whole snapshot that was cut — narrowing it to '
          'one workout is the comparison\'s job, not the pairing\'s',
    );

    // Ground nobody has looked at falls back to the pass as found — the
    // standalone review's own baseline, not the program's answer.
    final forPull = await history.comparisonBase(
      standalone,
      sessionId: pull.sessionId,
    );
    expect(forPull!.asFound, isTrue);
    expect(
      forPull.content.sessions.map((s) => s.sessionId),
      [push.sessionId, pull.sessionId],
      reason: 'the fallback is the pass as found — the review\'s own baseline, '
          'cut from the set it covers',
    );

    // A pass in progress is not a checkpoint: the window opens on finished
    // looks only, so the open standalone pass has opened nothing yet.
    expect(
      await history.checkpointForSet(userId, sessionIds: [pull.sessionId]),
      isNull,
    );
    // The completed program pass has — it looked at push, and the window for a
    // set opens on the newest pass over any of it, whichever surface started
    // it.
    expect(
      await history.checkpointForSet(userId, sessionIds: [push.sessionId]),
      finished.completedDate,
    );

    // Finishing the standalone pass opens the window on its own ground — the
    // read the Reviews landing makes when it resumes one.
    final closed = await history.completeReview(
      standalone.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );
    expect(
      await history.checkpointForSet(userId, sessionIds: [pull.sessionId]),
      closed.completedDate,
    );
  });

  test('the reviewable list is ordered by last logged, then newest created',
      () async {
    // The agreed rule, and the only implementation of it. `dim_planned_session`
    // has no updated_date — recency is a LOGGED session's date, so a workout
    // nobody has trained falls to the end whatever else is true of it.
    final recent = await planned.createPlannedSession(userId, name: 'Recent');
    final older = await planned.createPlannedSession(userId, name: 'Older');
    final newestCreated = await planned.createPlannedSession(
      userId,
      name: 'Newest created',
    );
    final oldestCreated = await planned.createPlannedSession(
      userId,
      name: 'Oldest created',
    );
    final archived = await planned.createPlannedSession(
      userId,
      name: 'Archived',
    );

    await _insertSession(
      db,
      userId,
      sessionId: 's-recent',
      name: 'Recent',
      plannedSessionId: recent.sessionId,
      createdDate: DateTime.now().subtract(const Duration(hours: 3)),
    );
    await _insertSession(
      db,
      userId,
      sessionId: 's-older',
      name: 'Older',
      plannedSessionId: older.sessionId,
      createdDate: DateTime.now().subtract(const Duration(days: 9)),
    );

    // The tie-break is created_date — set by hand, because two sessions made
    // moments apart in a test would order by whatever the clock did between
    // them, which is exactly the accident this rule exists to avoid.
    Future<void> stamp(String id, DateTime at) => db.execute(
          'UPDATE dim_planned_session SET created_date = ? WHERE session_id = ?',
          [at.toUtc().toIso8601String(), id],
        );
    await stamp(oldestCreated.sessionId, DateTime.utc(2026, 1, 1));
    await stamp(newestCreated.sessionId, DateTime.utc(2026, 6, 1));
    await db.execute(
      'UPDATE dim_planned_session SET date_archived = ? WHERE session_id = ?',
      [DateTime.now().toUtc().toIso8601String(), archived.sessionId],
    );

    final rows = await planned.fetchReviewableRows(userId);
    expect(
      rows.map((r) => r.session.name),
      ['Recent', 'Older', 'Newest created', 'Oldest created'],
      reason: 'logged first (newest first), then never-logged by newest '
          'created — and the archived workout is not on the list at all',
    );
    expect(rows.first.lastLogged, isNotNull);
    expect(rows.last.lastLogged, isNull);

    // The count line's facts: one finished session each for the workouts that
    // were trained, none for the ones that were not — and with no completed
    // pass on record, the count is all-time, which is the wording without
    // "since last review".
    expect(rows.map((r) => r.finished), [1, 1, 0, 0]);
    expect(rows.every((r) => r.lastReview == null), isTrue);

    // A completed pass moves the line. The review is written through the real
    // repository, then dated by hand — the count's rule is the session's date
    // against the pass's, and a pass completed "now" would have nothing after
    // it to demonstrate with.
    final pass = await history.scheduleReview(
      userId: userId,
      sessionIds: [recent.sessionId],
    );
    await history.completeReview(
      pass.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );
    await db.execute(
      'UPDATE fact_program_review SET completed_date = ? WHERE review_id = ?',
      [
        DateTime.now().subtract(const Duration(days: 5)).toUtc().toIso8601String(),
        pass.reviewId,
      ],
    );

    final measured = await planned.fetchReviewableRows(userId);
    expect(measured.first.lastReview, isNotNull);
    expect(
      measured.first.finished,
      1,
      reason: 'trained 3 hours ago, after the pass five days back',
    );
    expect(
      measured[1].finished,
      0,
      reason: 'trained 9 days ago, before the pass — spent, not counted',
    );
  });

  test('a standalone review is never a due item', () async {
    // Due items are answered prompts on a program — a banner, a badge, a run
    // question. A review the user started from the library asks nothing: it
    // sits open on the list until they finish it. The filter has to be there
    // because a schedule-less standalone row is exactly the legal shape of
    // one, and a program-less DueItem could not be rendered even if it were
    // returned.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final standalone = await history.scheduleReview(
      userId: userId,
      sessionIds: [push.sessionId],
      // Nonsense for a standalone row, which is the point: even a stale
      // scheduled_for must not make one come due.
      scheduledFor: DateTime.now().subtract(const Duration(days: 3)),
    );
    expect(standalone.isStandalone, isTrue);

    final due = await history.fetchDueItems(userId);
    expect(
      due.where((d) => d.review?.reviewId == standalone.reviewId),
      isEmpty,
    );

    // The contrast that proves the filter is doing something: the same row
    // shape, with a program, and a date that has passed, comes due normally.
    final scoped = await history.scheduleReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
      scheduledFor: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(
      (await history.fetchDueItems(userId))
          .where((d) => d.review?.reviewId == scoped.reviewId),
      hasLength(1),
    );
  });
}

/// The `dim_program` row itself. `ProgramRepository.createProgram` writes
/// straight to Supabase so the program exists server-side before anything
/// references it; here the row is plain fixture data and the local insert is
/// the shortest path to it.
Future<void> _insertProgram(
  PowerSyncDatabase db,
  String userId,
  String programId,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program
      (id, program_id, user_id, program_name, program_description,
       date_archived, program_created_date, program_updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [programId, programId, userId, 'Test Program', null, null, now, now],
  );
}

/// A phase of a program. Written directly for the same reason the program is:
/// the real create is REST-first, and what is under test is the local read.
Future<void> _insertBlock(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String blockId,
  required String name,
  required int order,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program_block
      (id, block_id, user_id, program_id, name, notes, block_order,
       target_weeks, target_days, target_sessions, start_date, end_date,
       date_archived, created_date, updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      blockId,
      blockId,
      userId,
      programId,
      name,
      null,
      order,
      null,
      null,
      null,
      null,
      null,
      null,
      now,
      now,
    ],
  );
}

/// A goal row, at whichever scope the caller names — null `blockId` is the
/// program's own. Plain fixture data for the same reason the block is: what is
/// under test is what a snapshot reads, not how a goal is written.
Future<void> _insertGoal(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String goalId,
  String? blockId,
  String? text,
}) async {
  await db.execute(
    '''
    INSERT INTO fact_goal
      (id, goal_id, user_id, program_id, block_id, program_run_id, goal_text,
       custom_exercise_id, custom_variation_id, target_weight, target_reps,
       goal_created_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      goalId,
      goalId,
      userId,
      programId,
      blockId,
      null,
      text,
      null,
      null,
      null,
      null,
      DateTime.now().toUtc().toIso8601String(),
    ],
  );
}

/// A logged session, linked to the planned session it was run from — which is
/// the only fact the review picker's recency rule reads.
Future<void> _insertSession(
  PowerSyncDatabase db,
  String userId, {
  required String sessionId,
  required String name,
  required String plannedSessionId,
  required DateTime createdDate,
}) async {
  await db.execute(
    '''
    INSERT INTO fact_session
      (id, session_id, user_id, created_datetime, end_datetime,
       planned_session_id, planned_session_name)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      sessionId,
      sessionId,
      userId,
      createdDate.toUtc().toIso8601String(),
      createdDate.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      plannedSessionId,
      name,
    ],
  );
}
