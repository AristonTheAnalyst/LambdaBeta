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

/// Owns "what program is current" and "what's next" — the logic needed by
/// both the live session (Phase 4) and the standalone progress screen
/// (Phase 3), kept out of both so neither has to duplicate it.
class ProgramRunRepository {
  ProgramRunRepository({ProgramRepository? programRepository})
      : _programRepo = programRepository ?? ProgramRepository();

  final ProgramRepository _programRepo;
  final PlannedSessionRepository _plannedRepo = PlannedSessionRepository();

  Future<ProgramRun?> getCurrentRun(String userId) async {
    // 1. Try the local PowerSync mirror first — it's fast and offline-safe.
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? AND is_current = 1 LIMIT 1',
      [userId],
    );
    if (rows.isNotEmpty) return ProgramRun.fromMap(rows.first);

    // 2. Fall back to Supabase REST — the local PowerSync DB can be stale when
    //    a checkpoint is stuck, but the server always has the latest state.
    try {
      final remote = await Supabase.instance.client
          .from('fact_program_run')
          .select('*')
          .eq('user_id', userId)
          .eq('is_current', true)
          .limit(1)
          .timeout(const Duration(seconds: 5));
      if (remote.isNotEmpty) return ProgramRun.fromMap(remote.first);
    } catch (_) {
      // Server unreachable — genuinely no current run, or just offline.
    }
    return null;
  }

  /// Ends any existing current run and starts a fresh one for [programId],
  /// carrying how it progresses ('frequency' | 'order') and the duration
  /// config (sessions for order, weeks or end date for frequency).
  ///
  /// [blockId] names the block being run. Null runs the whole program — the
  /// only option for a program with no blocks, and unchanged behaviour for one
  /// that has them.
  ///
  /// Writes to Supabase REST first (the authoritative write), then mirrors
  /// locally through PowerSync so the UI shows the change immediately.  If the
  /// REST call fails the local write is skipped — the caller gets the error.
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
    final client = Supabase.instance.client;

    // 1. End the previous run on the server FIRST — a unique partial index
    //    enforces at most one is_current=true row per user, so the old run
    //    must be cleared before inserting the new one.
    try {
      await client.from('fact_program_run').update({
        'is_current': false,
        'ended_date': startedDate.toIso8601String(),
      }).eq('user_id', userId).eq('is_current', true)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // If this fails the insert below will also fail with a duplicate-key
      // violation — let that propagate to the caller.
    }

    // 2. Authoritative write — hits Supabase directly so the run exists
    //    server-side even if PowerSync is stuck reconciling a checkpoint.
    await client.from('fact_program_run').insert({
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
    }).timeout(const Duration(seconds: 8));

    // No local PowerSync mirror — writing locally creates a CRUD entry that
    // blocks the checkpoint from applying (the row already exists server-side
    // and PowerSync will download it on the next successful sync).

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

  Future<void> endCurrentRun(String userId) async {
    await ps.safeExec(
      'UPDATE fact_program_run SET is_current = 0, ended_date = ? WHERE user_id = ? AND is_current = 1',
      [DateTime.now().toUtc().toIso8601String(), userId],
    );
  }

  Future<List<ProgramRun>> fetchProgramHistory(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? ORDER BY started_date DESC',
      [userId],
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
    final program = await _programRepo.fetchProgram(run.programId);
    if (program == null) return null;

    // A block run's cycle is its block: scoping the count here means every
    // downstream number (in-cycle progress, isFinished, remainingLabel) is
    // block-relative without a single branch in those getters.
    final workouts = await _plannedRepo.fetchPlannedSessions(
      userId,
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
