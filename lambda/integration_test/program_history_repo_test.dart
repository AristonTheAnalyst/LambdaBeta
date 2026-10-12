import 'dart:convert';
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
/// [ps.swapDatabase] — repositories resolve `ps.db` per call, so the
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
    ps.swapDatabase(db);
    planned = PlannedSessionRepository();
    history = ProgramHistoryRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a completed review writes its snapshot durably', () async {
    final push = await planned.createPlannedSession(userId, name: 'Push');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );

    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
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

  test('an ad-hoc set review persists its scope and no schedule', () async {
    // The "review these workouts now" path, which is not a reminder about
    // anything: no `scheduled_for`, and a stored set naming the plans being
    // examined rather than a logged session.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');

    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId, pull.sessionId],
      title: 'Second look at Push',
    );

    expect(review.scheduledFor, isNull);
    expect(review.isDue(DateTime.now()), isFalse,
        reason: 'an unscheduled review is never "due" — it is just open');

    final rows = await db.getAll(
      'SELECT session_ids_json, block_id, session_id, scheduled_for, '
      'completed_date FROM fact_program_review WHERE review_id = ?',
      [review.reviewId],
    );
    expect(rows.length, 1);
    expect(
      jsonDecode(rows.single['session_ids_json'] as String),
      [push.sessionId, pull.sessionId],
      reason: 'the scope has to survive the round trip, not just the object',
    );
    expect(
      review.storedSessionIds,
      [push.sessionId, pull.sessionId],
      reason: 'and read back as the same set through the model',
    );
    expect(
      rows.single['block_id'],
      isNull,
      reason: 'a set review writes neither legacy scope column — the old '
          'spelling is only kept for the rows that predate the set',
    );
    expect(rows.single['session_id'], isNull);
    expect(rows.single['scheduled_for'], isNull);
    expect(rows.single['completed_date'], isNull);
  });

  test('a review of nothing is refused — an empty set would claim the whole '
      'program', () async {
    // An empty set stores no scope, and a scoped row that stores nothing
    // resolves to every workout of the program: a look nobody took, recorded
    // as a checkpoint. The client has to refuse it in Dart, because nothing
    // in the database can — a row with no set and no legacy column is exactly
    // the legal shape of an old program review.
    await expectLater(
      history.scheduleReview(
        userId: userId,
        programId: programId,
        sessionIds: const [],
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

    // A pass over both workouts — the program's whole ground, ticked as a set.
    final v1 = await _checkpoint(
      history,
      userId,
      programId,
      sessionIds: [push.sessionId, pull.sessionId],
    );
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

    final v2 = await _checkpoint(
      history,
      userId,
      programId,
      sessionIds: [push.sessionId, pull.sessionId],
    );
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
    final push = await planned.createPlannedSession(userId, name: 'Push');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );

    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
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
      sessionIds: [push.sessionId],
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
    'completing a review snapshots the live program — the record never '
    'writes back to the rows',
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

      final review = await history.scheduleReview(
        userId: userId,
        programId: programId,
        sessionIds: [push.sessionId],
        title: 'Bench check',
        notes: 'How is the bench holding up?',
        scheduledFor: DateTime.now(),
      );
      expect(
        review.kind,
        kReviewKindReview,
        reason:
            'a review is the one kind there is — proposing a change was a '
            'second way to describe editing the thing in front of you',
      );
      expect(review.proposedContent, isNull);

      final finished = await history.completeReview(
        review.reviewId,
        userId: userId,
        outcome: kOutcomeReviewed,
      );
      expect(finished.snapshot, isNotNull);

      // Finishing records what the plan IS. The review row is a record, not a
      // writer: the live program is byte-identical to what it was before the
      // review was even scheduled.
      final afterLive = await history.buildContent(
        userId: userId,
        programId: programId,
      );
      expect(afterLive.contentHash, live.contentHash);
      expect(
        finished.snapshotHash,
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
        finished
            .snapshot!
            .sessions
            .single
            .exercises
            .single
            .sets
            .single
            .targetWeight,
        '70',
        reason: 'the snapshot carries the live target, read from the rows',
      );
    },
  );

  test('review notes round-trip: keyed to the exercise, clearable, durable',
      () async {
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final bench = await planned.createPlannedExercise(
      userId,
      push.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );

    final review = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
    );

    await history.setExerciseNote(
      review.reviewId,
      bench.plannedExerciseId,
      note: '  Drop to 55 if it grinds  ',
    );

    // Read back through a FRESH repository: the note lives on the row, not in
    // anything this instance is holding on to.
    final read = await ProgramHistoryRepository().fetchReview(review.reviewId);
    expect(
      read!.exerciseNotes[bench.plannedExerciseId],
      'Drop to 55 if it grinds',
      reason: 'trimmed on the way in, the way every note in the app is',
    );

    // A second note for the same exercise replaces the first — one exercise,
    // one note.
    await history.setExerciseNote(
      review.reviewId,
      bench.plannedExerciseId,
      note: 'Sharpened',
    );
    var reread = await history.fetchReview(review.reviewId);
    expect(reread!.exerciseNotes[bench.plannedExerciseId], 'Sharpened');
    expect(reread.exerciseNotes, hasLength(1));

    // A blank note clears the entry, and the emptied document goes back to
    // NULL rather than lingering as '{}'.
    await history.setExerciseNote(
      review.reviewId,
      bench.plannedExerciseId,
      note: '   ',
    );
    reread = await history.fetchReview(review.reviewId);
    expect(reread!.exerciseNotes, isEmpty);
    final stored = await db.getAll(
      'SELECT exercise_notes_json FROM fact_program_review '
      'WHERE review_id = ?',
      [review.reviewId],
    );
    expect(stored.single['exercise_notes_json'], isNull);
  });

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
    'a run reaching its length is answered by finishing a review — never by '
    'the reaching itself',
    () async {
      await _insertRun(
        db,
        userId,
        programId,
        runId: 'r1',
        progressionMode: 'frequency',
        endDate: DateTime.now().subtract(const Duration(days: 3)),
      );

      final due = await history.fetchDueItems(userId);
      expect(
        due.where((d) => d.kind == kDueRunFinished).single.label,
        'Program length reached',
        reason: 'the question is up while nobody has answered it',
      );

      // The pass covers a workout that is not in the program yet — adding it
      // mid-pass is the edit the baseline has to survive.
      final push = await planned.createPlannedSession(userId, name: 'Push');

      // Opening the prompt begins a review, and the pass opens by recording
      // the plan as found — the only "before" a first-ever review can have.
      final opened = await history.beginReview(
        userId: userId,
        programId: programId,
        sessionIds: [push.sessionId],
        programRunId: 'r1',
      );
      expect(opened.hasBaseline, isTrue);
      expect(opened.programRunId, 'r1');
      expect(opened.isCompleted, isFalse);

      // The baseline is a freeze-frame of the moment the pass began. Editing
      // the plan mid-pass and re-capturing must not move it, or the compare
      // would drift into "compare with yourself".
      await planned.createProgramLink(
        userId,
        programId: programId,
        plannedSessionId: push.sessionId,
        sequenceOrder: 1,
      );
      final live = await history.buildContent(
        userId: userId,
        programId: programId,
      );
      expect(
        live.contentHash,
        isNot(opened.baselineHash),
        reason: 'the plan really did change under the pass',
      );
      final recaptured = await history.captureBaseline(
        opened.reviewId,
        userId: userId,
      );
      expect(recaptured!.baselineContent, opened.baselineContent);

      // Prompt twice is one pass: the next visit finds the row it opened.
      expect(
        (await history.fetchOpenReviewForRun('r1'))?.reviewId,
        opened.reviewId,
      );

      // And an open pass is not an answer — the question is still up.
      expect(await history.hasCompletedReviewForRun('r1'), isFalse);
      expect(
        (await history.fetchDueItems(userId))
            .where((d) => d.kind == kDueRunFinished),
        hasLength(1),
      );

      // Finishing the pass is. The run is untouched: carrying on is one of
      // the answers, so the question must not end it on the way out.
      await history.completeReview(
        opened.reviewId,
        userId: userId,
        outcome: kOutcomeReviewed,
      );
      expect(await history.hasCompletedReviewForRun('r1'), isTrue);
      expect(
        (await history.fetchDueItems(userId))
            .where((d) => d.kind == kDueRunFinished),
        isEmpty,
      );
      expect(await history.fetchOpenReviewForRun('r1'), isNull);

      final rows = await db.getAll(
        'SELECT is_current, ended_date FROM fact_program_run '
        'WHERE program_run_id = ?',
        ['r1'],
      );
      expect(rows.single['is_current'], 1);
      expect(
        rows.single['ended_date'],
        isNull,
        reason: 'the review answered the prompt; ending the run is the '
            'user\'s separate decision',
      );
    },
  );

  test('the run prompt resumes the run\'s open pass — the newest one', () async {
    // A run can carry more than one open pass: a review started from the
    // panel carries the run id too, and a scope is a set of workouts now, so
    // there is no scope column left to narrow by. What the prompt must not do
    // is open a SECOND row for a question that already has one — so it
    // resumes the newest open pass for the run.
    await _insertRun(
      db,
      userId,
      programId,
      runId: 'r1',
      blockId: 'b1',
      progressionMode: 'frequency',
    );

    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');

    final first = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId],
      programRunId: 'r1',
    );
    // The row's created_date is the order, so make the second pass strictly
    // newer rather than racing the clock.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final second = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [pull.sessionId],
      programRunId: 'r1',
    );

    expect(
      (await history.fetchOpenReviewForRun('r1'))?.reviewId,
      second.reviewId,
      reason: 'the newest open pass is the one the prompt resumes — finishing '
          'it is the answer, so the question has one row',
    );
    expect(
      await history.fetchOpenReviewForRun('r2'),
      isNull,
      reason: 'another run is another question',
    );

    // Finishing the newest leaves the older one open: the prompt then resumes
    // that one rather than opening a third.
    await history.completeReview(
      second.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );
    expect(
      (await history.fetchOpenReviewForRun('r1'))?.reviewId,
      first.reviewId,
    );
  });

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
      final push = await planned.createPlannedSession(userId, name: 'Push');
      await planned.createProgramLink(
        userId,
        programId: programId,
        plannedSessionId: push.sessionId,
        sequenceOrder: 1,
      );
      final reviewedAt = DateTime(2026, 5, 20, 12);
      await _insertCompletedReview(
        db,
        userId,
        programId,
        reviewId: 'rev-a',
        sessionIds: [push.sessionId],
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

  test('a checkpoint is about ground, not scope labels: a pass over any of it '
      'opens it', () async {
    // The re-scope's load-bearing change. Once a pass covers a SET of
    // workouts, "which reviews open this window" stops being about matching
    // scope labels and becomes intersection: a pass over any of this ground
    // is a look at all of it. The program's own window is the one asymmetric
    // case — it opens only on a pass over the program ENTIRE, because
    // reviewing part of a plan is not reviewing the plan, and letting a
    // partial pass cut it would silently swallow what was achieved since the
    // last full look.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    final legs = await planned.createPlannedSession(userId, name: 'Legs');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: pull.sessionId,
      sequenceOrder: 2,
    );
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: legs.sessionId,
      sequenceOrder: 3,
    );

    final pushPass = DateTime(2026, 5, 10, 9);
    final pullPass = DateTime(2026, 5, 20, 9);
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-push',
      sessionIds: [push.sessionId],
      completedDate: pushPass,
    );
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-pull',
      sessionIds: [pull.sessionId],
      completedDate: pullPass,
    );

    // Each workout's window opens at the pass that looked at it...
    expect(
      await history.checkpointFor(programId, sessionIds: [push.sessionId]),
      pushPass,
    );
    expect(
      await history.checkpointFor(programId, sessionIds: [pull.sessionId]),
      pullPass,
      reason: 'a pass over push is not a look at pull',
    );

    // ...and ground nobody has looked at falls through to the caller's start.
    final runStart = DateTime(2026, 6, 1);
    expect(
      await history.checkpointFor(
        programId,
        sessionIds: [legs.sessionId],
        fallback: runStart,
      ),
      runStart,
      reason: 'no pass has ever looked at this ground',
    );

    // The program's window: partial passes do not open it.
    expect(
      await history.checkpointFor(programId, fallback: runStart),
      runStart,
      reason: 'reviewing part of a plan is not reviewing the plan',
    );

    // A pass over the whole set does — and it becomes the newest look at every
    // workout in it.
    final wholePass = DateTime(2026, 5, 28, 9);
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-all',
      sessionIds: [push.sessionId, pull.sessionId, legs.sessionId],
      completedDate: wholePass,
    );
    expect(
      await history.checkpointFor(programId, fallback: runStart),
      wholePass,
    );
    expect(
      await history.checkpointFor(programId, sessionIds: [pull.sessionId]),
      wholePass,
      reason: 'the pass covers pull, so it is the newest look at it',
    );

    // A legacy session row still resolves — a workout review of push contains
    // push — so old rows keep opening the windows they always did.
    final legacyPass = DateTime(2026, 5, 30, 9);
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-legacy',
      sessionId: push.sessionId,
      completedDate: legacyPass,
    );
    expect(
      await history.checkpointFor(programId, sessionIds: [push.sessionId]),
      legacyPass,
    );
    expect(
      await history.checkpointFor(programId, fallback: runStart),
      wholePass,
      reason: 'a legacy workout row is not a pass over the program',
    );
  });

  test('Done marks a workout in the pass, unmarks it, and the marks survive '
      'a reopen', () async {
    // The tick is the pass's progress, stored on the row as it goes: a user
    // who exits mid-review and comes back must find the workouts they
    // finished still ticked. Read-modify-write keeps it additive — a second
    // Done must not drop the first.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: pull.sessionId,
      sequenceOrder: 2,
    );

    final review = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId, pull.sessionId],
    );
    expect(review.reviewedSessions, isEmpty, reason: 'nothing walked yet');

    await history.markWorkoutReviewed(review.reviewId, push.sessionId);
    final afterFirst = await history.fetchReview(review.reviewId);
    expect(afterFirst!.reviewedSessions.keys, [push.sessionId]);

    await history.markWorkoutReviewed(review.reviewId, pull.sessionId);

    // Read back through a FRESH repository: the marks live on the row, not in
    // anything this instance is holding — which is what "survives a reopen"
    // means for a user who left the app mid-review.
    final reopened = await ProgramHistoryRepository().fetchReview(
      review.reviewId,
    );
    expect(
      reopened!.reviewedSessions.keys,
      unorderedEquals([push.sessionId, pull.sessionId]),
    );

    // Re-marking overwrites the stamp rather than adding a second one, so the
    // map always says when the tick last landed.
    final at = reopened.reviewedSessions[push.sessionId]!;
    await history.markWorkoutReviewed(review.reviewId, push.sessionId);
    final reMarked = await history.fetchReview(review.reviewId);
    expect(reMarked!.reviewedSessions.keys.length, 2);
    expect(reMarked.reviewedSessions[push.sessionId]!.isBefore(at), isFalse);

    // The tick comes back off the same way it went on: Done is a toggle, and
    // one key leaving the map is the whole of it — the other tick stays.
    await history.unmarkWorkoutReviewed(review.reviewId, push.sessionId);
    final unticked = await history.fetchReview(review.reviewId);
    expect(unticked!.reviewedSessions.keys, [pull.sessionId]);

    // And the knob turns both ways: re-marking after an un-mark lands again.
    await history.markWorkoutReviewed(review.reviewId, push.sessionId);

    // A completed review takes no more marks in either direction: a late Done
    // or a late un-Done must not mutate a record that has been written.
    await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
    );
    await history.markWorkoutReviewed(review.reviewId, 'workout-late');
    await history.unmarkWorkoutReviewed(review.reviewId, push.sessionId);
    final sealed = await history.fetchReview(review.reviewId);
    expect(
      sealed!.reviewedSessions.keys,
      unorderedEquals([push.sessionId, pull.sessionId]),
    );
  });

  test('a workout compares against the newest completed pass that contains it',
      () async {
    // "Contains", not "equals": a pass over a set including this workout is a
    // look at it, so the diff answers what changed in the workout since anyone
    // last snapshotted it. A newer pass that does NOT contain it must be
    // skipped over, not compared against — its numbers would read as real and
    // answer a different workout entirely.
    final push = await planned.createPlannedSession(userId, name: 'Push');
    final pull = await planned.createPlannedSession(userId, name: 'Pull');
    final legs = await planned.createPlannedSession(userId, name: 'Legs');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: push.sessionId,
      sequenceOrder: 1,
    );
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: pull.sessionId,
      sequenceOrder: 2,
    );
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: legs.sessionId,
      sequenceOrder: 3,
    );

    ContentSession workout(String id, String name) => ContentSession(
      sessionId: id,
      userId: userId,
      name: name,
      exercises: const [],
    );
    ProgramContent contentOf(List<ContentSession> sessions) =>
        ProgramContent(sessions: sessions);

    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-push',
      sessionIds: [push.sessionId],
      snapshot: contentOf([workout(push.sessionId, 'Push')]),
      completedDate: DateTime(2026, 5, 10),
    );
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-pull',
      sessionIds: [pull.sessionId],
      snapshot: contentOf([workout(pull.sessionId, 'Pull')]),
      completedDate: DateTime(2026, 5, 20),
    );
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-all',
      sessionIds: [push.sessionId, pull.sessionId],
      snapshot: contentOf([
        workout(push.sessionId, 'Push'),
        workout(pull.sessionId, 'Pull'),
      ]),
      completedDate: DateTime(2026, 5, 25),
    );
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-pull2',
      sessionIds: [pull.sessionId],
      snapshot: contentOf([workout(pull.sessionId, 'Pull')]),
      completedDate: DateTime(2026, 5, 28),
    );

    final current = await history.beginReview(
      userId: userId,
      programId: programId,
      sessionIds: [push.sessionId, pull.sessionId, legs.sessionId],
    );

    // Pull's newest containing pass is the 28th — "contains" picks the newest
    // look at THIS workout, not the newest review of anything.
    final forPull = await history.comparisonBase(
      current,
      sessionId: pull.sessionId,
    );
    expect(forPull!.completedDate, DateTime(2026, 5, 28));
    expect(forPull.content.sessions.single.sessionId, pull.sessionId);

    // Push was passed over more often, but the pass over pull (newer) does not
    // contain it — the walk skips it for the 25th, the newest pass that does.
    final forPush = await history.comparisonBase(
      current,
      sessionId: push.sessionId,
    );
    expect(forPush!.completedDate, DateTime(2026, 5, 25));
    expect(
      forPush.content.sessions.map((s) => s.sessionId),
      [push.sessionId, pull.sessionId],
      reason: 'the base is the whole snapshot — narrowing to one workout is '
          'the comparison\'s job, not the pairing\'s',
    );

    // No completed pass has ever contained legs, so it opens on the plan as
    // found — this review's own baseline.
    final forLegs = await history.comparisonBase(
      current,
      sessionId: legs.sessionId,
    );
    expect(forLegs!.completedDate, isNull);
    expect(forLegs.asFound, isTrue);

    // A legacy session row contains its own workout, exactly as its digests
    // always read — old rows keep pairing.
    await _insertCompletedReview(
      db,
      userId,
      programId,
      reviewId: 'rev-legacy',
      sessionId: push.sessionId,
      snapshot: contentOf([workout(push.sessionId, 'Push')]),
      completedDate: DateTime(2026, 5, 29),
    );
    final againForPush = await history.comparisonBase(
      current,
      sessionId: push.sessionId,
    );
    expect(againForPush!.completedDate, DateTime(2026, 5, 29));
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
///
/// [sessionIds] writes the stored set (the modern scope); [blockId] and
/// [sessionId] write the legacy spelling — the sides are mutually exclusive,
/// as the table's rows treat them. [snapshot] is the document the row
/// carries, for the reads that compare against it.
Future<void> _insertCompletedReview(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String reviewId,
  required DateTime completedDate,
  List<String>? sessionIds,
  String? blockId,
  String? sessionId,
  ProgramContent? snapshot,
}) async {
  final stamp = completedDate.toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_program_review
      (id, review_id, user_id, program_id, block_id, session_id,
       session_ids_json, kind, completed_date, outcome, created_date,
       snapshot_content, snapshot_hash)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      reviewId,
      reviewId,
      userId,
      programId,
      blockId,
      sessionId,
      sessionIds == null ? null : jsonEncode(sessionIds),
      kReviewKindReview,
      stamp,
      kOutcomeReviewed,
      stamp,
      snapshot?.encode(),
      snapshot?.contentHash,
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
  required List<String> sessionIds,
  String? notes,
}) async {
  final review = await history.scheduleReview(
    userId: userId,
    programId: programId,
    sessionIds: sessionIds,
    notes: notes,
  );
  return history.completeReview(
    review.reviewId,
    userId: userId,
    outcome: kOutcomeReviewed,
    notes: notes,
  );
}

