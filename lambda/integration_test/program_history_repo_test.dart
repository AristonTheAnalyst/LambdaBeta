import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/features/programs/model/achievements_derivation.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';
import 'package:lambda/features/programs/model/program_content_diff.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL repos against a REAL PowerSync SQLite DB (real
/// client schema, real read/write path) — the exact code the history screen and
/// the run read path execute, minus the network. Run with:
///
///   flutter test integration_test/program_history_repo_test.dart -d macos
///
/// Host `flutter test` cannot load `libpowersync.dylib`, and `openDatabase()`
/// is not usable here (it wants a signed-in session and the app container), so
/// the global DB is pointed at a throwaway database with
/// [ps.setDatabaseForTesting] — repositories resolve `ps.db` per call, so the
/// real ones work unmodified. `-d macos` is the cheapest host for this: a
/// desktop build bundles the dylib, and unlike a device install it leaves the
/// app on the user's phone and the simulator's bundle alone.
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
    ps.setDatabaseForTesting(db);
    planned = PlannedSessionRepository();
    history = ProgramHistoryRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a completed review writes its snapshot durably', () async {
    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
    );

    final completed = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );

    expect(completed.snapshotHash, isNotEmpty);
    expect(
      completed.snapshot,
      isNotNull,
      reason: 'the document must decode — a schema-2 payload the reader knows',
    );

    // Read straight from the table the client schema declares: if
    // `schema.dart` and the UPDATE disagreed on any column, the write would
    // have thrown above rather than landing here.
    final rows = await db.getAll(
      'SELECT review_id, outcome, snapshot_content, snapshot_hash '
      'FROM fact_program_review WHERE program_id = ?',
      [programId],
    );
    expect(rows.length, 1);
    expect(rows.single['outcome'], kOutcomeReviewed);
    expect(rows.single['snapshot_hash'], completed.snapshotHash);
    expect(
      rows.single['snapshot_content'],
      isNotEmpty,
      reason: 'the snapshot IS the checkpoint — an empty one is no record',
    );

    // Completing an already-completed review is idempotent: the first answer,
    // and the snapshot it froze, stand.
    final again = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeApplied,
    );
    expect(again.outcome, kOutcomeReviewed);
    expect(again.snapshotHash, completed.snapshotHash);
  });

  test('an ad-hoc session review persists its scope and no schedule', () async {
    // The "review this workout now" path, which is not a reminder about
    // anything: no `scheduled_for`, and a `session_id` that is the plan being
    // examined rather than a logged session.
    final push = await planned.createPlannedSession(userId, name: 'Push');

    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      sessionId: push.sessionId,
      title: 'Second look at Push',
    );

    expect(review.scheduledFor, isNull);
    expect(review.isDue(DateTime.now()), isFalse,
        reason: 'an unscheduled review is never "due" — it is just open');

    final rows = await db.getAll(
      'SELECT block_id, session_id, scheduled_for, completed_date '
      'FROM fact_program_review WHERE review_id = ?',
      [review.reviewId],
    );
    expect(rows.length, 1);
    expect(
      rows.single['session_id'],
      push.sessionId,
      reason: 'the scope has to survive the round trip, not just the object',
    );
    expect(rows.single['block_id'], isNull,
        reason: 'a session review is not also a block review');
    expect(rows.single['scheduled_for'], isNull);
    expect(rows.single['completed_date'], isNull);
  });

  test('a review cannot be scoped to a block and a session at once', () async {
    // The client has to refuse what the server's CHECK refuses. A row that
    // reached the constraint would quarantine as a `23514` — it can never
    // succeed, and it stalls that device's upload checkpoint behind it.
    expect(
      () => history.scheduleReview(
        userId: userId,
        programId: programId,
        blockId: 'b1',
        sessionId: 's1',
      ),
      throwsArgumentError,
    );

    final rows = await db.getAll(
      'SELECT review_id FROM fact_program_review WHERE program_id = ?',
      [programId],
    );
    expect(rows, isEmpty, reason: 'refused before it could be written');
  });

  test('edits produce a second version that diffs against the first', () async {
    // ── A program of two workouts: Push (Bench 1×5 @70, Row 1×10 @60) then
    //    Pull (Pulldown 1×10 @50).
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    final pushLink = await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );
    final pullLink = await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: pull.sessionId,
      sequenceOrder: 2,
    );

    final bench = await planned.createPlannedExercise(
      userId,
      push.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );
    final row = await planned.createPlannedExercise(
      userId,
      push.sessionId,
      exerciseId: 'ex-row',
      exerciseOrder: 2,
    );
    final benchSet = await planned.createPlannedSet(
      userId,
      bench.plannedExerciseId,
      plannedSessionId: push.sessionId,
      setNumber: 1,
      targetWeight: '70',
      targetReps: '5',
    );
    await planned.createPlannedSet(
      userId,
      row.plannedExerciseId,
      plannedSessionId: push.sessionId,
      setNumber: 1,
      targetWeight: '60',
      targetReps: '10',
    );

    final pulldown = await planned.createPlannedExercise(
      userId,
      pull.sessionId,
      exerciseId: 'ex-pulldown',
      exerciseOrder: 1,
    );
    await planned.createPlannedSet(
      userId,
      pulldown.plannedExerciseId,
      plannedSessionId: pull.sessionId,
      setNumber: 1,
      targetWeight: '50',
      targetReps: '10',
    );

    final v1 = await _checkpoint(history, userId, programId);
    expect(v1.snapshot!.sessionCount, 2);
    expect(v1.snapshot!.exerciseCount, 3);
    expect(v1.snapshot!.setCount, 3);

    // ── Swap the two workouts, retarget a set, and add one.
    await planned.updateProgramLink(
      pullLink.plannedSessionProgramId,
      sequenceOrder: 1,
    );
    await planned.updateProgramLink(
      pushLink.plannedSessionProgramId,
      sequenceOrder: 2,
    );
    await planned.updatePlannedSet(benchSet.plannedSetId, targetWeight: '80');
    await planned.createPlannedSet(
      userId,
      row.plannedExerciseId,
      plannedSessionId: push.sessionId,
      setNumber: 2,
      targetWeight: '65',
      targetReps: '8',
    );

    final v2 = await _checkpoint(history, userId, programId);
    expect(
      v2.snapshotHash,
      isNot(v1.snapshotHash),
      reason: 'the edited rows produce a different document',
    );
    expect(
      v2.snapshot!.setCount,
      4,
      reason: 'the added set is in the new document',
    );

    final diff = diffContent(v1.snapshot!, v2.snapshot!);
    expect(
      diff.movedCount,
      1,
      reason:
          'a two-workout swap is ONE move — the LCS is what makes a '
          'reorder read as one line rather than reporting both',
    );
    expect(diff.addedCount, 1, reason: 'the second Row target set');
    expect(
      diff.editedCount,
      greaterThanOrEqualTo(1),
      reason: 'the retargeted Bench set',
    );
    expect(diff.removedCount, 0);

    // Newest first — the order the timeline renders — and every stored
    // document still decodes.
    final timeline = await history.fetchReviews(programId);
    expect(
      timeline.first.snapshotHash,
      v2.snapshotHash,
      reason: 'newest first: the second checkpoint leads the list',
    );
    expect(timeline.every((r) => r.snapshot != null), isTrue);
  });

  test('a review comes due, and completing it cuts a snapshot', () async {
    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      title: 'Block 1 check-in',
      notes: 'How did the first four weeks go?',
      // Yesterday, i.e. due now: the prompt appears the moment its day has
      // arrived, not at whatever hour the row happens to carry.
      scheduledFor: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(
      review.kind,
      kReviewKindReview,
      reason: 'no proposal ⇒ the plain flavour',
    );
    expect(review.hasProposal, isFalse);
    expect(review.isOpen, isTrue);
    expect(review.isDue(DateTime.now()), isTrue);

    final due = await history.fetchDueItems(userId);
    final mine = due.where((d) => d.programId == programId).toList();
    expect(
      mine.length,
      1,
      reason: 'exactly one thing is waiting on this program',
    );
    expect(mine.single.kind, kDueReview);
    expect(mine.single.isReviewDue, isTrue);
    expect(
      mine.single.review?.reviewId,
      review.reviewId,
      reason: 'the due item IS the row, not a copy of its fields',
    );

    final done = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
      notes: 'Good progress.',
    );
    expect(
      done.snapshot,
      isNotNull,
      reason: 'reviewing cuts a snapshot — that is what a checkpoint is',
    );
    expect(done.reviewId, review.reviewId);
    expect(done.completedDate, isNotNull);

    // The snapshot is PERSISTED, not merely returned. Reading it back out of
    // the row is the point: an UPDATE that matched nothing would still hand
    // the caller a populated object built from the live program, and every
    // assertion on the return value above would pass.
    final rows = await db.getAll(
      'SELECT outcome, completed_date, snapshot_content, snapshot_hash '
      'FROM fact_program_review WHERE review_id = ?',
      [review.reviewId],
    );
    expect(rows.length, 1);
    expect(rows.single['outcome'], kOutcomeReviewed);
    expect(rows.single['completed_date'], isNotNull);
    expect(rows.single['snapshot_content'], isNotNull);
    expect(rows.single['snapshot_hash'], isNotNull);
    expect(
      rows.single['snapshot_hash'],
      done.snapshotHash,
      reason: 'the stored document is the one that was handed back',
    );

    final completed = await history.fetchReview(review.reviewId);
    expect(completed!.isCompleted, isTrue);
    expect(completed.outcome, kOutcomeReviewed);
    expect(completed.snapshotHash, done.snapshotHash);
    expect(completed.notes, 'Good progress.');

    // Answering the prompt stops the prompt — same read, opposite answer.
    final after = await history.fetchDueItems(userId);
    expect(
      after.where((d) => d.review?.reviewId == review.reviewId),
      isEmpty,
      reason: 'a completed review is no longer due',
    );

    // A dismissal is "not now", not a checkpoint. It cuts nothing, and it must
    // not move the window the next review reads from — otherwise dismissing a
    // prompt would silently swallow everything achieved since the last one.
    final window = await history.checkpointFor(programId);
    final dismissed = await history.scheduleReview(
      userId: userId,
      programId: programId,
      scheduledFor: DateTime.now().subtract(const Duration(days: 2)),
    );
    final answered = await history.completeReview(
      dismissed.reviewId,
      userId: userId,
      outcome: kOutcomeDismissed,
    );
    expect(
      answered.isCompleted,
      isTrue,
      reason: 'the prompt is answered — it just is not a checkpoint',
    );
    expect(
      answered.hasSnapshot,
      isFalse,
      reason: 'a dismissal cuts no snapshot',
    );
    // Both rows exist, but only the real review carries a document: the
    // dismissal is a completion with nothing behind it.
    final all = await history.fetchReviews(programId);
    expect(all.length, 2);
    expect(all.where((r) => r.hasSnapshot).length, 1);
    expect(await history.checkpointFor(programId), window);
  });

  test('a snapshot holds the blocks, the membership and the goals', () async {
    // Schema 2's three additions, read off live rows: a document that claimed
    // a block but not which workouts are in it (or a program's own targets but
    // not its phases') could not answer the review it exists for.
    await _insertBlock(
      db,
      userId,
      programId,
      blockId: 'b1',
      name: 'Accumulation',
      order: 1,
      targetWeeks: 4,
    );
    final push = await planned.createPlannedSession(userId, name: 'Push');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
      blockId: 'b1',
    );
    await _insertGoal(
      db,
      userId,
      programId,
      goalId: 'g1',
      exerciseId: 'ex-bench',
      weight: 100,
      reps: 1,
      text: 'Bench',
    );
    await _insertGoal(
      db,
      userId,
      programId,
      goalId: 'g2',
      blockId: 'b1',
      text: 'Sleep eight hours',
    );

    final content = await history.buildContent(
      userId: userId,
      programId: programId,
    );

    expect(content.schema, ProgramContent.currentSchema);
    expect(content.blocks.single.blockId, 'b1');
    expect(content.blocks.single.name, 'Accumulation');
    expect(content.blocks.single.targetWeeks, 4);

    expect(content.sessions.single.sessionId, push.sessionId);
    expect(
      content.sessions.single.blockId,
      'b1',
      reason:
          'membership comes from the join row — the same column the '
          'Blocks tab groups by, so a snapshot cannot disagree with the screen '
          'about which phase a workout is in',
    );

    expect(content.goals, hasLength(2));
    final programGoal = content.goals.firstWhere((g) => g.goalId == 'g1');
    expect(programGoal.blockId, isNull);
    expect(programGoal.exerciseId, 'ex-bench');
    expect(programGoal.targetWeight, 100);
    expect(programGoal.targetReps, 1);
    final blockGoal = content.goals.firstWhere((g) => g.goalId == 'g2');
    expect(blockGoal.blockId, 'b1');
    expect(blockGoal.text, 'Sleep eight hours');

    // And the document survives the trip through storage — the revision that
    // gets cut is the encoded one, not this in-memory copy.
    final roundTripped = ProgramContent.decode(content.encode());
    expect(roundTripped.goals, hasLength(2));
    expect(roundTripped.blocks.single.name, 'Accumulation');
    expect(roundTripped.sessions.single.blockId, 'b1');
    expect(roundTripped.contentHash, content.contentHash);
  });

  test('a goal scoped to an archived block leaves the snapshot', () async {
    // Archiving a block is how a phase is deleted, and a snapshot is of what
    // the program IS. `fetchBlocks` filters archived rows, so a goal still
    // pointing at one must not keep a dead phase alive in the document.
    await _insertBlock(
      db,
      userId,
      programId,
      blockId: 'b1',
      name: 'Accumulation',
      order: 1,
    );
    await db.execute(
      'UPDATE dim_program_block SET date_archived = ? WHERE block_id = ?',
      [DateTime.now().toUtc().toIso8601String(), 'b1'],
    );
    await _insertGoal(
      db,
      userId,
      programId,
      goalId: 'g1',
      blockId: 'b1',
      text: 'Sleep eight hours',
    );
    final push = await planned.createPlannedSession(userId, name: 'Push');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
      blockId: 'b1',
    );

    final content = await history.buildContent(
      userId: userId,
      programId: programId,
    );

    expect(content.blocks, isEmpty);
    expect(
      content.goals.single.blockId,
      'b1',
      reason:
          'the goal row is still live and still says which phase it '
          'belongs to — the scope is stored, not resolved, so archiving a '
          'block does not silently re-scope what the user aimed at',
    );
  });

  test(
    'completing a review records the live program, never the proposal',
    () async {
      final push = await planned.createPlannedSession(userId, name: 'Push');
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
      final benchSet = await planned.createPlannedSet(
        userId,
        bench.plannedExerciseId,
        plannedSessionId: push.sessionId,
        setNumber: 1,
        targetWeight: '70',
        targetReps: '5',
      );

      final live = await history.buildContent(
        userId: userId,
        programId: programId,
      );
      final proposal = _withTarget(live, benchSet.plannedSetId, '120');
      expect(proposal.contentHash, isNot(live.contentHash));

      final review = await history.scheduleReview(
        userId: userId,
        programId: programId,
        title: 'Add load',
        notes: 'Bench is too easy.',
        scheduledFor: DateTime.now(),
        proposedContent: proposal,
      );
      expect(
        review.kind,
        kReviewKindChange,
        reason:
            'a proposal IS the change flavour — the kind is not a '
            'separate choice the caller could get wrong',
      );
      expect(review.proposedHash, proposal.contentHash);
      expect(
        review.proposal!.contentHash,
        proposal.contentHash,
        reason: 'the stored proposal decodes back to what was proposed',
      );

      final applied = await history.completeReview(
        review.reviewId,
        userId: userId,
        outcome: kOutcomeApplied,
      );
      expect(applied.snapshot, isNotNull);

      // Nothing copied the proposal into the rows it describes. Applying a change
      // means the user edited the program through the normal editor, and this
      // records what that produced — so the live program is byte-identical to
      // what it was before the review was even scheduled.
      final afterLive = await history.buildContent(
        userId: userId,
        programId: programId,
      );
      expect(afterLive.contentHash, live.contentHash);
      expect(
        applied.snapshotHash,
        live.contentHash,
        reason: 'the snapshot is of the LIVE rows',
      );

      final stored = await db.getAll(
        'SELECT target_weight FROM dim_planned_session_exercise_set '
        'WHERE planned_set_id = ?',
        [benchSet.plannedSetId],
      );
      expect(stored.single['target_weight'], '70');
      expect(
        applied
            .snapshot!
            .sessions
            .single
            .exercises
            .single
            .sets
            .single
            .targetWeight,
        '70',
        reason: 'the proposed 120 appears nowhere in the snapshot that was cut',
      );
    },
  );

  test(
    'a run that has reached its length stays current until it is ended',
    () async {
      // A finished-but-still-current run: a frequency run whose end date has
      // passed. This is exactly the state that used to make `getProgress` call
      // `endCurrentRun` from inside itself — so opening the library silently
      // ended a program, with nothing recording why or when.
      await _insertRun(
        db,
        userId,
        programId,
        runId: 'r1',
        progressionMode: 'frequency',
        endDate: DateTime.now().subtract(const Duration(days: 3)),
      );
      final runs = ProgramRunRepository();

      final first = await runs.getProgress(userId);
      expect(first, isNotNull);
      expect(
        first!.isLengthReached,
        isTrue,
        reason: 'the fixture is a run whose length has run out',
      );

      final second = await runs.getProgress(userId);
      expect(second, isNotNull);
      expect(second!.isLengthReached, isTrue);

      final rows = await db.getAll(
        'SELECT is_current, ended_date FROM fact_program_run WHERE program_run_id = ?',
        ['r1'],
      );
      expect(
        rows.single['is_current'],
        1,
        reason: 'a read that mutates is the bug this asserts against',
      );
      expect(rows.single['ended_date'], isNull);

      // The question the removal exists to ask. Without this the run would sit
      // finished and unremarked — silent, which is the other half of the bug.
      final due = await ProgramHistoryRepository().fetchDueItems(userId);
      final finished = due.where((d) => d.kind == kDueRunFinished).toList();
      expect(finished, hasLength(1));
      expect(finished.single.programId, programId);
      expect(
        finished.single.blockId,
        isNull,
        reason: 'a blockless run finishes the program, not a block',
      );

      // And the answer still works: ending it is the user's act, and it lands.
      await runs.endCurrentRun(userId);
      final after = await runs.getProgress(userId);
      expect(after, isNull, reason: 'no current run left to read');
    },
  );

  test(
    'a planned start prompts, and only for the block the sequence is on',
    () async {
      // Blocks run in order, so a passed start date is only worth a prompt on the
      // one the program is actually up to — and only while nothing is running.
      final now = DateTime.now();
      await _insertBlock(
        db,
        userId,
        programId,
        blockId: 'b1',
        name: 'Accumulation',
        order: 1,
        targetWeeks: 4,
        startDate: now.subtract(const Duration(days: 3)),
      );
      await _insertBlock(
        db,
        userId,
        programId,
        blockId: 'b2',
        name: 'Intensification',
        order: 2,
        targetWeeks: 4,
        startDate: now.subtract(const Duration(days: 1)),
      );

      Future<List<DueItem>> starts() async => (await history.fetchDueItems(
        userId,
      )).where((d) => d.kind == kDueBlockStart).toList();

      // Nothing has been run: the sequence is on block 1, and block 2's date has
      // also passed — but only one prompt is owed, for the phase to do now.
      final first = await starts();
      expect(first, hasLength(1));
      expect(first.single.blockId, 'b1');
      expect(first.single.blockName, 'Accumulation');
      expect(first.single.programId, programId);

      // Block 1 ended: the sequence moves, and the prompt moves with it.
      await _insertRun(
        db,
        userId,
        programId,
        runId: 'r1',
        blockId: 'b1',
        isCurrent: false,
        endedDate: now.subtract(const Duration(hours: 2)),
      );
      final moved = await starts();
      expect(
        moved.single.blockId,
        'b2',
        reason:
            'an ended phase is behind you — its old start date has been '
            'answered and must not be asked again',
      );

      // A run open on block 2 — paused here, and current behaves the same — is
      // not waiting on a start date: it is already under way.
      await _insertRun(
        db,
        userId,
        programId,
        runId: 'r2',
        blockId: 'b2',
        isCurrent: false,
      );
      expect(
        await starts(),
        isEmpty,
        reason: 'the prompt begins a run, and a run is already open',
      );

      // Every block run: the program is finished, and nextBlock's wrap is what
      // makes it repeatable — so prompting to re-begin it on block 1's old start
      // date would be a nag that never goes away.
      await db.execute(
        'UPDATE fact_program_run SET ended_date = ? WHERE program_run_id = ?',
        [now.toIso8601String(), 'r2'],
      );
      expect(
        await starts(),
        isEmpty,
        reason: 'a finished program has nothing due',
      );
    },
  );

  test(
    'the achievements window opens at the run\'s start on a first run',
    () async {
      // Nothing has ever checkpointed this program, so the caller's fallback is
      // the only anchor there is. The fallback used to be ignored in favour of
      // `now`, which made a first-ever run's window `[now, now]` — its close
      // review derived nothing however much was lifted during it.
      final runStart = DateTime(2026, 5, 1, 9);
      expect(
        await history.checkpointFor(programId, fallback: runStart),
        runStart,
      );

      // A completed review is a checkpoint and outranks the run's start: the
      // window opens where the last one ended, so nothing is claimed twice.
      final reviewedAt = DateTime(2026, 5, 20, 12);
      await _insertCompletedReview(
        db,
        userId,
        programId,
        reviewId: 'rev-a',
        completedDate: reviewedAt,
      );
      expect(
        await history.checkpointFor(programId, fallback: runStart),
        reviewedAt,
      );

      // A caller with no run to point back to still gets "now" — the panel is
      // not showing a run, so there is no start to prefer.
      final before = DateTime.now();
      expect(
        (await history.checkpointFor('some-other-program')).isBefore(before),
        isFalse,
      );
    },
  );

  test('a checkpoint answers only for its own scope', () async {
    // Scope, not partition: the program's checkpoints and each block's are
    // separate streams. Cross them and a report either claims training nobody
    // looked at or forgets training that was reviewed somewhere else.
    final programLevel = DateTime(2026, 5, 10, 9);
    final blockLevel = DateTime(2026, 5, 20, 9);
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-p',
      completedDate: programLevel,
    );
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-b',
      blockId: 'b1',
      completedDate: blockLevel,
    );

    // A block's window opens at that block's last review, untouched by the
    // program's — which is LATER than the block's, so an unscoped read would
    // have answered with the wrong date rather than by luck with the right one.
    expect(await history.checkpointFor(programId, blockId: 'b1'), blockLevel);

    // And the program's opens at the program's own: a block review is not a
    // program checkpoint, so a program review after several block reviews
    // reports the whole program since the last program review.
    expect(await history.checkpointFor(programId), programLevel);

    // The third scope, and the one that catches the missing `session_id IS
    // NULL` clauses. This review is INSIDE b1 and LATER than the block's own,
    // so a block read without that clause answers with the session's date —
    // wrong by luck of the ordering, which is exactly how it would go
    // unnoticed.
    final sessionLevel = DateTime(2026, 5, 28, 9);
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-s',
      blockId: 'b1',
      sessionId: 's1',
      completedDate: sessionLevel,
    );

    expect(
      await history.checkpointFor(programId, blockId: 'b1'),
      blockLevel,
      reason: 'a session review inside the block is not the block itself',
    );
    expect(
      await history.checkpointFor(programId),
      programLevel,
      reason: 'nor the program, despite carrying the block id',
    );
    // And the session answers for itself.
    expect(
      await history.checkpointFor(programId, sessionId: 's1'),
      sessionLevel,
    );
    // A session with no reviews of its own does NOT inherit the block's —
    // scope is not containment.
    final sessionStart = DateTime(2026, 6, 1);
    expect(
      await history.checkpointFor(
        programId,
        sessionId: 's2',
        fallback: sessionStart,
      ),
      sessionStart,
    );

    // A block that has never been reviewed falls through to its run's start —
    // the fallback is per scope too, or a first run of a second block would
    // open at the first block's checkpoint.
    final blockStart = DateTime(2026, 6, 1);
    expect(
      await history.checkpointFor(
        programId,
        blockId: 'b2',
        fallback: blockStart,
      ),
      blockStart,
    );
  });

  test(
    'closing a run freezes its record and reads the run\'s sessions back',
    () async {
      // The round trip that matters: sessions are attributed to the run by the
      // id the close record carries. Address either with a different id and the
      // record freezes an empty run — the failure D1 produced in production.
      final started = DateTime(2026, 5, 2, 10);
      await _insertRun(db, userId, programId, runId: 'r1', blockId: 'b1');
      await _insertSession(
        db,
        userId,
        runId: 'r1',
        sessionId: 's1',
        name: 'Push',
        createdDate: started,
      );
      // Still being trained: an abandoned start has produced nothing to review.
      await _insertSession(
        db,
        userId,
        runId: 'r1',
        sessionId: 's2',
        name: 'Pull',
        createdDate: started,
        completed: false,
      );

      final frozen = ProgramAchievements(
        from: started,
        sessions: [
          AchievementSession(sessionId: 's1', name: 'Push', date: started),
        ],
      );

      final close = await history.closeRun(
        userId: userId,
        programId: programId,
        runId: 'r1',
        blockId: 'b1',
        achievementsJson: frozen.encode(),
      );
      expect(
        close.programRunId,
        'r1',
        reason: 'the record names the run it closes',
      );
      expect(close.blockId, 'b1');
      expect(close.kind, kReviewKindClose);
      expect(close.outcome, kOutcomeClosed);
      expect(close.sessionId, isNull);

      final reviews = await db.getAll(
        'SELECT program_run_id, block_id, kind, outcome, completed_date, '
        'achievements_json FROM fact_program_review WHERE program_id = ?',
        [programId],
      );
      expect(reviews, hasLength(1));
      expect(reviews.single['program_run_id'], 'r1');
      expect(reviews.single['kind'], kReviewKindClose);
      expect(reviews.single['outcome'], kOutcomeClosed);
      expect(
        reviews.single['completed_date'],
        isNotNull,
        reason:
            'a close review is complete the moment it is cut — an open '
            'one would come back as a due item',
      );
      expect(reviews.single['block_id'], 'b1');

      // What was frozen is what a closed run's panel will render — the decoder
      // is the same one the UI uses, so this is the whole read path.
      final decoded = ProgramAchievements.decode(
        reviews.single['achievements_json'] as String,
      );
      expect(decoded!.sessions.single.sessionId, 's1');

      final window = (
        from: started.subtract(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 1)),
      );
      final sessions = await history.fetchScopedSessions(
        programId: programId,
        from: window.from,
        to: window.to,
        blockId: 'b1',
      );
      expect(
        sessions.map((s) => s.sessionId),
        ['s1'],
        reason:
            'only completed sessions — an in-progress one has produced '
            'nothing yet',
      );
      expect(sessions.single.name, 'Push');

      // Scope is a predicate, not a label. Another block's read misses this
      // block's session...
      expect(
        await history.fetchScopedSessions(
          programId: programId,
          from: window.from,
          to: window.to,
          blockId: 'b2',
        ),
        isEmpty,
      );
      // ...and the program's read takes every run of it, block runs included: a
      // review of a blocked program that reported none of them would report a
      // program that never trained.
      expect(
        (await history.fetchScopedSessions(
          programId: programId,
          from: window.from,
          to: window.to,
        )).map((s) => s.sessionId),
        ['s1'],
      );

      // The window is a window, not a decoration on the scope.
      expect(
        await history.fetchScopedSessions(
          programId: programId,
          from: started.add(const Duration(days: 1)),
          to: window.to,
        ),
        isEmpty,
        reason:
            'a session before the window opened belongs to the checkpoint '
            'that already reported it',
      );
    },
  );

  test(
    'the derivation reports the sessions of its scope, and only those',
    () async {
      // The plan's "one derivation, two scopes": a block's review reports that
      // block's training, the program's reports the whole program's. Both come
      // out of the same call, so a closed block and a program review of the same
      // window cannot disagree about what happened — they answer different
      // questions.
      final derivation = AchievementsDerivation();
      final from = DateTime(2026, 5, 1);
      final to = DateTime(2026, 6, 1);

      await _insertRun(db, userId, programId, runId: 'run-a', blockId: 'b1');
      await _insertSession(
        db,
        userId,
        runId: 'run-a',
        sessionId: 's-a',
        name: 'Push A',
        createdDate: DateTime(2026, 5, 2),
      );
      await _insertRun(
        db,
        userId,
        programId,
        runId: 'run-b',
        blockId: 'b2',
        isCurrent: false,
      );
      await _insertSession(
        db,
        userId,
        runId: 'run-b',
        sessionId: 's-b',
        name: 'Push B',
        createdDate: DateTime(2026, 5, 3),
      );
      // Freestyle training between the two runs: no run, so no program can
      // claim it — attribution is what keeps a review from reporting the user's
      // whole training as the program's.
      await _insertSession(
        db,
        userId,
        runId: null,
        sessionId: 's-free',
        name: 'Freestyle',
        createdDate: DateTime(2026, 5, 4),
      );

      final inBlock = await derivation.derive(
        userId: userId,
        from: from,
        until: to,
        programId: programId,
        blockId: 'b1',
      );
      expect(inBlock.sessions.map((s) => s.sessionId), [
        's-a',
      ], reason: 'a block review reports the block');

      final whole = await derivation.derive(
        userId: userId,
        from: from,
        until: to,
        programId: programId,
      );
      expect(
        whole.sessions.map((s) => s.sessionId),
        ['s-a', 's-b'],
        reason:
            'a program review spans every run of the program, block runs '
            'included — otherwise a review of a blocked program would report '
            'a program that never trained',
      );
    },
  );
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

