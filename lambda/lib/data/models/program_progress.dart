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
    this.totalWeeks,
    this.nextPlannedWorkout,
  });

  final Program program;
  final ProgramRun run;
  final int weekNumber;
  final int? totalWeeks;
  final int workoutsCompletedInCycle;
  final int totalWorkoutsInCycle;
  final PlannedWorkout? nextPlannedWorkout;
}
