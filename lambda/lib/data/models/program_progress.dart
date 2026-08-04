import 'planned_workout.dart';
import 'program.dart';
import 'program_run.dart';

/// Computed value object — not a table. Built by ProgramRunRepository.getProgress
/// from the current run's history, not persisted anywhere itself.
class ProgramProgress {
  const ProgramProgress({
    required this.program,
    required this.run,
    required this.weekNumber,
    required this.workoutsCompletedInCycle,
    required this.totalWorkoutsInCycle,
    required this.totalWorkoutsCompleted,
    this.totalWeeks,
    this.nextPlannedWorkout,
  });

  final Program program;
  final ProgramRun run;
  final int weekNumber;
  final int? totalWeeks;
  final int workoutsCompletedInCycle;
  final int totalWorkoutsInCycle;

  /// Raw count of completed workouts for the run (not modulo'd by the cycle).
  final int totalWorkoutsCompleted;
  final PlannedWorkout? nextPlannedWorkout;

  /// Whether the program's cycle is complete. Sequential: the full cycle has
  /// been worked through (raw completed count reached a multiple of the cycle
  /// length — `workoutsCompletedInCycle` alone wraps via `%`). Calendar: the
  /// run has passed its lengthWeeks. When true, the run should no longer be
  /// "current".
  bool get isFinished {
    if (program.progressionMode == 'calendar') {
      return totalWeeks != null && weekNumber > totalWeeks!;
    }
    return totalWorkoutsInCycle > 0 &&
        totalWorkoutsCompleted >= totalWorkoutsInCycle;
  }

  /// 0..1 fraction of the program complete, for progress bars.
  double get progress {
    if (program.progressionMode == 'calendar') {
      final w = totalWeeks;
      if (w == null || w <= 0) return 0;
      return (weekNumber / w).clamp(0.0, 1.0);
    }
    if (totalWorkoutsInCycle <= 0) return 0;
    return (workoutsCompletedInCycle / totalWorkoutsInCycle).clamp(0.0, 1.0);
  }
}
