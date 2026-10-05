import 'package:uuid/uuid.dart';

import '../../core/powersync/database.dart' as ps;
import '../models/block_sequence.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/program_block.dart';
import '../models/program_content.dart';
import '../models/program_history.dart';
import '../models/program_review.dart';
import '../models/program_run.dart';
import 'planned_session_repository.dart';
import 'program_repository.dart';
import 'program_run_repository.dart';

const _uuid = Uuid();

/// Sequence order used when a link has none — sorts last, matching the
/// `ORDER BY sequence_order NULLS LAST` the link queries use.
const _unordered = 1 << 30;

/// A program's checkpoints: the reviews that record it, and the snapshot each
/// completed review carries.
///
/// Deliberately separate from [ProgramRepository] rather than bolted onto it.
/// Building a snapshot reads the entire program (links, templates, exercises,
/// sets), and completing a review has to write that snapshot and mark the
/// review complete inside a single local transaction — neither belongs on the
/// CRUD repository the rest of the screens already depend on.
class ProgramHistoryRepository {
  ProgramHistoryRepository({
    PlannedSessionRepository? plannedSessionRepository,
    ProgramRunRepository? programRunRepository,
    ProgramRepository? programRepository,
  }) : _plannedRepo = plannedSessionRepository ?? PlannedSessionRepository(),
       _runRepo = programRunRepository ?? ProgramRunRepository(),
       _programRepo = programRepository ?? ProgramRepository();

  final PlannedSessionRepository _plannedRepo;

  /// Read for the two things a snapshot holds that no other repository does:
  /// the program's blocks, and its goals.
  final ProgramRepository _programRepo;

  /// Needed for exactly two things: the "this run has reached its length"
  /// due item, and knowing a run's start when it produced no checkpoint yet.
  /// `getProgress` is a pure read (the mutation it used to carry now lives in
  /// the ViewModel), so reading it from here is safe — but the reverse is not
  /// true: this is a read that *prompts*, so nothing may prompt from inside
  /// `getProgress`.
  final ProgramRunRepository _runRepo;

  // ── Snapshots ────────────────────────────────────────────────────────────

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
  Future<ProgramContent> buildContent({
    required String userId,
    required String programId,
  }) async {
    final links = await _plannedRepo.fetchProgramLinks(programId);
    final sessions = await _plannedRepo.fetchPlannedSessions(
      userId,
      programId: programId,
    );
    final sessionById = {for (final s in sessions) s.sessionId: s};

    // Both scopes: a block's goals are part of what the program is, and a
    // review of that block has to be able to say what it was chasing.
    final goals = await _programRepo.fetchGoals(userId, programId: programId);
    final blocks = await _programRepo.fetchBlocks(programId);

    // Ordered here rather than trusting the query's ORDER BY: this list's
    // sequence is part of the stored document, so it outlives any future
    // change to how links are fetched.
    final ordered =
        links.where((l) => sessionById.containsKey(l.plannedSessionId)).toList()
          ..sort(
            (a, b) => (a.sequenceOrder ?? _unordered).compareTo(
              b.sequenceOrder ?? _unordered,
            ),
          );

    final snapshot = <ContentSession>[];
    for (final link in ordered) {
      final session = sessionById[link.plannedSessionId]!;

      // Both reads are already scoped to active rows and ordered by
      // exercise_order / set_number, so grouping preserves that order.
      final exercises = await _plannedRepo.fetchPlannedExercises(
        session.sessionId,
      );
      final sets = await _plannedRepo.fetchPlannedSets(session.sessionId);
      final setsByExercise = <String, List<PlannedSessionExerciseSet>>{};
      for (final set in sets) {
        setsByExercise.putIfAbsent(set.plannedExerciseId, () => []).add(set);
      }

      snapshot.add(
        ContentSession(
          sessionId: session.sessionId,
          userId: userId,
          name: session.name,
          notes: session.notes,
          createdDate: session.createdDate,
          sequenceOrder: link.sequenceOrder,
          dayOfWeek: link.dayOfWeek,
          weekOffset: link.weekOffset,
          // Membership, from the link row — the same column the Blocks tab
          // groups by, so a snapshot and the screen agree about which phase a
          // workout is in.
          blockId: link.blockId,
          exercises: exercises
              .map(
                (e) =>
                    _exercise(e, userId, setsByExercise[e.plannedExerciseId]),
              )
              .toList(growable: false),
        ),
      );
    }

    return ProgramContent.fromRows(
      blocks: [
        for (final b in blocks)
          ContentBlock(
            blockId: b.blockId,
            name: b.name,
            notes: b.notes,
            blockOrder: b.blockOrder,
            targetWeeks: b.targetWeeks,
            targetDays: b.targetDays,
            targetSessions: b.targetSessions,
          ),
      ],
      sessions: snapshot,
      goals: [
        for (final g in goals)
          ContentGoal(
            goalId: g.goalId,
            userId: userId,
            blockId: g.blockId,
            exerciseId: g.exerciseId,
            variationId: g.variationId,
            targetWeight: g.targetWeight,
            targetReps: g.targetReps,
            text: g.text,
          ),
      ],
    );
  }

