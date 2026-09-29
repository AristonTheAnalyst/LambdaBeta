import 'package:uuid/uuid.dart';

import '../../core/powersync/database.dart' as ps;
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/program_history.dart';
import '../models/program_review.dart';
import '../models/program_revision.dart';
import 'planned_session_repository.dart';
import 'program_run_repository.dart';

const _uuid = Uuid();

/// Sequence order used when a link has none — sorts last, matching the
/// `ORDER BY sequence_order NULLS LAST` the link queries use.
const _unordered = 1 << 30;

/// The version history of a program's contents: cutting revisions and reading
/// them back.
///
/// Deliberately separate from [ProgramRepository] rather than bolted onto it.
/// Capturing a revision reads the entire program (links, templates, exercises,
/// sets) and writes one row, and the review work that lands on top of this
/// (Phase 2) has to complete a review and cut its revision inside a single
/// local transaction — neither belongs on the CRUD repository the rest of the
/// screens already depend on.
class ProgramHistoryRepository {
  ProgramHistoryRepository({
    PlannedSessionRepository? plannedSessionRepository,
    ProgramRunRepository? programRunRepository,
  })  : _plannedRepo = plannedSessionRepository ?? PlannedSessionRepository(),
        _runRepo = programRunRepository ?? ProgramRunRepository();

  final PlannedSessionRepository _plannedRepo;

  /// Needed for exactly two things: the "this run has reached its length"
  /// due item, and knowing a run's start when it produced no revision yet.
  /// `getProgress` is a pure read (the mutation it used to carry now lives in
  /// the ViewModel), so reading it from here is safe — but the reverse is not
  /// true: this is a read that *prompts*, so nothing may prompt from inside
  /// `getProgress`.
  final ProgramRunRepository _runRepo;

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Revisions of [programId], newest first — the order the timeline renders.
  ///
  /// [blockId] filters to revisions cut while that block was active. It is
  /// CONTEXT, not scope: every revision is a whole-program snapshot, so this
  /// is a view filter and nothing more.
  Future<List<ProgramRevision>> fetchRevisions(
    String programId, {
    int? limit,
    String? blockId,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_revision
      WHERE program_id = ?${blockId != null ? ' AND block_id = ?' : ''}
      ORDER BY revision_number DESC${limit != null ? ' LIMIT ${limit.clamp(1, 1000)}' : ''}
      ''',
      [programId, ?blockId],
    );
    return rows.map((r) => ProgramRevision.fromMap(r)).toList();
  }

  /// The most recent revision, or null if the program has never been captured.
  Future<ProgramRevision?> fetchLatestRevision(String programId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_revision
      WHERE program_id = ?
      ORDER BY revision_number DESC
      LIMIT 1
      ''',
      [programId],
    );
    if (rows.isEmpty) return null;
    return ProgramRevision.fromMap(rows.first);
  }

  // ── Capturing ────────────────────────────────────────────────────────────

