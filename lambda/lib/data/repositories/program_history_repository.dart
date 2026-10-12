import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/powersync/database.dart' as ps;
import '../models/block_sequence.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session_program.dart';
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

/// Where a review's comparison starts — see
/// [ProgramHistoryRepository.comparisonBase].
class ComparisonBase {
  const ComparisonBase(this.content, {this.completedDate, this.notes = const {}});

  final ProgramContent content;

  /// When the previous review this snapshot came from finished, or null when
  /// the content is the review's own baseline — the plan as found.
  final DateTime? completedDate;

  /// The exercise notes THAT review recorded, keyed by `planned_exercise_id`.
  /// The notes live on the review row, not in the document, so a comparison
  /// that wants the record's own words has to carry them alongside its
  /// content. Empty for a baseline: a pass's notes are the pass's additions,
  /// not part of the plan as found.
  final Map<String, String> notes;

  bool get asFound => completedDate == null;
}

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

  /// Reads a SET of workouts — plus the goals the pass explicitly picked —
  /// into the same document shape [buildContent] produces for a program.
  ///
  /// This is a standalone review's snapshot: a pass that named workouts from
  /// anywhere (several programs, or none) instead of a program entire. The
  /// **stored id order is the document order** — the picker wrote it, and a
  /// snapshot has to reproduce from the same stored row — so no other sort is
  /// applied to the sessions.
  ///
  /// Join rows contribute exactly what they contribute inside a program: the
  /// block a workout sits in and its schedule slots, read from the workout's
  /// first link when it has one (a workout in two programs borrows the first
  /// one's placement — the snapshot is about the workouts, not about
  /// recreating a program). A workout with no link carries nulls, exactly as
  /// an unplaced one does.
  ///
  /// Missing rows are skipped, not fatal: a workout deleted between the pick
  /// and the snapshot has no content to record and the pass goes on without
  /// it — the same doctrine that makes an archived row read as absent in the
  /// program path.
  Future<ProgramContent> buildContentForSessions({
    required String userId,
    required List<String> sessionIds,
    List<String> goalIds = const [],
  }) async {
    final links = await _plannedRepo.fetchLinksForSessions(sessionIds);
    final linkBySession = <String, PlannedSessionProgram>{};
    for (final link in links) {
      linkBySession.putIfAbsent(link.plannedSessionId, () => link);
    }

    final sessions = <ContentSession>[];
    for (final id in sessionIds) {
      final session = await _plannedRepo.fetchPlannedSessionById(id);
      if (session == null) continue;
      final link = linkBySession[id];

      // Both reads are already scoped to active rows and ordered by
      // exercise_order / set_number, so grouping preserves that order.
      final exercises = await _plannedRepo.fetchPlannedExercises(id);
      final sets = await _plannedRepo.fetchPlannedSets(id);
      final setsByExercise = <String, List<PlannedSessionExerciseSet>>{};
      for (final set in sets) {
        setsByExercise.putIfAbsent(set.plannedExerciseId, () => []).add(set);
      }

      sessions.add(
        ContentSession(
          sessionId: session.sessionId,
          userId: userId,
          name: session.name,
          notes: session.notes,
          createdDate: session.createdDate,
          sequenceOrder: link?.sequenceOrder,
          dayOfWeek: link?.dayOfWeek,
          weekOffset: link?.weekOffset,
          blockId: link?.blockId,
          exercises: exercises
              .map(
                (e) =>
                    _exercise(e, userId, setsByExercise[e.plannedExerciseId]),
              )
              .toList(growable: false),
        ),
      );
    }

    // The blocks any kept workout sits in — active only, same doctrine as the
    // program path: archiving a block is how it is deleted, so a removed
    // phase must read as absent rather than linger in the document.
    final blocks = await _programRepo.fetchBlocksByIds([
      for (final s in sessions)
        if (s.blockId != null) s.blockId!,
    ]);

    // Goals in the pass's own stored order. An id that resolves to nothing
    // (goal deleted since the pick) is dropped silently — the landing says
    // "no longer available", the snapshot simply does not contain it.
    final goalById = {
      for (final option in await _programRepo.fetchGoalOptionsByIds(goalIds))
        option.goal.goalId: option.goal,
    };

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
      sessions: sessions,
      goals: [
        for (final id in goalIds)
          if (goalById[id] case final goal?)
            ContentGoal(
              goalId: goal.goalId,
              userId: userId,
              blockId: goal.blockId,
              exerciseId: goal.exerciseId,
              variationId: goal.variationId,
              targetWeight: goal.targetWeight,
              targetReps: goal.targetReps,
              text: goal.text,
            ),
      ],
    );
  }

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

  /// Every review [userId] has — program-owned and standalone alike — newest
  /// first by [ProgramReview.effectiveDate]. What the Reviews tab lists and
  /// what a standalone review's comparison walks.
  ///
  /// Program-scoped here on the USER, not a program: `fetchReviews` cannot see
  /// standalone rows (`program_id = ?` never matches NULL), which is also what
  /// keeps old builds from tripping over the new shape. Sorting is done in
  /// Dart for the same reason [fetchReviews] does it — a downloaded row's
  /// timestamp formatting is not guaranteed to match the client's.
  Future<List<ProgramReview>> fetchReviewsForUser(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE user_id = ?
      ORDER BY created_date DESC, review_id DESC
      ''',
      [userId],
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

  /// Creates a review — always a [kReviewKindReview].
  ///
  /// `proposed_content` rows still read back ([ProgramReview.fromMap] keeps the
  /// columns), but nothing writes them any more: reviewing IS editing, so a
  /// "proposed change" was a second way to describe the same act.
  ///
  /// [sessionIds] is the SCOPE — the workouts the pass covers, ticked in the
  /// picker. A review of nothing is not a review: an empty set would store no
  /// scope and resolve to the whole program, silently claiming a look nobody
  /// took, so it is refused here rather than written.
  ///
  /// A null [programId] is a **standalone** review — workouts picked from
  /// anywhere, no program in the picture. [goalIds] is the other half of the
  /// pass's question: the goals the user ticked, any scope, in pick order.
  ///
  /// A null [scheduledFor] is the ad-hoc path — a checkpoint taken on the
  /// spot, not a prompt for later.
  Future<ProgramReview> scheduleReview({
    required String userId,
    String? programId,
    required List<String> sessionIds,
    List<String> goalIds = const [],
    String? programRunId,
    String? title,
    String? notes,
    DateTime? scheduledFor,
  }) async {
    if (sessionIds.isEmpty) {
      throw ArgumentError(
        'A review covers at least one workout: sessionIds cannot be empty',
      );
    }
    final reviewId = _uuid.v4();
    final now = DateTime.now().toUtc();

    await ps.safeExec(
      '''
      INSERT INTO fact_program_review
        (id, review_id, user_id, program_id, program_run_id, kind, title,
         notes, scheduled_for, session_ids_json, goal_ids_json, created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        reviewId,
        reviewId,
        userId,
        programId,
        programRunId,
        kReviewKindReview,
        title,
        notes,
        scheduledFor?.toUtc().toIso8601String(),
        jsonEncode(sessionIds),
        goalIds.isEmpty ? null : jsonEncode(goalIds),
        now.toIso8601String(),
      ],
    );

    final created = await fetchReview(reviewId);
    if (created == null) {
      throw StateError('The review was inserted but cannot be read back');
    }
    return created;
  }

  /// Starts a review **now**: creates the row and records the plan as found.
  ///
  /// The two writes belong together, and not in [scheduleReview]: a review
  /// scheduled for later must not freeze "as found" today, because the plan
  /// may legitimately change before its date arrives. A review that is being
  /// taken, on the other hand, has nothing to compare its first pass against
  /// unless the moment the pass began is recorded — which is what
  /// [captureBaseline] is for, and why every "start now" path goes through
  /// here rather than calling [scheduleReview] itself.
  Future<ProgramReview> beginReview({
    required String userId,
    String? programId,
    required List<String> sessionIds,
    List<String> goalIds = const [],
    String? programRunId,
    String? title,
  }) async {
    final review = await scheduleReview(
      userId: userId,
      programId: programId,
      sessionIds: sessionIds,
      goalIds: goalIds,
      programRunId: programRunId,
      title: title,
    );
    return (await captureBaseline(review.reviewId, userId: userId)) ?? review;
  }

  /// The open review this run already has, if any — the newest one, should a
  /// run somehow have several.
  ///
  /// The run-finished prompt must land in the review that exists rather than
  /// opening a second one for the same question: opening the prompt twice —
  /// or leaving a review and coming back to the banner — is one pass, and one
  /// pass means one row. The run id alone is what ties a review to its run:
  /// a review started from the panel carries it too, and scopes are sets of
  /// workouts now, so there is no scope column left to narrow by.
  Future<ProgramReview?> fetchOpenReviewForRun(String programRunId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_program_review
      WHERE program_run_id = ?
        AND completed_date IS NULL
      ORDER BY created_date DESC
      LIMIT 1
      ''',
      [programRunId],
    );
    if (rows.isEmpty) return null;
    return ProgramReview.fromMap(rows.first);
  }

  /// Whether this run has already been answered at the length prompt — i.e.
  /// some review carrying its id has been completed.
  ///
  /// This is what keeps [fetchDueItems]' run-finished item from standing
  /// forever: "reached its length" is a fact that never un-happens, so the
  /// condition that raises the question has to be the *unanswered* state, not
  /// the reaching itself. Any completed review at any scope answers it —
  /// finishing the pass is the answer, whichever door the user came through.
  Future<bool> hasCompletedReviewForRun(String programRunId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM fact_program_review
      WHERE program_run_id = ? AND completed_date IS NOT NULL
      LIMIT 1
      ''',
      [programRunId],
    );
    return rows.isNotEmpty;
  }

  /// Records the plan **as found** on [reviewId] — the "before" side of the
  /// comparison when nothing at that scope has finished before.
  ///
  /// Idempotent by construction: the UPDATE only lands `WHERE baseline_content
  /// IS NULL`, so resuming a review, or opening it twice, keeps the baseline
  /// from when the pass actually began. That guard is the whole point — a
  /// baseline that moved with the user's edits would compare the plan to
  /// itself and read "identical" no matter what the pass changed.
  ///
  /// Returns the review as it now stands, or null when there is no such row.
  ///
  /// What "as found" copies follows the review's own scope: a program review
  /// freezes the program, a **standalone** one freezes its stored set and
  /// picked goals — the ground the pass says it is about, and nothing else.
  Future<ProgramReview?> captureBaseline(
    String reviewId, {
    required String userId,
  }) async {
    final review = await fetchReview(reviewId);
    if (review == null || review.hasBaseline) return review;

    final content = review.isStandalone
        ? await buildContentForSessions(
            userId: userId,
            sessionIds: review.storedSessionIds ?? const [],
            goalIds: review.storedGoalIds ?? const [],
          )
        : await buildContent(userId: userId, programId: review.programId!);
    await ps.safeExec(
      '''
      UPDATE fact_program_review
      SET baseline_content = ?, baseline_hash = ?
      WHERE review_id = ? AND baseline_content IS NULL
      ''',
      [content.encode(), content.contentHash, reviewId],
    );
    return fetchReview(reviewId);
  }

  /// The "before" side of [review]'s comparison for one workout: the newest
  /// COMPLETED predecessor whose resolved set **contains** [sessionId], or —
  /// when none does — the plan as found, the review's own baseline.
  ///
  /// "Contains", not "equals": a pass over a set that includes this workout is
  /// a look at this workout, so the diff answers what changed in *it* since
  /// anyone last snapshotted it. Legacy rows qualify by their old scope — a
  /// session review of X contains X, a program review contains everything —
  /// which is exactly how their digests already read. Everything newer than
  /// [review] is not a predecessor whatever its scope, which is why the walk
  /// starts after it in the newest-first order.
  ///
  /// Each predecessor resolves against its OWN snapshot: a completed review's
  /// set is read as the program stood when it completed, which is the document
  /// the comparison is about to use.
  ///
  /// Null when neither exists — an open review from before baselines were
  /// recorded. The comparison says "no earlier version recorded" rather than
  /// inventing one.
  ///
  /// The pool of predecessors follows the review's own scope: a program
  /// review walks that program's history, while a **standalone** review walks
  /// every review the user has. That is deliberate — a standalone pass over
  /// {A,B} and a program pass over {A,B} are asking the same question, and the
  /// first should see the second's answer.
  Future<ComparisonBase?> comparisonBase(
    ProgramReview review, {
    required String sessionId,
  }) async {
    final reviews = review.isStandalone
        ? await fetchReviewsForUser(review.userId)
        : await fetchReviews(review.programId!);
    final selfIndex = reviews.indexWhere((r) => r.reviewId == review.reviewId);
    final predecessors = reviews.skip(selfIndex < 0 ? 0 : selfIndex + 1);

    for (final other in predecessors) {
      if (!other.isCompleted) continue;
      final snapshot = other.snapshot;
      if (snapshot == null) continue;
      final links = [
        for (final s in snapshot.sessions)
          (sessionId: s.sessionId, blockId: s.blockId),
      ];
      if (!other.sessionsIn(links).contains(sessionId)) continue;
      return ComparisonBase(
        snapshot,
        completedDate: other.completedDate,
        notes: other.exerciseNotes,
      );
    }

    final baseline = review.baseline;
    return baseline == null ? null : ComparisonBase(baseline);
  }

  /// Sets (or, with a blank [note], clears) one exercise's review note.
  ///
  /// Write-through rather than buffered at Finish: the notes are the review's
  /// record, and a user who leaves mid-pass must not lose what they wrote
  /// along the way. Read-modify-write of the whole JSON object — the notes are
  /// one small document belonging to one user, so last-write-wins is the
  /// correct behaviour and a merge would only invent conflicts.
  Future<void> setExerciseNote(
    String reviewId,
    String plannedExerciseId, {
    required String? note,
  }) async {
    final review = await fetchReview(reviewId);
    if (review == null) return;
    final notes = Map<String, String>.of(review.exerciseNotes);
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      notes.remove(plannedExerciseId);
    } else {
      notes[plannedExerciseId] = trimmed;
    }
    await ps.safeExec(
      'UPDATE fact_program_review SET exercise_notes_json = ? WHERE review_id = ?',
      [notes.isEmpty ? null : jsonEncode(notes), reviewId],
    );
  }

  /// Sets (or, with a blank [note], clears) one workout's review note.
  ///
  /// The workout-level sibling of [setExerciseNote], deliberately identical in
  /// contract: write-through at every keystroke-commit, read-modify-write of
  /// the whole JSON object, last-write-wins between devices, and an empty map
  /// clearing the column back to NULL.
  Future<void> setWorkoutNote(
    String reviewId,
    String plannedSessionId, {
    required String? note,
  }) async {
    final review = await fetchReview(reviewId);
    if (review == null) return;
    final notes = Map<String, String>.of(review.workoutNotes);
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      notes.remove(plannedSessionId);
    } else {
      notes[plannedSessionId] = trimmed;
    }
    await ps.safeExec(
      'UPDATE fact_program_review SET workout_notes_json = ? WHERE review_id = ?',
      [notes.isEmpty ? null : jsonEncode(notes), reviewId],
    );
  }

  /// Rewrites the pass's scope: the workouts and the goals it covers.
  ///
  /// The scope is not frozen at the start — a workout that should have been in
  /// the pass, a goal that should not have been — and the row is where a pass's
  /// scope lives, so an edit lands here as it is made rather than at Finish. The
  /// caller holds the whole scope it was shown and hands the finished lists
  /// back; the write is deliberately whole-list, like [setWorkoutNote]'s JSON,
  /// because two devices editing one pass is last-write-wins by design.
  ///
  /// Order is the caller's and is preserved: the landing reads the set back in
  /// stored order, and a set re-ticked into a different order would open in a
  /// sequence nobody chose.
  ///
  /// Guarded on `completed_date IS NULL`, like [markWorkoutReviewed]: a finished
  /// review's scope is part of what was recorded, so a late edit cannot rewrite
  /// it. An empty [sessionIds] is refused for the reason [scheduleReview]
  /// refuses one — a review contains workouts, and a row covering none is not a
  /// review.
  Future<void> setReviewScope(
    String reviewId, {
    required List<String> sessionIds,
    required List<String> goalIds,
  }) async {
    if (sessionIds.isEmpty) {
      throw ArgumentError(
        'A review covers at least one workout: sessionIds cannot be empty',
      );
    }
    await ps.safeExec(
      '''
      UPDATE fact_program_review
      SET session_ids_json = ?, goal_ids_json = ?
      WHERE review_id = ? AND completed_date IS NULL
      ''',
      [
        jsonEncode(sessionIds),
        goalIds.isEmpty ? null : jsonEncode(goalIds),
        reviewId,
      ],
    );
  }

  /// Cancels an open review: the row is hard-deleted, locally and on the
  /// server — the CRUD queue turns the local DELETE into a PostgREST delete on
  /// `review_id`, the same path [ProgramRepository.hardDeleteProgram] takes
  /// when it clears a program's reviews.
  ///
  /// Nothing else goes with the row: notes, ticks, baseline and snapshot are
  /// columns on it, and no table references it, so there is nothing to unwind.
  ///
  /// Guarded on `completed_date IS NULL`, like every other write to an open
  /// pass ([setReviewScope], [markWorkoutReviewed], [_writeReviewed]): a review
  /// completed on another device between the swipe and this statement is a
  /// record now, and must not be deleted out from under its own completion.
  Future<void> deleteReview(String reviewId) => ps.safeExec(
    '''
    DELETE FROM fact_program_review
    WHERE review_id = ? AND completed_date IS NULL
    ''',
    [reviewId],
  );

  /// Records that [plannedSessionId] is finished inside [reviewId]'s pass.
  ///
  /// Read-modify-write of the whole `reviewed_sessions_json` map — the same
  /// single-small-document pattern [setExerciseNote] uses, and for the same
  /// reason: last-write-wins is the correct behaviour between two devices, and
  /// a merge would only invent conflicts. Re-marking overwrites the stamp, so
  /// the map always says when the tick last landed — and [unmarkWorkoutReviewed]
  /// is the other half of the same toggle.
  ///
  /// Guarded on `completed_date IS NULL` — a review that is already finished
  /// takes no more marks, so a late Done cannot mutate a record that has been
  /// written — alongside the same check in Dart, which also skips the write
  /// when there is no such row at all.
  Future<void> markWorkoutReviewed(
    String reviewId,
    String plannedSessionId,
  ) async {
    final review = await fetchReview(reviewId);
    if (review == null || review.isCompleted) return;

    final reviewed = _reviewedFrom(review);
    reviewed[plannedSessionId] = DateTime.now().toUtc().toIso8601String();
    await _writeReviewed(reviewId, reviewed);
  }

  /// Takes [plannedSessionId]'s tick back off [reviewId]'s pass.
  ///
  /// The inverse of [markWorkoutReviewed], and the same read-modify-write for
  /// the same reasons. Done is a toggle — a workout marked by mistake is
  /// unmarked by the same button — and one key leaving the map is the whole of
  /// it. Guarded on `completed_date IS NULL` like the mark: a finished review's
  /// ticks are part of what was recorded, so neither direction can rewrite it.
  Future<void> unmarkWorkoutReviewed(
    String reviewId,
    String plannedSessionId,
  ) async {
    final review = await fetchReview(reviewId);
    if (review == null || review.isCompleted) return;

    final reviewed = _reviewedFrom(review)..remove(plannedSessionId);
    await _writeReviewed(reviewId, reviewed);
  }

  /// The tick map read off [review], decoded for a read-modify-write. An
  /// unreadable blob reads as "nothing marked yet" — the same rule the model's
  /// getter follows, so the two cannot disagree.
  Map<String, dynamic> _reviewedFrom(ProgramReview review) {
    final reviewed = <String, dynamic>{};
    final json = review.reviewedSessionsJson;
    if (json == null) return reviewed;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        reviewed.addAll({for (final e in decoded.entries) '${e.key}': e.value});
      }
    } catch (_) {
      // Unreadable: nothing marked yet.
    }
    return reviewed;
  }

  /// Writes [reviewed] onto the pass's row, refusing a review that is already
  /// finished — the guard sits in the WHERE so a race cannot slip past it.
  Future<void> _writeReviewed(String reviewId, Map<String, dynamic> reviewed) {
    return ps.safeExec(
      '''
      UPDATE fact_program_review
      SET reviewed_sessions_json = ?
      WHERE review_id = ? AND completed_date IS NULL
      ''',
      [jsonEncode(reviewed), reviewId],
    );
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

    // The snapshot is of the LIVE rows. Reviewing IS editing: the user
    // changes the plan through the normal editor, and finishing records what
    // that produced — the review row never writes back to the rows it
    // describes. Which rows "live" means follows the pass's own scope: the
    // whole program for a program review, the stored set and picked goals for
    // a standalone one.
    //
    // Built BEFORE the transaction opens — querying from inside a
    // `writeTransaction` callback contends with the write lock that
    // transaction holds (see the note on `ProgramRepository.duplicateProgram`).
    final content = review.isStandalone
        ? await buildContentForSessions(
            userId: userId,
            sessionIds: review.storedSessionIds ?? const [],
            goalIds: review.storedGoalIds ?? const [],
          )
        : await buildContent(userId: userId, programId: review.programId!);

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
  /// actually looked at this ground.
  ///
  /// [sessionIds] names the workouts the window is about. The latest completed
  /// review whose resolved set **intersects** them opens it — a pass over any
  /// of this ground is a look at all of it, which is the whole point of a
  /// review being a set. Null asks for the program's own window, and that one
  /// opens only on a pass over the program entire: reviewing part of a plan is
  /// not reviewing the plan, and letting it cut this window would silently
  /// swallow what was achieved since the last full look. (A legacy program
  /// review resolves to every workout, so old rows open it exactly as they
  /// always did.)
  ///
  /// Dismissed reviews are skipped, and that is load-bearing: a dismissal
  /// means "not now", so letting it open the window would silently swallow
  /// everything achieved since the last real review.
  ///
  /// Candidates resolve against the program's **live** links — a legacy row's
  /// block is read as that block's workouts *today*, which is the most useful
  /// reading for a window question and costs one small read. The snapshot
  /// blobs are deliberately not selected: resolving a set needs ids, not
  /// documents.
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
    List<String>? sessionIds,
    DateTime? fallback,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT review_id, user_id, program_id, block_id, session_id,
             session_ids_json, completed_date, outcome
      FROM fact_program_review
      WHERE program_id = ? AND completed_date IS NOT NULL AND outcome <> ?
      ''',
      [programId, kOutcomeDismissed],
    );
    if (rows.isEmpty) return fallback ?? DateTime.now();

    // Resolved once, for every candidate: the fall-through resolver needs the
    // program's (sessionId, blockId) pairs and the program-wide check needs
    // every id.
    final links = await _plannedRepo.fetchProgramLinks(programId);
    final sessionLinks = [
      for (final link in links)
        (sessionId: link.plannedSessionId, blockId: link.blockId),
    ];
    final everySession = [for (final link in links) link.plannedSessionId];

    final candidates = [
      for (final row in rows) ProgramReview.fromMap(row),
    ]..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));

    for (final review in candidates) {
      final set = review.sessionsIn(sessionLinks);
      final opens = sessionIds == null
          // The program's window: the pass has to have covered all of it.
          ? set.length == everySession.length &&
                set.toSet().containsAll(everySession)
          : set.any(sessionIds.contains);
      if (opens) return review.effectiveDate;
    }

    return fallback ?? DateTime.now();
  }

  /// Where a **standalone** window opens: the newest completed pass of the
  /// user's whose resolved set intersects [sessionIds].
  ///
  /// The twin of [checkpointFor] for reviews with no program — same question
  /// ("has anyone looked at this ground since?"), asked of the user's whole
  /// review history rather than one program's. Returns [fallback] (null when
  /// none is given) when nothing earlier exists: an open review that is
  /// genuinely the first look at this ground has nothing to say "since".
  ///
  /// Candidate sets resolve the way [comparisonBase]'s predecessors do: a
  /// stored set is itself, and a legacy row's scope resolves against its
  /// program's **live** links — fetched once per distinct program id, since
  /// the rows are bounded by how many reviews a human has. Dismissed reviews
  /// are skipped, the same load-bearing exclusion [checkpointFor] makes.
  Future<DateTime?> checkpointForSet(
    String userId, {
    required List<String> sessionIds,
    DateTime? fallback,
  }) async {
    if (sessionIds.isEmpty) return fallback;
    final rows = await ps.db.getAll(
      '''
      SELECT review_id, user_id, program_id, block_id, session_id,
             session_ids_json, completed_date, outcome
      FROM fact_program_review
      WHERE user_id = ? AND completed_date IS NOT NULL AND outcome <> ?
      ''',
      [userId, kOutcomeDismissed],
    );
    if (rows.isEmpty) return fallback;

    final reviews = [for (final row in rows) ProgramReview.fromMap(row)]
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));

    final linksByProgram =
        <String, List<({String sessionId, String? blockId})>>{};
    for (final review in reviews) {
      var links = const <({String sessionId, String? blockId})>[];
      final programId = review.programId;
      if (programId != null) {
        final cached = linksByProgram[programId];
        if (cached != null) {
          links = cached;
        } else {
          final programLinks = await _plannedRepo.fetchProgramLinks(programId);
          links = [
            for (final link in programLinks)
              (sessionId: link.plannedSessionId, blockId: link.blockId),
          ];
          linksByProgram[programId] = links;
        }
      }
      if (review.sessionsIn(links).any(sessionIds.contains)) {
        return review.effectiveDate;
      }
    }
    return fallback;
  }

  /// Completed sessions the scope owns inside `[from, to]`, oldest first.
  ///
  /// Attribution is by run, so a session with no `program_run_id` — freestyle
  /// training while the program was active — is not claimed by it, and neither
  /// is one belonging to another program's run.
  ///
  /// [blockId] narrows to that block's runs, [sessionIds] to those of the
  /// named planned sessions, and null twice is the *program's* scope, which is
  /// every run of the program rather than only the unblocked ones. That
  /// asymmetry with [checkpointFor] is deliberate: a program review asks what
  /// the program did, and a blocked program's training happened inside its
  /// blocks — reporting only the runs that were outside them would report a
  /// program that never trained. Goals reconcile the two: a program-level
  /// target is in force in every block.
  ///
  /// The set filter is applied here in Dart, and it drops sessions with no
  /// planned session — which is why the run-close path narrows by [blockId]
  /// instead: a block run's logged sessions include freestyle ones, and a set
  /// of planned ids could never name them.
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
    List<String>? sessionIds,
  }) async {
    final scopeFilters = <String>[
      if (blockId != null) 'AND r.block_id = ?',
    ].join('\n        ');
    final rows = await ps.db.getAll(
      '''
      SELECT s.session_id, s.planned_session_id, s.planned_session_name,
             s.created_datetime
      FROM fact_session s
      JOIN fact_program_run r ON r.program_run_id = s.program_run_id
      WHERE r.program_id = ? AND s.end_datetime IS NOT NULL
        $scopeFilters
      ORDER BY s.created_datetime
      ''',
      [programId, ?blockId],
    );
    final sessions = <AchievementSession>[];
    for (final row in rows) {
      final date = _toDate(row['created_datetime']);
      if (date == null || date.isBefore(from) || date.isAfter(to)) continue;
      if (sessionIds != null &&
          !sessionIds.contains(row['planned_session_id'])) {
        continue;
      }
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
      WHERE user_id = ? AND completed_date IS NULL
        AND scheduled_for IS NOT NULL
        AND program_id IS NOT NULL
      ''',
      [userId],
    );
    for (final row in rows) {
      final review = ProgramReview.fromMap(row);
      if (!review.isDue(now)) continue;
      // Non-null by the WHERE above; the guard is the type's, so a future
      // edit to the SQL cannot smuggle a scope-less row into a DueItem.
      final programId = review.programId;
      if (programId == null) continue;
      due.add(
        DueItem(
          kind: kDueReview,
          programId: programId,
          review: review,
          dueDate: review.scheduledFor,
        ),
      );
    }

    // A run that has reached its length is a question, not a state. It stays
    // current until the user answers, so this item is the standing reminder —
    // and it is why nothing else in the app is allowed to end a run.
    //
    // "Reached its length" never un-happens, so the question has to be asked
    // of the ANSWER, not of the reaching: a review completed over this run is
    // the user having looked at the plan and said what they want — continue
    // with it, change it, or end the run — and the prompt comes down at Finish
    // rather than waiting for an end that may never come. The cadence feature,
    // when it lands, is what will earn the right to ask again.
    final progress = await _runRepo.getProgress(userId);
    final currentProgramId = progress?.program.programId;
    if (progress != null && progress.isReadyToEnd) {
      final answered = await hasCompletedReviewForRun(
        progress.run.programRunId,
      );
      if (!answered) {
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
