import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/models/program_revision.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/features/programs/model/program_revision_diff.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL repos against a REAL PowerSync SQLite DB (real
/// client schema, real read/write path) — the exact code the history screen and
/// the run read path execute, minus the network. Run with:
///
///   flutter test integration_test/program_history_repo_test.dart -d DEVICE
///
/// Host `flutter test` cannot load `libpowersync.dylib`, and `openDatabase()`
/// is not usable here (it wants a signed-in session and the app container), so
/// the global DB is pointed at a throwaway database with
/// [ps.setDatabaseForTesting] — repositories resolve `ps.db` per call, so the
/// real ones work unmodified.
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

  test('a capture is numbered, projected and durably stored', () async {
    final first = await history.captureRevision(
      userId: userId,
      programId: programId,
      reason: kRevisionCreated,
    );

    expect(first.revisionNumber, 1);
    expect(first.sessionCount, 0, reason: 'the program starts empty');
    expect(first.setCount, 0);
    expect(first.content, isNotNull,
        reason: 'the document must decode — a schema-1 payload the reader knows');

    // Read straight from the table the client schema declares: if
    // `schema.dart` and the INSERT disagreed on any column, the write would
    // have thrown above rather than landing here.
    final rows = await db.getAll(
      'SELECT revision_id, revision_number, reason, session_count, content_hash '
      'FROM fact_program_revision WHERE program_id = ?',
      [programId],
    );
    expect(rows.length, 1);
    expect(rows.single['revision_number'], 1);
    expect(rows.single['reason'], kRevisionCreated);
    expect(rows.single['session_count'], 0);
    expect(rows.single['content_hash'], first.contentHash);
    expect(rows.single['revision_id'], isNotEmpty,
        reason: 'the stream aliases revision_id as id; both must be written');

    // A reason the CHECK constraint would refuse never reaches the table — it
    // is rejected before any work, so nothing is left queued for upload.
    await expectLater(
      history.captureRevision(
        userId: userId,
        programId: programId,
        reason: 'whenever',
      ),
      throwsArgumentError,
    );
    expect(
      (await db.getAll(
        'SELECT revision_id FROM fact_program_revision WHERE program_id = ?',
        [programId],
      )).length,
      1,
    );
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

    final v1 = await history.captureRevision(
      userId: userId,
      programId: programId,
      reason: kRevisionCreated,
    );
    expect(v1.revisionNumber, 1);
    expect(v1.sessionCount, 2);
    expect(v1.exerciseCount, 3);
    expect(v1.setCount, 3);

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

    final v2 = await history.captureRevision(
      userId: userId,
      programId: programId,
      reason: kRevisionManual,
    );
    expect(v2.revisionNumber, 2,
        reason: 'the number is claimed inside the capture transaction');
    expect(v2.contentHash, isNot(v1.contentHash));
    expect(v2.setCount, 4, reason: 'the added set is in the new document');

    final diff = diffRevisions(v1.content!, v2.content!);
    expect(diff.movedCount, 1,
        reason: 'a two-workout swap is ONE move — the LCS is what makes a '
            'reorder read as one line rather than reporting both');
    expect(diff.addedCount, 1, reason: 'the second Row target set');
    expect(diff.editedCount, greaterThanOrEqualTo(1),
        reason: 'the retargeted Bench set');
    expect(diff.removedCount, 0);

    // Newest first — the order the timeline renders — and every stored
    // document still decodes.
    final timeline = await history.fetchRevisions(programId);
    expect(timeline.map((r) => r.revisionNumber), [2, 1]);
    expect(timeline.every((r) => r.content != null), isTrue);
    expect((await history.fetchLatestRevision(programId))?.revisionNumber, 2);
  });

  test('a review comes due, and completing it cuts a version', () async {
    await history.captureRevision(
      userId: userId,
      programId: programId,
      reason: kRevisionCreated,
    );

    final review = await history.scheduleReview(
      userId: userId,
      programId: programId,
      title: 'Block 1 check-in',
      notes: 'How did the first four weeks go?',
      // Yesterday, i.e. due now: the prompt appears the moment its day has
      // arrived, not at whatever hour the row happens to carry.
      scheduledFor: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(review.kind, kReviewKindReview,
        reason: 'no proposal ⇒ the plain flavour');
    expect(review.hasProposal, isFalse);
    expect(review.isOpen, isTrue);
    expect(review.isDue(DateTime.now()), isTrue);

    final due = await history.fetchDueItems(userId);
    final mine = due.where((d) => d.programId == programId).toList();
    expect(mine.length, 1, reason: 'exactly one thing is waiting on this program');
    expect(mine.single.kind, kDueReview);
    expect(mine.single.isReviewDue, isTrue);
    expect(mine.single.review?.reviewId, review.reviewId,
        reason: 'the due item IS the row, not a copy of its fields');

    final revision = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeReviewed,
      notes: 'Good progress.',
    );
    expect(revision, isNotNull,
        reason: 'reviewing cuts a version — that is what a checkpoint is');
    expect(revision!.reason, kRevisionReview);
    expect(revision.revisionNumber, 2);
    expect(revision.reviewId, review.reviewId);

    // The pairing is persisted, not merely returned: a completed review whose
    // revision went missing is the failure the shared transaction exists to
    // prevent, and this is what would catch a regression in it.
    final rows = await db.getAll(
      'SELECT revision_number, reason, review_id FROM fact_program_revision '
      'WHERE program_id = ? ORDER BY revision_number',
      [programId],
    );
    expect(rows.length, 2);
    expect(rows.last['reason'], kRevisionReview);
    expect(rows.last['review_id'], review.reviewId);

    final completed = await history.fetchReview(review.reviewId);
    expect(completed!.isCompleted, isTrue);
    expect(completed.outcome, kOutcomeReviewed);
    expect(completed.revisionId, revision.revisionId);
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
    expect(
      await history.completeReview(
        dismissed.reviewId,
        userId: userId,
        outcome: kOutcomeDismissed,
      ),
      isNull,
      reason: 'a dismissal returns no revision because it cuts none',
    );
    expect((await history.fetchReview(dismissed.reviewId))!.isCompleted, isTrue);
    expect((await history.fetchRevisions(programId)).length, 2);
    expect(await history.checkpointFor(programId), window);
  });

  test('completing a review records the live program, never the proposal',
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

    final live = await history.buildContent(userId: userId, programId: programId);
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
    expect(review.kind, kReviewKindChange,
        reason: 'a proposal IS the change flavour — the kind is not a '
            'separate choice the caller could get wrong');
    expect(review.proposedHash, proposal.contentHash);
    expect(review.proposal!.contentHash, proposal.contentHash,
        reason: 'the stored proposal decodes back to what was proposed');

    final revision = await history.completeReview(
      review.reviewId,
      userId: userId,
      outcome: kOutcomeApplied,
    );
    expect(revision, isNotNull);

    // Nothing copied the proposal into the rows it describes. Applying a change
    // means the user edited the program through the normal editor, and this
    // records what that produced — so the live program is byte-identical to
    // what it was before the review was even scheduled.
    final afterLive =
        await history.buildContent(userId: userId, programId: programId);
    expect(afterLive.contentHash, live.contentHash);
    expect(revision!.contentHash, live.contentHash,
        reason: 'the revision is a snapshot of the LIVE rows');

    final stored = await db.getAll(
      'SELECT target_weight FROM dim_planned_session_exercise_set '
      'WHERE planned_set_id = ?',
      [benchSet.plannedSetId],
    );
    expect(stored.single['target_weight'], '70');
    expect(
      revision.content!.sessions.single.exercises.single.sets.single.targetWeight,
      '70',
      reason: 'the proposed 120 appears nowhere in the version that was cut',
    );
  });

  test('a run that has reached its length stays current until it is ended',
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
    expect(first!.isLengthReached, isTrue,
        reason: 'the fixture is a run whose length has run out');

    final second = await runs.getProgress(userId);
    expect(second, isNotNull);
    expect(second!.isLengthReached, isTrue);

    final rows = await db.getAll(
      'SELECT is_current, ended_date FROM fact_program_run WHERE program_run_id = ?',
      ['r1'],
    );
    expect(rows.single['is_current'], 1,
        reason: 'a read that mutates is the bug this asserts against');
    expect(rows.single['ended_date'], isNull);

    // The question the removal exists to ask. Without this the run would sit
    // finished and unremarked — silent, which is the other half of the bug.
    final due = await ProgramHistoryRepository().fetchDueItems(userId);
    final finished = due.where((d) => d.kind == kDueRunFinished).toList();
    expect(finished, hasLength(1));
    expect(finished.single.programId, programId);
    expect(finished.single.blockId, isNull,
        reason: 'a blockless run finishes the program, not a block');

    // And the answer still works: ending it is the user's act, and it lands.
    await runs.endCurrentRun(userId);
    final after = await runs.getProgress(userId);
    expect(after, isNull, reason: 'no current run left to read');
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
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_program_run
      (id, program_run_id, program_id, user_id, target_sessions, target_weeks,
       end_date, started_date, ended_date, is_current, progression_mode)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      null,
      1,
      progressionMode,
    ],
  );
}

/// The same document with one set's target changed. A proposal is a document
/// carrying the same ids it describes, so building one is a copy with one value
/// replaced rather than a second format to keep in step.
ProgramRevisionContent _withTarget(
  ProgramRevisionContent source,
  String plannedSetId,
  String targetWeight,
) =>
    ProgramRevisionContent(
      blocks: source.blocks,
      sessions: [
        for (final session in source.sessions)
          RevisionSession(
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
                RevisionExercise(
                  plannedExerciseId: exercise.plannedExerciseId,
                  plannedSessionId: exercise.plannedSessionId,
                  userId: exercise.userId,
                  exerciseId: exercise.exerciseId,
                  exerciseOrder: exercise.exerciseOrder,
                  sets: [
                    for (final set in exercise.sets)
                      if (set.plannedSetId == plannedSetId)
                        RevisionSet(
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