  /// Reads [programId]'s live contents into a snapshot document.
  ///
  /// Active rows only, and that is the diff's own vocabulary rather than tidy:
  /// archiving a planned set or an exercise group is how the planner deletes
  /// one, so an archived row has to read as absent here — otherwise a set the
  /// user removed would never show up as a removal.
  ///
  /// Order is the join row's program-global `sequence_order` — the order
  /// 'order' runs walk and the order `reorderWorkouts` writes. A position in
  /// the returned list IS the workout's place in the program, which is what
  /// makes the diff's move detection mean anything.
  Future<ProgramRevisionContent> buildContent({
    required String userId,
    required String programId,
  }) async {
    final links = await _plannedRepo.fetchProgramLinks(programId);
    final sessions = await _plannedRepo.fetchPlannedSessions(userId,
        programId: programId);
    final sessionById = {for (final s in sessions) s.sessionId: s};

    // Ordered here rather than trusting the query's ORDER BY: this list's
    // sequence is part of the stored document, so it outlives any future
    // change to how links are fetched.
    final ordered = links
        .where((l) => sessionById.containsKey(l.plannedSessionId))
        .toList()
      ..sort((a, b) =>
          (a.sequenceOrder ?? _unordered).compareTo(b.sequenceOrder ?? _unordered));

    final snapshot = <RevisionSession>[];
    for (final link in ordered) {
      final session = sessionById[link.plannedSessionId]!;

      // Both reads are already scoped to active rows and ordered by
      // exercise_order / set_number, so grouping preserves that order.
      final exercises = await _plannedRepo.fetchPlannedExercises(session.sessionId);
      final sets = await _plannedRepo.fetchPlannedSets(session.sessionId);
      final setsByExercise = <String, List<PlannedSessionExerciseSet>>{};
      for (final set in sets) {
        setsByExercise.putIfAbsent(set.plannedExerciseId, () => []).add(set);
      }

      snapshot.add(RevisionSession(
        sessionId: session.sessionId,
        userId: userId,
        name: session.name,
        notes: session.notes,
        createdDate: session.createdDate,
        sequenceOrder: link.sequenceOrder,
        dayOfWeek: link.dayOfWeek,
        weekOffset: link.weekOffset,
        // Blocks arrive in Phase 4; the document's `block_id` key exists from
        // schema 1 so revisions cut before then stay readable after.
        blockId: null,
        exercises: exercises
            .map((e) => _exercise(e, userId, setsByExercise[e.plannedExerciseId]))
            .toList(growable: false),
      ));
    }

    return ProgramRevisionContent.fromRows(sessions: snapshot);
  }

  RevisionExercise _exercise(
    PlannedSessionExercise exercise,
    String userId,
    List<PlannedSessionExerciseSet>? sets,
  ) =>
      RevisionExercise(
        plannedExerciseId: exercise.plannedExerciseId,
        plannedSessionId: exercise.plannedSessionId,
        userId: userId,
        exerciseId: exercise.exerciseId,
        exerciseOrder: exercise.exerciseOrder,
        sets: (sets ?? const <PlannedSessionExerciseSet>[])
            .map((s) => RevisionSet(
                  plannedSetId: s.plannedSetId,
                  plannedExerciseId: s.plannedExerciseId,
                  plannedSessionId: s.plannedSessionId,
                  userId: userId,
                  variationId: s.variationId,
                  setNumber: s.setNumber,
                  targetWeight: s.targetWeight,
                  targetReps: s.targetReps,
                  targetNotes: s.targetNotes,
                ))
            .toList(growable: false),
      );

  /// Cuts a version of [programId]'s current contents and returns it.
  ///
  /// Written through a local transaction, NOT Supabase REST — unlike starting a
  /// run there is no unique index to race for, and a version the user asked for
  /// must be saveable offline.
  ///
  /// [reason] must be one of [kRevisionReasons]; anything else would be refused
  /// server-side by the CHECK constraint and sit in `upload_failures` as an
  /// opaque quarantine row, so it is rejected here instead.
  Future<ProgramRevision> captureRevision({
    required String userId,
    required String programId,
    required String reason,
    String? blockId,
    String? blockRunId,
    String? reviewId,
  }) async {
    if (!kRevisionReasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason', 'Unknown revision reason');
    }

    // Read the whole program BEFORE opening the transaction — querying from
    // inside a `writeTransaction` callback contends with the write lock that
    // transaction holds (see the note on `ProgramRepository.duplicateProgram`).
    final content = await buildContent(userId: userId, programId: programId);
    late ProgramRevision revision;

    await ps.safeWriteTransaction((tx) async {
      revision = await _insertRevision(
        tx,
        userId: userId,
        programId: programId,
        reason: reason,
        content: content,
        blockId: blockId,
        blockRunId: blockRunId,
        reviewId: reviewId,
      );
    });

    return revision;
  }

