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

  final _client = Supabase.instance.client;
  final ProgramRepository _programRepo;

  Future<ProgramRun?> getCurrentRun(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_program_run WHERE user_id = ? AND is_current = 1 LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) return null;
    return ProgramRun.fromMap(rows.first);
  }

  /// Ends any existing current run and starts a fresh one for [programId].
  /// Returns the row straight from the Supabase insert response — callers
  /// should use this return value directly rather than immediately
  /// re-querying getCurrentRun, since local PowerSync reads can lag behind a
  /// just-completed remote write (the same sync-lag gap seen elsewhere in
  /// this app, e.g. new-exercise-not-appearing).
  Future<ProgramRun> startProgramRun(String userId, String programId) async {
    await endCurrentRun(userId);

    final data = await _client
        .from('fact_program_run')
        .insert({
          'program_run_id': _uuid.v4(),
          'program_id': programId,
          'user_id': userId,
          'is_current': true,
        })
        .select()
        .single();
    return ProgramRun.fromMap(data);
  }

  Future<void> endCurrentRun(String userId) async {
    await _client
        .from('fact_program_run')
        .update({
          'is_current': false,
          'ended_date': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('is_current', true);
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
    final workoutsCompletedInCycle = totalInCycle == 0 ? 0 : completed % totalInCycle;

    final rawWeek = (DateTime.now().difference(run.startedDate).inDays ~/ 7) + 1;
    final weekNumber = program.lengthWeeks != null && rawWeek > program.lengthWeeks!
        ? program.lengthWeeks!
        : rawWeek;

    final next = await getNextPlannedWorkout(
      program.programId,
      run.programRunId,
      progressionMode: program.progressionMode,
    );

    return ProgramProgress(
      program: program,
      run: run,
      weekNumber: weekNumber,
      totalWeeks: program.lengthWeeks,
      workoutsCompletedInCycle: workoutsCompletedInCycle,
      totalWorkoutsInCycle: totalInCycle,
      nextPlannedWorkout: next,
    );
  }
}