  ContentExercise _exercise(
    PlannedSessionExercise exercise,
    String userId,
    List<PlannedSessionExerciseSet>? sets,
  ) => ContentExercise(
    plannedExerciseId: exercise.plannedExerciseId,
    plannedSessionId: exercise.plannedSessionId,
    userId: userId,
    exerciseId: exercise.exerciseId,
    exerciseOrder: exercise.exerciseOrder,
    sets: (sets ?? const <PlannedSessionExerciseSet>[])
        .map(
          (s) => ContentSet(
            plannedSetId: s.plannedSetId,
            plannedExerciseId: s.plannedExerciseId,
            plannedSessionId: s.plannedSessionId,
            userId: userId,
            variationId: s.variationId,
            setNumber: s.setNumber,
            targetWeight: s.targetWeight,
            targetReps: s.targetReps,
            targetNotes: s.targetNotes,
          ),
        )
        .toList(growable: false),
  );

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Reviews of [programId], newest first by [ProgramReview.effectiveDate] —
  /// the order the timeline renders.
  ///
  /// The SQL pre-sort mirrors what the client writes; the effective date is
  /// re-sorted in Dart because a downloaded row's timestamp formatting is not
  /// guaranteed to match the client's, and a lexicographic comparison across
  /// two formats silently misorders rows. The review-id tie-break keeps the
  /// order deterministic when two reviews share a date (Dart's sort is not
  /// stable).
  Future<List<ProgramReview>> fetchReviews(String programId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE program_id = ?
      ORDER BY created_date DESC, review_id DESC
      ''',
      [programId],
    );
    final reviews = rows.map((r) => ProgramReview.fromMap(r)).toList();
    reviews.sort((a, b) {
      final byDate = b.effectiveDate.compareTo(a.effectiveDate);
      return byDate != 0 ? byDate : b.reviewId.compareTo(a.reviewId);
    });
    return reviews;
  }

  Future<ProgramReview?> fetchReview(String reviewId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_review WHERE review_id = ?',
      [reviewId],
    );
    if (rows.isEmpty) return null;
    return ProgramReview.fromMap(rows.first);
  }

  /// Creates a review. A non-null [proposedContent] makes it a
  /// [kReviewKindChange] — a checkpoint carrying a proposed edit — because the
  /// kind IS "has a proposal", not a separate choice the caller could get
  /// wrong.
  ///
  /// [blockId] and [sessionId] are the SCOPE, mutually exclusive: a program
  /// review sets neither, a block review the block, a session review the
  /// planned session. Both set would violate the server's scope CHECK and
  /// quarantine the row as a `23514`, so the client refuses it here instead.
  /// A null [scheduledFor] is the ad-hoc path — a checkpoint taken on the
  /// spot, not a prompt for later.
  Future<ProgramReview> scheduleReview({
    required String userId,
    required String programId,
    String? blockId,
    String? sessionId,
    String? programRunId,
    String? title,
    String? notes,
    DateTime? scheduledFor,
    ProgramContent? proposedContent,
  }) async {
    if (blockId != null && sessionId != null) {
      throw ArgumentError(
        'A review examines one scope: blockId and sessionId cannot both be set',
      );
    }
    final reviewId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final json = proposedContent?.encode();

    await ps.safeExec(
      '''
      INSERT INTO fact_program_review
        (id, review_id, user_id, program_id, block_id, session_id,
         program_run_id, kind, title, notes, scheduled_for, proposed_content,
         proposed_hash, created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        reviewId,
        reviewId,
        userId,
        programId,
        blockId,
        sessionId,
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

  /// Completes a review, writing the snapshot it is a checkpoint of onto the
  /// row.
  ///
  /// The snapshot write and the completion UPDATE share ONE transaction: a
  /// review marked complete with no snapshot behind it, or a snapshot no
  /// review claims, are both worse than the operation failing outright.
  ///
  /// A [kOutcomeDismissed] review is "not now", not a checkpoint, so it takes
  /// the completion UPDATE alone — no snapshot, no content build. It is also
  /// excluded from the achievements window ([checkpointFor]); otherwise
  /// dismissing a prompt would silently swallow everything achieved since the
  /// last real review.
  ///
  /// Idempotent: a review that is already completed is returned unchanged, so
  /// a double-tap cannot re-snapshot a program the user has since edited.
  Future<ProgramReview> completeReview(
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
    if (review.isCompleted) return review;

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
      return (await fetchReview(reviewId)) ?? review;
    }

    // The snapshot is of the LIVE rows, never of the proposal: applying a
    // change means the user edited the program through the normal editor, and
    // this records what that produced. No code path copies proposed_content
    // into live rows.
    //
    // Built BEFORE the transaction opens — querying from inside a
    // `writeTransaction` callback contends with the write lock that
    // transaction holds (see the note on `ProgramRepository.duplicateProgram`).
    final content = await buildContent(
      userId: userId,
      programId: review.programId,
    );

    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        '''
        UPDATE fact_program_review
        SET completed_date = ?, outcome = ?, notes = COALESCE(?, notes),
            snapshot_content = ?, snapshot_hash = ?
        WHERE review_id = ? AND completed_date IS NULL
        ''',
        [
          now.toIso8601String(),
          outcome,
          notes,
          content.encode(),
          content.contentHash,
          reviewId,
        ],
      );
    });
    return (await fetchReview(reviewId)) ?? review;
  }

  // ── Achievements ─────────────────────────────────────────────────────────

  /// Where the current achievements window opens: the last checkpoint that
  /// actually looked at the program **at this scope**.
  ///
  /// The latest completed review at the scope, else [fallback] (the running
  /// run's start, when the caller has one). Dismissed reviews are skipped, and
  /// that is load-bearing: a dismissal means "not now", so letting it open the
  /// window would silently swallow everything achieved since the last real
  /// review.
  ///
  /// [blockId] and [sessionId] are the scope, not context, and they are
  /// mutually exclusive: null twice asks for the program's own checkpoints,
  /// an id for that block's or that session's, and none answers for another.
  /// The `session_id IS NULL` clauses are load-bearing in the other two
  /// branches — without them a session review inside block B would open B's
  /// window and a block's checkpoint would answer for the program.
  ///
  /// The fallback used to be `DateTime.now()`, which made a first-ever run's
  /// window `[now, now]`: its close review derived nothing, no matter what was
  /// lifted. A caller with no run at all still gets "now" — the panel is not
  /// showing a run, so there is nothing to look back to.
  ///
  /// A program with no reviews therefore opens its window at the run's start,
  /// which is what `fallback` already carries on every real call path.
  Future<DateTime> checkpointFor(
    String programId, {
    String? blockId,
    String? sessionId,
    DateTime? fallback,
  }) async {
    final String scopePredicate;
    final List<Object?> params;
    if (sessionId != null) {
      // The session's own checkpoints only: a block review that happened to
      // cover this session is not a look at the session itself.
      scopePredicate = 'AND session_id = ?';
      params = [programId, kOutcomeDismissed, sessionId];
    } else if (blockId != null) {
      // `session_id IS NULL`: without it a session review inside this block
      // would open the block's window.
      scopePredicate = 'AND block_id = ? AND session_id IS NULL';
      params = [programId, kOutcomeDismissed, blockId];
    } else {
      scopePredicate = 'AND block_id IS NULL AND session_id IS NULL';
      params = [programId, kOutcomeDismissed];
    }

    final reviews = await ps.db.getAll(
      '''
      SELECT completed_date FROM fact_program_review
      WHERE program_id = ? AND completed_date IS NOT NULL AND outcome <> ?
        $scopePredicate
      ORDER BY completed_date DESC
      LIMIT 1
      ''',
      params,
    );
    if (reviews.isNotEmpty) {
      final date = _toDate(reviews.first['completed_date']);
      if (date != null) return date;
    }

    return fallback ?? DateTime.now();
  }

  /// Completed sessions the scope owns inside `[from, to]`, oldest first.
  ///
  /// Attribution is by run, so a session with no `program_run_id` — freestyle
  /// training while the program was active — is not claimed by it, and neither
  /// is one belonging to another program's run.
  ///
  /// [blockId] narrows to that block's runs, [sessionId] to that planned
  /// session's, and null twice is the *program's* scope, which is every run of
  /// the program rather than only the unblocked ones. That asymmetry with
  /// [checkpointFor] is deliberate: a program review asks what the program
  /// did, and a blocked program's training happened inside its blocks —
  /// reporting only the runs that were outside them would report a program
  /// that never trained. Goals reconcile the two: a program-level target is in
  /// force in every block.
  ///
  /// `end_datetime IS NOT NULL` is what makes it a session rather than an
  /// abandoned start — an in-progress session has produced nothing to review.
  /// The window is applied in Dart rather than SQL: a synced row's timestamp
  /// formatting is not guaranteed to match what the client writes, and a
  /// lexicographic comparison across two formats silently drops rows.
  Future<List<AchievementSession>> fetchScopedSessions({
    required String programId,
    required DateTime from,
    required DateTime to,
    String? blockId,
    String? sessionId,
  }) async {
    final scopeFilters = <String>[
      if (blockId != null) 'AND r.block_id = ?',
      if (sessionId != null) 'AND s.planned_session_id = ?',
    ].join('\n        ');
    final rows = await ps.db.getAll(
      '''
      SELECT s.session_id, s.planned_session_name, s.created_datetime
      FROM fact_session s
      JOIN fact_program_run r ON r.program_run_id = s.program_run_id
      WHERE r.program_id = ? AND s.end_datetime IS NOT NULL
        $scopeFilters
      ORDER BY s.created_datetime
      ''',
      [programId, ?blockId, ?sessionId],
    );
    final sessions = <AchievementSession>[];
    for (final row in rows) {
      final date = _toDate(row['created_datetime']);
      if (date == null || date.isBefore(from) || date.isAfter(to)) continue;
      sessions.add(
        AchievementSession(
          sessionId: '${row['session_id']}',
          name: row['planned_session_name'] as String?,
          date: date,
        ),
      );
    }
    return sessions;
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
      due.add(
        DueItem(
          kind: kDueReview,
          programId: review.programId,
          review: review,
          dueDate: review.scheduledFor,
        ),
      );
    }

    // A run that has reached its length is a question, not a state. It stays
    // current until the user answers, so this item is the standing reminder —
    // and it is why nothing else in the app is allowed to end a run.
    final progress = await _runRepo.getProgress(userId);
    final currentProgramId = progress?.program.programId;
    if (progress != null && progress.isReadyToEnd) {
      due.add(
        DueItem(
          kind: kDueRunFinished,
          programId: progress.program.programId,
          dueDate: progress.endsAt,
          blockId: progress.block?.blockId,
          blockName: progress.block?.name,
        ),
      );
    }

    // A block whose planned start has arrived, on a program that is not running.
    //
    // "Not running" is the whole condition, and it is asked of the program
    // rather than of the block: a program already mid-run has blocks that
    // started in the past by definition, so scoping this to "not the current
    // block" would nag about beginning phase 2 the moment phase 1 was under
    // way. Moving between blocks is the user's call, made on the program
    // screen where the blocks are visible.
    //
    // Only the block the sequence is actually on is worth prompting for. A
    // phase's start date is a plan, not a queue: once a block has been ended —
    // or while an earlier one is still unended — its old date has been
    // answered, and a prompt for it would be asking the user to do something
    // the sequencing rule refuses. That is why the read below gathers every
    // active block and its program's runs rather than filtering on
    // `start_date` in SQL: which block is next is a question about the runs,
    // and it is answered in Dart by the same model the program screen uses.
    final blockRows = await ps.db.getAll(
      '''
      SELECT b.block_id, b.user_id, b.program_id, b.name, b.start_date,
             b.block_order
      FROM dim_program_block b
      WHERE b.user_id = ?
        AND b.date_archived IS NULL
        AND (? IS NULL OR b.program_id != ?)
        AND EXISTS (
          SELECT 1 FROM dim_program p
          WHERE p.program_id = b.program_id AND p.date_archived IS NULL
        )
      ORDER BY b.block_order
      ''',
      [userId, currentProgramId, currentProgramId],
    );
    if (blockRows.isNotEmpty) {
      // One read for every run the user has, then grouped by program: the
      // alternative is a query per candidate program, and the number of runs
      // a human has accumulated is the smaller and slower-growing list.
      final runRows = await ps.db.getAll(
        'SELECT * FROM fact_program_run WHERE user_id = ?',
        [userId],
      );
      final runsByProgram = <String, List<ProgramRun>>{};
      for (final row in runRows) {
        final run = ProgramRun.fromMap(row);
        (runsByProgram[run.programId] ??= []).add(run);
      }
      final blocksByProgram = <String, List<ProgramBlock>>{};
      for (final row in blockRows) {
        final programId = '${row['program_id']}';
        (blocksByProgram[programId] ??= []).add(ProgramBlock.fromMap(row));
      }

      final startedPrograms = <String>{};
      for (final entry in blocksByProgram.entries) {
        final sequence = BlockSequence(
          blocks: entry.value,
          runs: runsByProgram[entry.key] ?? const [],
        );
        // `pending`, never `nextBlock`: the wrap in `nextBlock` is what lets a
        // finished program be run again, and a program whose every block has
        // been run has nothing due — prompting to re-begin it on the old
        // start date would be a nag that never goes away.
        //
        // An open run — running or paused — also means there is nothing to
        // start: the block it holds is not waiting on a start date, it is
        // already under way, and the prompt's action begins a run rather than
        // resuming one.
        final block = sequence.pending;
        final startDate = block?.startDate;
        if (block == null ||
            sequence.hasOpenRun ||
            startDate == null ||
            startDate.isAfter(now)) {
          continue;
        }
        // One prompt per program, and the earliest arrived start is the one
        // that has been waiting longest.
        if (!startedPrograms.add(entry.key)) continue;
        due.add(
          DueItem(
            kind: kDueBlockStart,
            programId: entry.key,
            dueDate: startDate,
            blockId: block.blockId,
            blockName: block.name,
          ),
        );
      }
    }

    due.sort((a, b) => (a.dueDate ?? now).compareTo(b.dueDate ?? now));
    return due;
  }

  // ── Closing a run ────────────────────────────────────────────────────────

  /// Records the end of a run: one close review carrying the frozen record of
  /// what the run produced and a snapshot of the program it ran.
  ///
  /// [blockId] is the scope — null closes the program, an id closes that
  /// block. It is the only thing distinguishing the two, so there is no
  /// `reason` to keep in step with it.
  ///
  /// [achievementsJson] is derived by the caller — one derivation, used both to
  /// render the panel the user just looked at and to freeze it here, so the two
  /// cannot disagree. The repo writes it; it does not compute it, because
  /// freezing derived data is a decision that belongs where the user's action
  /// is, not buried in a write path.
  ///
  /// Ending the run itself is a separate call ([ProgramRunRepository
  /// .endCurrentRun]); this one only writes the history.
  Future<ProgramReview> closeRun({
    required String userId,
    required String programId,
    required String runId,
    required String achievementsJson,
    String? blockId,
  }) async {
    // Built BEFORE the transaction opens — querying from inside a
    // `writeTransaction` callback contends with the write lock that
    // transaction holds (see the note on `ProgramRepository.duplicateProgram`).
    final content = await buildContent(userId: userId, programId: programId);
    final reviewId = _uuid.v4();
    final now = DateTime.now().toUtc();

    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO fact_program_review
          (id, review_id, user_id, program_id, block_id, session_id,
           program_run_id, kind, completed_date, outcome, achievements_json,
           snapshot_content, snapshot_hash, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          reviewId,
          reviewId,
          userId,
          programId,
          blockId,
          null,
          runId,
          kReviewKindClose,
          now.toIso8601String(),
          kOutcomeClosed,
          achievementsJson,
          content.encode(),
          content.contentHash,
          now.toIso8601String(),
        ],
      );
    });

    final created = await fetchReview(reviewId);
    if (created == null) {
      throw StateError('The close review was inserted but cannot be read back');
    }
    return created;
  }
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