  /// Claims the next version number and inserts the row, inside a transaction
  /// the CALLER owns.
  ///
  /// Split out so completing a review can cut its revision in the same
  /// transaction as the UPDATE that marks the review complete — otherwise a
  /// crash between the two leaves a completed review pointing at a version
  /// that does not exist, or a version no review ever claimed.
  ///
  /// [content] is built by the caller, before the transaction opens: the
  /// read-before-transaction rule is not optional.
  Future<ProgramRevision> _insertRevision(
    dynamic tx, {
    required String userId,
    required String programId,
    required String reason,
    required ProgramRevisionContent content,
    String? blockId,
    String? blockRunId,
    String? reviewId,
  }) async {
    // The number is claimed inside the transaction: two captures racing on one
    // program (a review and a run close, say) must not both read the same MAX.
    // `unique (program_id, revision_number)` is the backstop across devices —
    // that collision quarantines as a 23505 rather than silently misnumbering
    // the history.
    final rows = await tx.getAll(
      'SELECT MAX(revision_number) AS max_number FROM fact_program_revision WHERE program_id = ?',
      [programId],
    );
    final revisionNumber =
        (_toInt(rows.isEmpty ? null : rows.first['max_number']) ?? 0) + 1;
    final revisionId = _uuid.v4();
    final contentJson = content.encode();
    final now = DateTime.now().toUtc();

    await tx.execute(
      '''
      INSERT INTO fact_program_revision
        (id, revision_id, user_id, program_id, block_id, block_run_id,
         review_id, revision_number, reason, content_json, content_hash,
         session_count, exercise_count, set_count, created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        revisionId,
        revisionId,
        userId,
        programId,
        blockId,
        blockRunId,
        reviewId,
        revisionNumber,
        reason,
        contentJson,
        content.contentHash,
        content.sessionCount,
        content.exerciseCount,
        content.setCount,
        now.toIso8601String(),
      ],
    );

    return ProgramRevision(
      revisionId: revisionId,
      userId: userId,
      programId: programId,
      blockId: blockId,
      blockRunId: blockRunId,
      reviewId: reviewId,
      revisionNumber: revisionNumber,
      reason: reason,
      contentJson: contentJson,
      contentHash: content.contentHash,
      sessionCount: content.sessionCount,
      exerciseCount: content.exerciseCount,
      setCount: content.setCount,
      createdDate: now,
    );
  }

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Reviews of [programId], newest first.
  Future<List<ProgramReview>> fetchReviews(
    String programId, {
    String? blockId,
    int? limit,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE program_id = ?${blockId != null ? ' AND block_id = ?' : ''}
      ORDER BY created_date DESC, review_id DESC${limit != null ? ' LIMIT ${limit.clamp(1, 1000)}' : ''}
      ''',
      [programId, ?blockId],
    );
    return rows.map((r) => ProgramReview.fromMap(r)).toList();
  }