/// A run row, written directly for the same reason the program row is:
/// `startProgramRun` writes to Supabase REST first (the authoritative write),
/// and the read path under test here is local.
Future<void> _insertRun(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String runId,
  String? progressionMode,
  DateTime? endDate,
  String? blockId,
  bool isCurrent = true,
  DateTime? endedDate,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_program_run
      (id, program_run_id, program_id, user_id, target_sessions, target_weeks,
       end_date, started_date, ended_date, is_current, progression_mode,
       block_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      runId,
      runId,
      programId,
      userId,
      null,
      null,
      endDate?.toUtc().toIso8601String(),
      now,
      endedDate?.toUtc().toIso8601String(),
      isCurrent ? 1 : 0,
      progressionMode,
      blockId,
    ],
  );
}

/// A phase of a program. Written directly for the same reason the run is: the
/// real create is REST-first, and what is under test is the local read.
Future<void> _insertBlock(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String blockId,
  required String name,
  required int order,
  DateTime? startDate,
  int? targetWeeks,
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
      targetWeeks,
      null,
      null,
      startDate?.toIso8601String(),
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
  String? exerciseId,
  String? variationId,
  num? weight,
  int? reps,
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
      exerciseId,
      variationId,
      weight,
      reps,
      DateTime.now().toUtc().toIso8601String(),
    ],
  );
}

