import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../core/utils/block_length.dart';
import '../models/planned_session.dart';
import '../models/program.dart';
import '../models/program_block.dart';
import '../models/program_progress.dart';
import '../models/program_run.dart';
import 'planned_session_repository.dart';
import 'program_repository.dart';

const _uuid = Uuid();

/// The network half of [ProgramRunRepository] — the three calls that go
/// straight to Supabase because the local mirror may be stale or empty (a run
/// that has never been downloaded is invisible locally, which is exactly the
/// state a just-begun run is in).
///
/// A seam, not an abstraction for its own sake: tests cannot construct
/// `Supabase.instance` at all, so the run lifecycle's contract with the server
/// — the id it inserts, the times it clears — is only testable if it can be
/// observed through an injected object.
abstract class ProgramRunRemote {
  Future<Map<String, dynamic>?> fetchCurrentRun(String userId);

  /// Steps the user's current run aside: `is_current = false`, and
  /// deliberately **no** `ended_date`.
  ///
  /// Pausing is not ending. Ending stamps a date, which is what freezes the
  /// run as history; pausing leaves the row open so it can be resumed with its
  /// id, config, block and session attribution intact.
  Future<void> pauseCurrentRun(String userId);

  Future<void> insertRun(Map<String, dynamic> row);
}

/// The real remote: Supabase REST via the ambient client.
class SupabaseProgramRunRemote implements ProgramRunRemote {
  const SupabaseProgramRunRemote();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<Map<String, dynamic>?> fetchCurrentRun(String userId) async {
    final remote = await _client
        .from('fact_program_run')
        .select('*')
        .eq('user_id', userId)
        .eq('is_current', true)
        .limit(1)
        .timeout(const Duration(seconds: 5));
    return remote.isEmpty ? null : remote.first;
  }

  @override
  Future<void> pauseCurrentRun(String userId) async {
    await _client.from('fact_program_run').update({
      'is_current': false,
    }).eq('user_id', userId).eq('is_current', true)
        .timeout(const Duration(seconds: 5));
  }

  @override
  Future<void> insertRun(Map<String, dynamic> row) async {
    await _client
        .from('fact_program_run')
        .insert(row)
        .timeout(const Duration(seconds: 8));
  }
}

/// Owns "what program is current" and "what's next" — the logic needed by
/// both the live session (Phase 4) and the standalone progress screen
/// (Phase 3), kept out of both so neither has to duplicate it.
class ProgramRunRepository {
  ProgramRunRepository({
    ProgramRepository? programRepository,
    ProgramRunRemote? remote,
  })  : _programRepo = programRepository ?? ProgramRepository(),
        _remote = remote ?? const SupabaseProgramRunRemote();

  final ProgramRepository _programRepo;
  final PlannedSessionRepository _plannedRepo = PlannedSessionRepository();
  final ProgramRunRemote _remote;

  Future<ProgramRun?> getCurrentRun(String userId) async {
    // 1. Try the local PowerSync mirror first — it's fast and offline-safe.
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? AND is_current = 1 LIMIT 1',
      [userId],
    );
    if (rows.isNotEmpty) return ProgramRun.fromMap(rows.first);