  Future<ProgramReview?> fetchReview(String reviewId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_review WHERE review_id = ?',
      [reviewId],
    );
    if (rows.isEmpty) return null;
    return ProgramReview.fromMap(rows.first);
  }

  /// The program's open review, if one is waiting — scheduled or not.
  ///
  /// A program has at most one in practice (the UI schedules the next one when
  /// it completes the current one), but nothing enforces that: two devices
  /// scheduling offline would both land. Picking the earliest scheduled and
  /// leaving the other open is the honest read — the extra row surfaces as a
  /// due item later rather than being silently discarded.
  Future<ProgramReview?> fetchOpenReview(String programId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE program_id = ? AND completed_date IS NULL
      ORDER BY scheduled_for IS NULL, scheduled_for, created_date
      LIMIT 1
      ''',
      [programId],
    );
    if (rows.isEmpty) return null;
    return ProgramReview.fromMap(rows.first);
  }

  /// Creates a review. A non-null [proposedContent] makes it a
  /// [kReviewKindChange] — a checkpoint carrying a proposed edit — because the
  /// kind IS "has a proposal", not a separate choice the caller could get
  /// wrong.
  Future<ProgramReview> scheduleReview({
    required String userId,
    required String programId,
    String? blockId,
    String? programRunId,
    String? title,
    String? notes,
    DateTime? scheduledFor,
    ProgramRevisionContent? proposedContent,
  }) async {
    final reviewId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final json = proposedContent?.encode();

    await ps.safeExec(
      '''
      INSERT INTO fact_program_review
        (id, review_id, user_id, program_id, block_id, program_run_id, kind,
         title, notes, scheduled_for, proposed_content, proposed_hash,
         created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        reviewId,
        reviewId,
        userId,
        programId,
        blockId,
        programRunId,
        proposedContent == null ? kReviewKindReview : kReviewKindChange,
        title,
        notes,
        scheduledFor?.toUtc().toIso8601String(),
        json,
        json == null ? null : proposedContent!.contentHash,
        now.toIso8601String(),
      ],
    );

    final created = await fetchReview(reviewId);
    if (created == null) {
      throw StateError('The review was inserted but cannot be read back');
    }
    return created;
  }

  /// Replaces (or clears) an open review's proposed edit.
  ///
  /// Allowed only while the review is open — the proposal is a plan, and once
  /// the checkpoint is taken the outcome is a revision, which is immutable.
  Future<void> updateProposal(
    String reviewId,
    ProgramRevisionContent? content,
  ) async {
    final json = content?.encode();
    await ps.safeExec(
      '''
      UPDATE fact_program_review
      SET proposed_content = ?, proposed_hash = ?,
          kind = CASE WHEN ? IS NULL THEN ? ELSE ? END
      WHERE review_id = ? AND completed_date IS NULL
      ''',
      [
        json,
        json == null ? null : content!.contentHash,
        json,
        kReviewKindReview,
        kReviewKindChange,
        reviewId,
      ],
    );
  }

  /// Completes a review, cutting the revision it is a checkpoint of.
  ///
  /// The revision insert and the completion UPDATE share ONE transaction:
  /// a review marked complete with no revision behind it, or a revision no
  /// review claims, are both worse than the operation failing outright.
  ///
  /// Returns the revision, or **null when [outcome] is [kOutcomeDismissed]** —
  /// a dismissal is "not now", not a checkpoint, so it cuts nothing. It is also
  /// excluded from the achievements window ([checkpointFor]); otherwise
  /// dismissing a prompt would silently swallow everything achieved since the
  /// last real review.
  Future<ProgramRevision?> completeReview(
    String reviewId, {
    required String userId,
    required String outcome,
    String? notes,
  }) async {
    if (!kReviewOutcomes.contains(outcome)) {
      throw ArgumentError.value(outcome, 'outcome', 'Unknown review outcome');
    }
    final review = await fetchReview(reviewId);
    if (review == null) {
      throw ArgumentError.value(reviewId, 'reviewId', 'No such review');
    }
    if (review.isCompleted) return null;

    final now = DateTime.now().toUtc();

    if (outcome == kOutcomeDismissed) {
      await ps.safeExec(
        '''
        UPDATE fact_program_review
        SET completed_date = ?, outcome = ?, notes = COALESCE(?, notes)
        WHERE review_id = ? AND completed_date IS NULL
        ''',
        [now.toIso8601String(), outcome, notes, reviewId],
      );
      return null;
    }

    // The snapshot is of the LIVE rows, never of the proposal: applying a
    // change means the user edited the program through the normal editor, and
    // this records what that produced. No code path copies proposed_content
    // into live rows.
    final content = await buildContent(userId: userId, programId: review.programId);
    late ProgramRevision revision;

    await ps.safeWriteTransaction((tx) async {
      revision = await _insertRevision(
        tx,
        userId: userId,
        programId: review.programId,
        reason: kRevisionReview,
        content: content,
        blockId: review.blockId,
        blockRunId: review.programRunId,
        reviewId: reviewId,
      );
      await tx.execute(
        '''
        UPDATE fact_program_review
        SET completed_date = ?, outcome = ?, notes = COALESCE(?, notes),
            revision_id = ?
        WHERE review_id = ? AND completed_date IS NULL
        ''',
        [
          now.toIso8601String(),
          outcome,
          notes,
          revision.revisionId,
          reviewId,
        ],
      );
    });
    return revision;
  }

  // ── Achievements ─────────────────────────────────────────────────────────

  /// Where the current achievements window opens: the last checkpoint that
  /// actually looked at the program.
  ///
  /// Latest completed review → else the latest revision → else the run's start.
  /// Dismissed reviews are skipped, and that is load-bearing: a dismissal means
  /// "not now", so letting it open the window would silently swallow
  /// everything achieved since the last real review.
  Future<DateTime> checkpointFor(String programId) async {
    final reviews = await ps.db.getAll(
      '''
      SELECT completed_date FROM fact_program_review
      WHERE program_id = ? AND completed_date IS NOT NULL AND outcome <> ?
      ORDER BY completed_date DESC
      LIMIT 1
      ''',
      [programId, kOutcomeDismissed],
    );
    if (reviews.isNotEmpty) {
      final date = _toDate(reviews.first['completed_date']);
      if (date != null) return date;
    }

    final revision = await fetchLatestRevision(programId);
    if (revision != null) return revision.createdDate;

    return DateTime.now();
  }

  /// Completed sessions attributed to [runId], oldest first.
  ///
  /// `end_datetime IS NOT NULL` is what makes it a session rather than an
  /// abandoned start — an in-progress session has produced nothing to review.
  Future<List<AchievementSession>> fetchRunSessions(String runId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT session_id, planned_session_name, created_datetime
      FROM fact_session
      WHERE program_run_id = ? AND end_datetime IS NOT NULL
      ORDER BY created_datetime
      ''',
      [runId],
    );
    return rows
        .map((r) => AchievementSession(
              sessionId: '${r['session_id']}',
              name: r['planned_session_name'] as String?,
              date: _toDate(r['created_datetime']) ?? DateTime.now(),
            ))
        .toList();
  }

  /// Bodyweight at the edges of a window — the first and last weigh-in inside
  /// `[from, to]`, either of which is null when the user logged none.
  ///
  /// `user_weight_date` is a date-only string ("2026-09-27") written by
  /// `UserRepository.logWeight`, and a synced row may arrive in a fuller form,
  /// so the rows are ordered in SQL and parsed here — the same "dates in Dart"
  /// rule the rest of the app follows. Weight is a text column for the same
  /// reason `target_weight` is: it was free-form text historically.
  Future<({double? start, double? end})> weightWindow({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT user_weight, user_weight_date FROM fact_bodyweight
      WHERE user_id = ?
      ORDER BY user_weight_date
      ''',
      [userId],
    );

    ({double? start, double? end}) window = (start: null, end: null);
    for (final row in rows) {
      final date = _toDate(row['user_weight_date']);
      final weight = _toDouble(row['user_weight']);
      if (date == null || weight == null) continue;
      if (date.isBefore(from) || date.isAfter(to)) continue;
      window = (start: window.start ?? weight, end: weight);
    }
    return window;
  }

  // ── Due ──────────────────────────────────────────────────────────────────

  /// What is waiting on the user across every program, most overdue first.
  ///
  /// Three sources, all of them derived: open reviews with a schedule, a run
  /// whose length has run out but which nobody has ended, and a block whose
  /// planned start has arrived on a program that isn't running yet.
  ///
  /// Every date comparison is done in Dart rather than SQL: a synced row's
  /// timestamp formatting is not guaranteed to match what the client writes,
  /// and a lexicographic string comparison across two formats silently drops
  /// rows. The row counts here are bounded by how many reviews and blocks a
  /// human has created.
  ///
  /// Called from the library and the program detail loader ONLY, never from
  /// `getProgress` — a read that prompts must not be the same read that
  /// mutates.
  Future<List<DueItem>> fetchDueItems(String userId) async {
    final now = DateTime.now();
    final due = <DueItem>[];

    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE user_id = ? AND completed_date IS NULL AND scheduled_for IS NOT NULL
      ''',
      [userId],
    );
    for (final row in rows) {
      final review = ProgramReview.fromMap(row);
      if (!review.isDue(now)) continue;
      due.add(DueItem(
        kind: kDueReview,
        programId: review.programId,
        review: review,
        dueDate: review.scheduledFor,
      ));
    }

    // A run that has reached its length is a question, not a state. It stays
    // current until the user answers, so this item is the standing reminder —
    // and it is why nothing else in the app is allowed to end a run.
    final progress = await _runRepo.getProgress(userId);
    final currentProgramId = progress?.program.programId;
    if (progress != null && progress.isLengthReached && progress.run.isCurrent) {
      due.add(DueItem(
        kind: kDueRunFinished,
        programId: progress.program.programId,
        dueDate: progress.endsAt,
        blockId: progress.block?.blockId,
        blockName: progress.block?.name,
      ));
    }

    // A block whose planned start has arrived, on a program that is not running.
    //
    // "Not running" is the whole condition, and it is asked of the program
    // rather than of the block: a program already mid-run has blocks that
    // started in the past by definition, so scoping this to "not the current
    // block" would nag about beginning phase 2 the moment phase 1 was under
    // way. Moving between blocks is the user's call, made on the program
    // screen where the blocks are visible.
    final blockRows = await ps.db.getAll(
      '''
      SELECT b.block_id, b.program_id, b.name, b.start_date
      FROM dim_program_block b
      WHERE b.user_id = ?
        AND b.date_archived IS NULL
        AND b.start_date IS NOT NULL
        AND (? IS NULL OR b.program_id != ?)
        AND EXISTS (
          SELECT 1 FROM dim_program p
          WHERE p.program_id = b.program_id AND p.date_archived IS NULL
        )
      ORDER BY b.start_date
      ''',
      [userId, currentProgramId, currentProgramId],
    );
    final startedPrograms = <String>{};
    for (final row in blockRows) {
      final startDate = _toDate(row['start_date']);
      if (startDate == null || startDate.isAfter(now)) continue;
      final programId = '${row['program_id']}';
      // One prompt per program, and the earliest arrived start is the one that
      // has been waiting longest — the rows are already in that order.
      if (!startedPrograms.add(programId)) continue;
      due.add(DueItem(
        kind: kDueBlockStart,
        programId: programId,
        dueDate: startDate,
        blockId: '${row['block_id']}',
        blockName: row['name'] as String?,
      ));
    }

    due.sort((a, b) => (a.dueDate ?? now).compareTo(b.dueDate ?? now));
    return due;
  }

  // ── Closing a run ────────────────────────────────────────────────────────

  /// Records the end of a run: one final revision and the close review that
  /// carries the frozen record of what the run produced.
  ///
  /// [achievementsJson] is derived by the caller — one derivation, used both to
  /// render the panel the user just looked at and to freeze it here, so the two
  /// cannot disagree. The repo writes it; it does not compute it, because
  /// freezing derived data is a decision that belongs where the user's action
  /// is, not buried in a write path.
  ///
  /// Ending the run itself is a separate call ([ProgramRunRepository
  /// .endCurrentRun]); this one only writes the history.
  Future<ProgramRevision> closeRun({
    required String userId,
    required String programId,
    required String runId,
    required String reason,
    required String achievementsJson,
    String? blockId,
  }) async {
    if (!kRevisionReasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason', 'Unknown revision reason');
    }

    final content = await buildContent(userId: userId, programId: programId);
    late ProgramRevision revision;
    final now = DateTime.now().toUtc();

    await ps.safeWriteTransaction((tx) async {
      revision = await _insertRevision(
        tx,
        userId: userId,
        programId: programId,
        reason: reason,
        content: content,
        blockId: blockId,
        blockRunId: runId,
      );

      final reviewId = _uuid.v4();
      await tx.execute(
        '''
        INSERT INTO fact_program_review
          (id, review_id, user_id, program_id, block_id, program_run_id, kind,
           completed_date, outcome, achievements_json, revision_id,
           created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          reviewId,
          reviewId,
          userId,
          programId,
          blockId,
          runId,
          kReviewKindClose,
          now.toIso8601String(),
          kOutcomeClosed,
          achievementsJson,
          revision.revisionId,
          now.toIso8601String(),
        ],
      );
    });

    return revision;
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

/// Timestamps are compared and windows computed in Dart rather than SQL —
/// a downloaded row's text form is not guaranteed to match what the client
/// writes, and `'2026-09-27T00:00:00.000Z' < '2026-09-27 00:00:00+00'` is
/// false for the wrong reason. Everything is normalized to local time here,
/// which is also what the UI renders.
DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}
