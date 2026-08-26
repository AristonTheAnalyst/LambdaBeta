import 'planned_session.dart';
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
    this.nextPlannedSession,
  });

  final Program program;
  final ProgramRun run;
  final int weekNumber;
  final int? totalWeeks;
  final int workoutsCompletedInCycle;
  final int totalWorkoutsInCycle;

  /// Raw count of completed workouts for the run (not modulo'd by the cycle).
  final int totalWorkoutsCompleted;
  final PlannedSession? nextPlannedSession;

  /// Whether the program's cycle is complete. Order: the configured
  /// session count (or the planned-session cycle) has been worked through.
  /// Frequency: the run has passed its weeks or explicit end date. When true,
  /// the run should no longer be "current".
  bool get isFinished {
    if (run.progressionMode == 'frequency') {
      final end = run.effectiveEndDate;
      if (end != null && DateTime.now().isAfter(end)) return true;
      return totalWeeks != null && weekNumber > totalWeeks!;
    }
    return totalWorkoutsInCycle > 0 &&
        totalWorkoutsCompleted >= totalWorkoutsInCycle;
  }

  /// 0..1 fraction of the program complete, for progress bars.
  double get progress {
    if (run.progressionMode == 'frequency') {
      final w = totalWeeks;
      if (w == null || w <= 0) return 0;
      return (weekNumber / w).clamp(0.0, 1.0);
    }
    if (totalWorkoutsInCycle <= 0) return 0;
    return (workoutsCompletedInCycle / totalWorkoutsInCycle).clamp(0.0, 1.0);
  }

  /// Human-readable "how much is left" — order shows remaining sessions,
  /// frequency shows weeks or days remaining (by weeks or end date).
  String get remainingLabel {
    if (isFinished) return 'finished';
    if (run.progressionMode == 'frequency') {
      final end = run.effectiveEndDate;
      if (end != null) {
        final days = end.difference(DateTime.now()).inDays;
        if (days <= 0) return 'ends today';
        return days == 1 ? '1 day left' : '$days days left';
      }
      final w = totalWeeks;
      if (w != null) {
        final left = w - weekNumber;
        return left <= 0 ? 'final week' : '$left week${left == 1 ? '' : 's'} left';
      }
      return 'ongoing';
    }
    final left = totalWorkoutsInCycle - totalWorkoutsCompleted;
    return left <= 0 ? 'final session' : '$left session${left == 1 ? '' : 's'} left';
  }
}
