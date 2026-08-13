import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_session.dart';
import '../models/program_progress.dart';
import '../models/program_run.dart';
import 'program_repository.dart';

const _uuid = Uuid();

/// Owns "what program is current" and "what's next" — the logic needed by
/// both the live session (Phase 4) and the standalone progress screen
/// (Phase 3), kept out of both so neither has to duplicate it.
class ProgramRunRepository {
  ProgramRunRepository({ProgramRepository? programRepository})
      : _programRepo = programRepository ?? ProgramRepository();

  final ProgramRepository _programRepo;

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
  /// optionally carrying the duration config (sessions for sequential, weeks
  /// or end date for calendar).
  ///
  /// Writes to Supabase REST first (the authoritative write), then mirrors
  /// locally through PowerSync so the UI shows the change immediately.  If the
  /// REST call fails the local write is skipped — the caller gets the error.
  Future<ProgramRun> startProgramRun(
    String userId,
    String programId, {
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
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
    );
  }

  /// Updates an active run's duration config — programs are mutable while
  /// running. Pass `clear: true` alongside a null value to explicitly clear a
  /// previously-set field (e.g. switching a calendar run from end date to
  /// weeks must clear the old end date).
  Future<void> updateRunConfig(
    String programRunId, {
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) async {
    final updates = <String, dynamic>{};
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
      'SELECT COUNT(*) as cnt FROM fact_session WHERE program_run_id = ? AND is_active = 0',
      [programRunId],
    );
    if (rows.isEmpty) return 0;
    final v = rows.first['cnt'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// Branches on the program's progression_mode:
  /// - sequential: strict cursor over completed-workout count, never skips
  ///   based on calendar gaps.
  /// - calendar: whichever planned workout's day_of_week matches today; null
  ///   (rest day / free-form only) when nothing matches.
  Future<PlannedSession?> getNextPlannedSession(
    String programId,
    String programRunId, {
    required String progressionMode,
  }) async {
    final workouts = await _programRepo.fetchPlannedSessions(programId);
    if (workouts.isEmpty) return null;

    if (progressionMode == 'calendar') {
      final today = DateTime.now().weekday; // 1=Mon..7=Sun
      for (final w in workouts) {
        if (w.dayOfWeek == today) return w;
      }
      return null;
    }

    final completed = await _completedWorkoutCount(programRunId);
    return workouts[completed % workouts.length];
  }

  Future<ProgramProgress?> getProgress(String userId) async {
    final run = await getCurrentRun(userId);
    if (run == null) return null;
    final program = await _programRepo.fetchProgram(run.programId);
    if (program == null) return null;

    final workouts = await _programRepo.fetchPlannedSessions(program.programId);
    final completed = await _completedWorkoutCount(run.programRunId);
    final totalInCycle = workouts.length;

    // Sequential: the run's configured session count overrides the planned
    // workout count for progress/finish. Calendar: the run's weeks or end date
    // overrides program.lengthWeeks.
    final effectiveTotal =
        program.progressionMode == 'sequential'
            ? (run.targetSessions ?? totalInCycle)
            : totalInCycle;
    final workoutsCompletedInCycle =
        effectiveTotal == 0 ? 0 : completed % effectiveTotal;

    final now = DateTime.now();
    final rawWeek = (now.difference(run.startedDate).inDays ~/ 7) + 1;
    final totalWeeks = run.targetWeeks ?? program.lengthWeeks;
    final weekNumber =
        totalWeeks != null && rawWeek > totalWeeks ? totalWeeks : rawWeek;

    final next = await getNextPlannedSession(
      program.programId,
      run.programRunId,
      progressionMode: program.progressionMode,
    );

    final progress = ProgramProgress(
      program: program,
      run: run,
      weekNumber: weekNumber,
      totalWeeks: totalWeeks,
      workoutsCompletedInCycle: workoutsCompletedInCycle,
      totalWorkoutsInCycle: effectiveTotal,
      totalWorkoutsCompleted: completed,
      nextPlannedSession: next,
    );

    // A completed program stops being "current" — end the run so the session
    // stops offering it and the library can show it as finished.
    final finished = progress.isFinished;
    if (finished && run.isCurrent) {
      await endCurrentRun(userId);
    }

    return progress;
  }
}