/// A logged session. `end_datetime` is the completed/abandoned distinction the
/// achievements read depends on, so it is the one field worth a parameter.
Future<void> _insertSession(
  PowerSyncDatabase db,
  String userId, {

  /// Null is a real value here — a freestyle session belongs to no run, which
  /// is exactly what keeps a program from claiming it.
  required String? runId,
  required String sessionId,
  required String name,
  required DateTime createdDate,
  bool completed = true,
}) async {
  await db.execute(
    '''
    INSERT INTO fact_session
      (id, session_id, user_id, created_datetime, end_datetime,
       planned_session_name, program_run_id)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      sessionId,
      sessionId,
      userId,
      // Written UTC like the app writes it, so the read path's date parsing is
      // exercised against a realistic row rather than a hand-shaped one.
      createdDate.toUtc().toIso8601String(),
      completed
          ? createdDate.add(const Duration(hours: 1)).toUtc().toIso8601String()
          : null,
      name,
      runId,
    ],
  );
}

/// A review that has already been completed — the checkpoint [checkpointFor]
/// looks for. Written directly because the read under test orders by
/// `completed_date`, which `completeReview` would stamp with "now".
Future<void> _insertCompletedReview(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String reviewId,
  required DateTime completedDate,
  String? blockId,
  String? sessionId,
}) async {
  final stamp = completedDate.toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_program_review
      (id, review_id, user_id, program_id, block_id, session_id, kind,
       completed_date, outcome, created_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      reviewId,
      reviewId,
      userId,
      programId,
      blockId,
      sessionId,
      kReviewKindReview,
      stamp,
      kOutcomeReviewed,
      stamp,
    ],
  );
}

/// Schedules a review and completes it, the way the UI does — one call for the
/// overwhelmingly common "take a checkpoint" shape.
///
/// Deliberately not one repository call: the two steps are separate on
/// purpose, because a review is a row that exists while it is OPEN. A helper
/// that hid both would let a test pass while never exercising the open state
/// the timeline actually renders.
Future<ProgramReview> _checkpoint(
  ProgramHistoryRepository history,
  String userId,
  String programId, {
  String? blockId,
  String? sessionId,
  String? notes,
}) async {
  final review = await history.scheduleReview(
    userId: userId,
    programId: programId,
    blockId: blockId,
    sessionId: sessionId,
    notes: notes,
  );
  return history.completeReview(
    review.reviewId,
    userId: userId,
    outcome: kOutcomeReviewed,
    notes: notes,
  );
}

/// The same document with one set's target changed. A proposal is a document
/// carrying the same ids it describes, so building one is a copy with one value
/// replaced rather than a second format to keep in step.
ProgramContent _withTarget(
  ProgramContent source,
  String plannedSetId,
  String targetWeight,
) => ProgramContent(
  blocks: source.blocks,
  sessions: [
    for (final session in source.sessions)
      ContentSession(
        sessionId: session.sessionId,
        userId: session.userId,
        name: session.name,
        notes: session.notes,
        createdDate: session.createdDate,
        sequenceOrder: session.sequenceOrder,
        dayOfWeek: session.dayOfWeek,
        weekOffset: session.weekOffset,
        blockId: session.blockId,
        exercises: [
          for (final exercise in session.exercises)
            ContentExercise(
              plannedExerciseId: exercise.plannedExerciseId,
              plannedSessionId: exercise.plannedSessionId,
              userId: exercise.userId,
              exerciseId: exercise.exerciseId,
              exerciseOrder: exercise.exerciseOrder,
              sets: [
                for (final set in exercise.sets)
                  if (set.plannedSetId == plannedSetId)
                    ContentSet(
                      plannedSetId: set.plannedSetId,
                      plannedExerciseId: set.plannedExerciseId,
                      plannedSessionId: set.plannedSessionId,
                      userId: set.userId,
                      variationId: set.variationId,
                      setNumber: set.setNumber,
                      targetWeight: targetWeight,
                      targetReps: set.targetReps,
                      targetNotes: set.targetNotes,
                    )
                  else
                    set,
              ],
            ),
        ],
      ),
  ],
);
