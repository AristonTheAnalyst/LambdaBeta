import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_workout.dart';
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
  final _client = Supabase.instance.client;

  Future<ProgramRun?> getCurrentRun(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? AND is_current = 1 LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) return null;
    return ProgramRun.fromMap(rows.first);
  }

  /// Ends any existing current run and starts a fresh one for [programId],
  /// optionally carrying the duration config (sessions for sequential, weeks
  /// or end date for calendar).
  Future<ProgramRun> startProgramRun(
    String userId,
    String programId, {
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
  }) async {
    final id = _uuid.v4();
    final startedDate = DateTime.now().toUtc();

    // Both REST calls are individually wrapped in try-catch with short
    // timeouts — on this device the Supabase API is unreachable and hangs
    // forever without a timeout.  The first call (`endCurrentRun`) had no
    // timeout at all, which was the hang.
    try {
      await endCurrentRun(userId);
    } catch (_) {}

    try {
      await _client.from('fact_program_run').insert({
        'program_run_id': id,
        'program_id': programId,
        'user_id': userId,
        'started_date': startedDate.toIso8601String(),
        'is_current': true,
        'target_sessions': targetSessions,
        'target_weeks': targetWeeks,
        'end_date': endDate?.toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
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
    try {
      await _client.from('fact_program_run').update(updates).eq('program_run_id', programRunId)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> endCurrentRun(String userId) async {
    try {
      await _client.from('fact_program_run').update({
        'is_current': false,
        'ended_date': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId).eq('is_current', true)
        .timeout(const Duration(seconds: 3));
    } catch (_) {}
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
      'SELECT COUNT(*) as cnt FROM fact_workout WHERE program_run_id = ? AND is_active = 0',
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
  Future<PlannedWorkout?> getNextPlannedWorkout(
    String programId,
    String programRunId, {
    required String progressionMode,
  }) async {
    final workouts = await _programRepo.fetchPlannedWorkouts(programId);
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

    final workouts = await _programRepo.fetchPlannedWorkouts(program.programId);
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

    final next = await getNextPlannedWorkout(
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
      nextPlannedWorkout: next,
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