    // 2. Fall back to the server — the local mirror can be stale when a
    //    checkpoint is stuck, but the server always has the latest state.
    try {
      final remote = await _remote.fetchCurrentRun(userId);
      if (remote != null) return ProgramRun.fromMap(remote);
    } catch (_) {
      // Server unreachable — genuinely no current run, or just offline.
    }
    return null;
  }

  /// Starts a fresh run for [programId], carrying how it progresses
  /// ('frequency' | 'order') and the duration config (sessions for order,
  /// weeks or end date for frequency).
  ///
  /// **It pauses the previous run, it does not end it.** Starting something
  /// else is a switch, not a verdict on what you left: the run that was current
  /// keeps its id, its config, its block and every session attributed to it,
  /// and can be resumed. Ending is always a separate, explicit act — see
  /// [ProgramRunLifecycle].
  ///
  /// [blockId] names the block being run. Null runs the whole program — the
  /// only option for a program with no blocks, and unchanged behaviour for one
  /// that has them.
  ///
  /// Writes to Supabase REST first (the authoritative write), then mirrors the
  /// run locally through PowerSync so the UI — and anything logged against the
  /// run, including sessions started right after — sees it at once. If the REST
  /// call fails the local write is skipped and the caller gets the error.
  Future<ProgramRun> startProgramRun(
    String userId,
    String programId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async {
    final id = _uuid.v4();
    final startedDate = DateTime.now().toUtc();

    // 1. Step the previous run aside on the server FIRST — a unique partial
    //    index enforces at most one is_current=true row per user, so the old
    //    run must be cleared before inserting the new one. Cleared, not ended:
    //    the run left behind stays resumable, and only an explicit end stamps
    //    an `ended_date`.
    try {
      await _remote.pauseCurrentRun(userId);
    } catch (_) {
      // If this fails the insert below will also fail with a duplicate-key
      // violation — let that propagate to the caller.
    }

    // 2. Authoritative write — hits Supabase directly so the run exists
    //    server-side even if PowerSync is stuck reconciling a checkpoint.
    await _remote.insertRun({
      'program_run_id': id,
      'program_id': programId,
      'user_id': userId,
      'started_date': startedDate.toIso8601String(),
      'is_current': true,
      'target_sessions': targetSessions,
      'target_weeks': targetWeeks,
      'end_date': endDate?.toUtc().toIso8601String(),
      'progression_mode': progressionMode,
      // The block must already exist server-side — `createProgramBlock` is
      // REST-first for exactly this reason (its FK is checked on upload).
      'block_id': blockId,
    });

    // 3. Mirror it locally, under the same id the server knows. Without this
    //    the run is invisible until the next download lands: `getProgress`
    //    reads locally first, and a session started in that window would be
    //    logged with `program_run_id = NULL`, silently not counting toward the
    //    run the user just began.
    //
    //    The uploader upserts (`database.dart` → `uploadData`), so the PUT this
    //    queues is a no-op against the row already on the server, and the
    //    server's copy downloads onto the same row rather than beside it. The
    //    previous run is cleared locally in the same transaction so the local
    //    queue mirrors the order the server saw — and cleared the same way the
    //    server cleared it, with no `ended_date`, so the two halves cannot
    //    disagree about whether the run that was left is paused or finished.
    //
    //    Best-effort: the run exists server-side either way, so a mirror
    //    failure logs and moves on rather than failing a begin that succeeded.
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'UPDATE fact_program_run SET is_current = 0 '
          'WHERE user_id = ? AND is_current = 1',
          [userId],
        );
        await tx.execute(
          'INSERT INTO fact_program_run '
          '(id, program_run_id, program_id, user_id, target_sessions, '
          'target_weeks, end_date, started_date, ended_date, is_current, '
          'progression_mode, block_id) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            id,
            id,
            programId,
            userId,
            targetSessions,
            targetWeeks,
            endDate?.toUtc().toIso8601String(),
            startedDate.toIso8601String(),
            null,
            1,
            progressionMode,
            blockId,
          ],
        );
      });
    } catch (e) {
      debugPrint('startProgramRun: local mirror failed: $e');
    }

    return ProgramRun(
      programRunId: id,
      programId: programId,
      userId: userId,
      startedDate: startedDate,
      isCurrent: true,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate?.toUtc(),
      progressionMode: progressionMode,
      blockId: blockId,
    );
  }

  /// Updates an active run's config — runs are mutable while in progress.
  /// Pass `clear: true` alongside a null value to explicitly clear a
  /// previously-set field (e.g. switching a frequency run from end date to
  /// weeks must clear the old end date).
  Future<void> updateRunConfig(
    String programRunId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) async {
    final updates = <String, dynamic>{};
    if (progressionMode != null) updates['progression_mode'] = progressionMode;
    if (clearSessions) updates['target_sessions'] = null;
    if (targetSessions != null) updates['target_sessions'] = targetSessions;
    if (clearWeeks) updates['target_weeks'] = null;
    if (targetWeeks != null) updates['target_weeks'] = targetWeeks;
    if (clearEndDate) updates['end_date'] = null;
    if (endDate != null) updates['end_date'] = endDate.toUtc().toIso8601String();
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.safeExec(
      'UPDATE fact_program_run SET $setClause WHERE program_run_id = ?',
      [...updates.values, programRunId],
    );
  }

  /// Steps the user's current run aside **without ending it**.
  ///
  /// The counterpart to [endCurrentRun]'s two columns: this writes only
  /// `is_current = 0`, which is exactly what makes the run paused rather than
  /// ended. Kept here (as well as on the remote) so a caller that pauses
  /// without starting anything — none today, but the state exists — has one
  /// spelling to use.
  ///
  /// Why there is no `(user_id, program_id) WHERE ended_date IS NULL` unique
  /// index on the server, which would make "one open attempt per program" a
  /// fact: this write is local, and reaches the server through PowerSync on its
  /// own schedule, while the begin that follows inserts over REST immediately.
  /// A restart begins against the same program the old run belongs to, so the
  /// insert would arrive while the server still sees that old run as open — its
  /// end is still queued locally — and the index would refuse it. A normal
  /// restart would come back as a constraint violation. The rule stays a rule
  /// of the app, enforced by the paths that produce it.
  Future<void> pauseCurrentRun(String userId) async {
    await ps.safeExec(
      'UPDATE fact_program_run SET is_current = 0 '
      'WHERE user_id = ? AND is_current = 1',
      [userId],
    );
  }

  /// Ends one run by id, stamping the end.
  ///
  /// By id because a run can be ended from either state: "End program" has to
  /// work on a paused run, which [endCurrentRun] cannot reach — that one only
  /// knows what is current.
  Future<void> endRun(String programRunId) async {
    await ps.safeExec(
      'UPDATE fact_program_run SET is_current = 0, ended_date = ? '
      'WHERE program_run_id = ?',
      [DateTime.now().toUtc().toIso8601String(), programRunId],
    );
  }

  Future<void> endCurrentRun(String userId) async {
    await ps.safeExec(
      'UPDATE fact_program_run SET is_current = 0, ended_date = ? WHERE user_id = ? AND is_current = 1',
      [DateTime.now().toUtc().toIso8601String(), userId],
    );
  }

  /// Puts a paused run back in charge, in a single local transaction.
  ///
  /// Order matters: whatever is current steps aside before this one steps up,
  /// because two `is_current` rows at once is exactly what the server's
  /// one-current unique index refuses — and the refusal would arrive as a
  /// quarantined upload, not as an error here.
  ///
  /// Local, like [endCurrentRun]: the write syncs up through PowerSync. The
  /// run being resumed is necessarily a local row — it is read with
  /// [fetchPausedRun], which reads locally — so the update always has
  /// something to land on.
  Future<void> resumeRun(String userId, String programRunId) async {
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'UPDATE fact_program_run SET is_current = 0 '
        'WHERE user_id = ? AND is_current = 1 AND program_run_id != ?',
        [userId, programRunId],
      );
      await tx.execute(
        'UPDATE fact_program_run SET is_current = 1 WHERE program_run_id = ?',
        [programRunId],
      );
    });
  }

  /// Every open run that is not current — "stepped away from", newest first.
  ///
  /// Open means `ended_date IS NULL`: the test is the whole distinction
  /// between paused and ended, so this can never return a run that is over.
  /// There can be one per program (only one run of any program is current),
  /// and the list is bounded by how many programs a human has actually paused.
  Future<List<ProgramRun>> fetchPausedRuns(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run '
      'WHERE user_id = ? AND is_current = 0 AND ended_date IS NULL '
      'ORDER BY started_date DESC',
      [userId],
    );
    return rows.map((r) => ProgramRun.fromMap(r)).toList();
  }

  /// The paused run of one program, or the newest paused run overall.
  ///
  /// [programId] is how the detail screen asks "was THIS program ever
  /// paused?"; without it the question is "what did I step away from?", which
  /// is what the library badge wants.
  Future<ProgramRun?> fetchPausedRun(String userId, {String? programId}) async {
    final runs = await fetchPausedRuns(userId);
    for (final run in runs) {
      if (programId == null || run.programId == programId) return run;
    }
    return null;
  }

  /// One run by id, or null when its row has not synced locally.
  ///
  /// Used to answer "when did the run behind this record start?" — the
  /// achievements window of a first run opens there, so the question has to be
  /// answerable for a run that is no longer current.
  Future<ProgramRun?> fetchRunById(String programRunId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE program_run_id = ? LIMIT 1',
      [programRunId],
    );
    if (rows.isEmpty) return null;
    return ProgramRun.fromMap(rows.first);
  }

  Future<List<ProgramRun>> fetchProgramHistory(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? ORDER BY started_date DESC',
      [userId],
    );
    return rows.map((r) => ProgramRun.fromMap(r)).toList();
  }

  /// Every run of one program, newest first — the history a block sequence
  /// reads.
  ///
  /// Ended runs included and, more to the point, ended runs *distinguished*:
  /// "which blocks are behind you" is the question that decides what may be
  /// begun next, and it is only answerable from the runs that were formally
  /// closed.
  Future<List<ProgramRun>> fetchRunsForProgram(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE program_id = ? '
      'ORDER BY started_date DESC',
      [programId],
    );
    return rows.map((r) => ProgramRun.fromMap(r)).toList();
  }

  Future<int> _completedWorkoutCount(String programRunId) async {
    final rows = await ps.db.getAll(
      'SELECT COUNT(*) as cnt FROM fact_session WHERE program_run_id = ? AND end_datetime IS NOT NULL',
      [programRunId],
    );
    if (rows.isEmpty) return 0;
    final v = rows.first['cnt'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// Branches on the run's progression_mode:
  /// - 'frequency': whichever planned session's join-row day_of_week matches
  ///   today (respecting a fortnight week_offset against the run's start);
  ///   null (rest day / free-form only) when nothing matches.
  /// - 'order' (default, incl. legacy runs with no mode): strict cursor over
  ///   completed-session count following the join rows' sequence_order,
  ///   never skipping based on calendar gaps.
  ///
  /// A block run sees only its own block's links. Everything downstream —
  /// the cursor, the frequency fortnight, the completion count — is already
  /// scoped to the run, so narrowing the link list here is the whole change:
  /// for a block run the cycle is the block, and `daysSinceStart` measured
  /// from the run's start makes the fortnight block-relative for free.
  Future<PlannedSession?> getNextPlannedSession({
    required Program program,
    required ProgramRun run,
  }) async {
    final links = (await _plannedRepo.fetchProgramLinks(program.programId))
        .where((l) => run.blockId == null || l.blockId == run.blockId)
        .toList();
    if (links.isEmpty) return null;
    final sessions = await _plannedRepo.fetchPlannedSessions(
      run.userId,
      programId: program.programId,
    );
    final sessionById = {for (final s in sessions) s.sessionId: s};

    if (run.progressionMode == 'frequency') {
      final today = DateTime.now().weekday; // 1=Mon..7=Sun
      final daysSinceStart =
          DateTime.now().difference(run.startedDate).inDays;
      final fortnightWeek = (daysSinceStart ~/ 7) % 2;
      for (final link in links) {
        if (link.dayOfWeek == today &&
            (link.weekOffset == null || link.weekOffset == fortnightWeek)) {
          final session = sessionById[link.plannedSessionId];
          if (session != null) return session;
        }
      }
      return null;
    }

    final ordered = links
        .where((l) => l.sequenceOrder != null)
        .toList()
      ..sort((a, b) => a.sequenceOrder!.compareTo(b.sequenceOrder!));
    final orderedSessions = ordered
        .map((l) => sessionById[l.plannedSessionId])
        .whereType<PlannedSession>()
        .toList();
    if (orderedSessions.isEmpty) return null;

    final completed = await _completedWorkoutCount(run.programRunId);
    return orderedSessions[completed % orderedSessions.length];
  }

  Future<ProgramProgress?> getProgress(String userId) async {
    final run = await getCurrentRun(userId);
    if (run == null) return null;
    return progressFor(run);
  }

  /// The same numbers for a named run, whatever its state.
  ///
  /// Split out for the paused case: a paused run is not current, so
  /// [getProgress] returns null for it and the program could not say how far
  /// it had got — which is the one thing a user coming back to a paused
  /// program wants to see. Everything is keyed off the run's id and its block,
  /// so nothing changes but the entry point.
  ///
  /// The caller decides whether to show the "next workout" this computes:
  /// nothing is scheduled while a run is paused, and [getProgress] — the read
  /// the session screen and the due prompts use — still answers for the
  /// current run only.
  Future<ProgramProgress?> progressFor(ProgramRun run) async {
    final program = await _programRepo.fetchProgram(run.programId);
    if (program == null) return null;

    // A block run's cycle is its block: scoping the count here means every
    // downstream number (in-cycle progress, isFinished, remainingLabel) is
    // block-relative without a single branch in those getters.
    final workouts = await _plannedRepo.fetchPlannedSessions(
      run.userId,
      programId: program.programId,
      blockId: run.blockId,
    );
    final completed = await _completedWorkoutCount(run.programRunId);
    final totalInCycle = workouts.length;

    // The block the run is following, named for the reader. Read separately
    // from the workout fetch because a block with no workouts is still a block,
    // and because an archived block must not blank the whole progress object.
    ProgramBlock? block;
    int? blockNumber;
    int? totalBlocks;
    if (run.blockId != null) {
      final blocks = await _programRepo.fetchBlocks(program.programId);
      totalBlocks = blocks.length;
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].blockId == run.blockId) {
          block = blocks[i];
          blockNumber =
              blocks[i].blockOrder > 0 ? blocks[i].blockOrder : i + 1;
          break;
        }
      }
    }

    // The length the run is measured against. A block declares its own — that
    // is what makes the BLOCK, not the run, the thing that says how long the
    // phase is, and it is why a late start pushes the end out rather than
    // eating into the plan. A blockless run falls through to its own targets,
    // so every number it renders is exactly what it always was.
    final targetSessions = block?.targetSessions ?? run.targetSessions;
    final targetWeeks = block?.targetWeeks ?? run.targetWeeks;

    // Which of the two bounds applies. Must be the same rule the reader uses
    // (`ProgramProgress.boundedBySessions`), or the bar measures one thing and
    // the finish check another.
    final sessionsBounded = isSessionsBounded(
      hasBlock: block != null,
      blockTargetSessions: block?.targetSessions,
      progressionMode: run.progressionMode,
    );
    final effectiveTotal =
        sessionsBounded ? (targetSessions ?? totalInCycle) : totalInCycle;
    final workoutsCompletedInCycle =
        effectiveTotal == 0 ? 0 : completed % effectiveTotal;

    // Weeks count from the RUN's start, so a block run's week number is
    // block-relative by construction — which is what a coach means by "week 2"
    // when they say it about a phase.
    final now = DateTime.now();
    final rawWeek = (now.difference(run.startedDate).inDays ~/ 7) + 1;
    // Clamped only as a label guard: past the last week it reads "Week 8 of 8"
    // while the banner asks whether to end it. Nothing derives finish from this
    // — `ProgramProgress.endsAt` compares the clock — so the clamp cannot hide
    // a run that has overrun.
    //
    // Floored at 1 for the same reason it is clamped at the top: a sub-week
    // block declares zero weeks, and "Week 0" is not a week anybody has. It is
    // still the first week of the phase, which is what the label says. The days
    // remainder deliberately does NOT fold in here — a week counter reads
    // "Week 3 of 8", never "of 8.43".
    //
    // A length that declares no weeks at all is clamped by nothing: an
    // open-ended run has no ceiling to reach, and it has always counted upward.
    final weekCeiling =
        targetWeeks == null ? null : (targetWeeks < 1 ? 1 : targetWeeks);
    final weekNumber =
        weekCeiling != null && rawWeek > weekCeiling ? weekCeiling : rawWeek;

    final next = await getNextPlannedSession(program: program, run: run);

    final progress = ProgramProgress(
      program: program,
      run: run,
      weekNumber: weekNumber,
      totalWeeks: targetWeeks,
      workoutsCompletedInCycle: workoutsCompletedInCycle,
      totalWorkoutsInCycle: effectiveTotal,
      totalWorkoutsCompleted: completed,
      nextPlannedSession: next,
      block: block,
      blockNumber: blockNumber,
      totalBlocks: totalBlocks,
    );

    // PURE READ. This used to call `endCurrentRun` when the run looked
    // finished, which meant every caller — including the library's list
    // rendering — silently mutated the database. The consequence was a run
    // that ended just because a screen was opened, with nothing recording why
    // or when. Ending a run now belongs to the ViewModel, where the mutation is
    // visible at the call site and can be paired with the revision that
    // `closeRun` cuts at the same moment.
    return progress;
  }
}
