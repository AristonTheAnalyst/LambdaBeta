import '../../core/utils/block_length.dart';
import 'planned_session.dart';
import 'program.dart';
import 'program_block.dart';
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
    this.block,
    this.blockNumber,
    this.totalBlocks,
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

  /// The block being run, when this is a block run. Null for a blockless run,
  /// and also null if the block was archived out from under the run — the
  /// progress stays readable either way, it just loses its name.
  final ProgramBlock? block;

  /// 1-based position of [block] among the program's active blocks.
  final int? blockNumber;

  /// How many active blocks the program has. Null when blockless.
  final int? totalBlocks;

  /// True when this run is following a block rather than the whole program.
  bool get isBlockRun => block != null;

  /// "Block 2 of 3 · Accumulation" — null when there is no block to name, so
  /// a blockless caller renders exactly the label it always did.
  String? get blockLabel {
    final b = block;
    if (b == null) return null;
    final n = blockNumber;
    final t = totalBlocks;
    if (n == null || t == null) return b.name;
    return 'Block $n of $t · ${b.name}';
  }

  /// The live session's context line: "Week 2 · Accumulation · My Program".
  ///
  /// The week number counts from the run's start, so for a block run it is
  /// already the block's week and needs no adjusting here. A blockless run
  /// gets "Week 2 · My Program" — the same string it has always rendered.
  String get kickerLine {
    final b = block;
    return b == null
        ? 'Week $weekNumber · ${program.name}'
        : 'Week $weekNumber · ${b.name} · ${program.name}';
  }

  /// Whether this run is bounded by a count of sessions rather than by the
  /// calendar. See [isSessionsBounded] — the rule lives there because
  /// `getProgress` has to apply the same one when it fills in the numbers this
  /// reads.
  bool get boundedBySessions => isSessionsBounded(
        hasBlock: block != null,
        blockTargetSessions: block?.targetSessions,
        progressionMode: run.progressionMode,
      );

  /// The days remainder of the weeks length — the part whole weeks cannot
  /// express. Null for a run with no block to carry one: a blockless run's own
  /// `target_weeks` is whole weeks by design, since nothing is projected from a
  /// number typed once as a target.
  int? get targetDays => block?.targetDays;

  /// When the calendar length runs out, or null when nothing bounds this run in
  /// time.
  ///
  /// Measured from the run's **actual** start rather than from the block's
  /// planned `start_date`: a block begun late ends late. That is the whole
  /// consequence of starting a block by hand, and it is why `end_date` is a
  /// projection the editor writes rather than a second thing to keep in step.
  ///
  /// The remainder rides along, which is the point of storing one: a block of
  /// eight weeks and three days asks to be ended on its own last day, not on
  /// the Saturday the weeks alone would round to.
  ///
  /// This supersedes `ProgramRun.effectiveEndDate`, which could only ever see
  /// the run's *own* weeks — and a block run no longer has any, because the
  /// block owns the length. Same arithmetic, one level up, where the block is
  /// visible.
  DateTime? get endsAt {
    if (run.endDate != null) return run.endDate;
    final w = totalWeeks;
    return w == null ? null : endDateFor(run.startedDate, w, targetDays ?? 0);
  }

  /// Whether the run has reached the length its block declared — **not**
  /// whether it is over. Nothing ends a run but the user saying so; this is the
  /// condition that puts the question to them (`kDueRunFinished`), and the
  /// library's label for a run that is waiting on an answer.
  ///
  /// A run with no length at all — a block that declares neither weeks nor
  /// sessions — never reaches one. It is ended by hand, which is the honest
  /// reading of "open-ended" rather than a guess.
  bool get isLengthReached {
    final end = endsAt;
    if (end != null && !DateTime.now().isBefore(end)) return true;
    if (!boundedBySessions) return false;
    return totalWorkoutsInCycle > 0 &&
        totalWorkoutsCompleted >= totalWorkoutsInCycle;
  }

  /// Whether the run has done what it was asked to do and is still open —
  /// the one spelling of "this attempt is waiting on the user to end it".
  ///
  /// Two screens ask it and had each written it out for themselves: the
  /// session screen's block-complete banner and the due item that keeps
  /// prompting until the run is ended. They are the same condition, and the
  /// moment they were spelled twice they could disagree — which shows up as a
  /// banner and no prompt, or a prompt for a run the banner says is not done.
  ///
  /// Not the whole story at either site, and deliberately so: the banner also
  /// needs a block to name, and the session screen also needs no workout to be
  /// open. Those are each site's own question, asked *on top of* this one.
  bool get isReadyToEnd => isLengthReached && run.isCurrent;

  /// 0..1 fraction of the length complete, for progress bars.
  ///
  /// A bar that has filled is a bar waiting on the user, not a bar that keeps
  /// going — so this clamps at 1 and stays there until the run is ended.
  double get progress {
    if (boundedBySessions) {
      if (totalWorkoutsInCycle <= 0) return 0;
      return (workoutsCompletedInCycle / totalWorkoutsInCycle).clamp(0.0, 1.0);
    }
    final w = totalWeeks;
    if (w == null) return 0;
    if (w <= 0) {
      // A sub-week block: weeks is 0 and the days carry the whole length, which
      // is legal but breaks the assumption that a length is at least a week.
      // There is no week to take a fraction of, so the bar measures the same
      // length one unit down — the days the block declares, which are exactly
      // what [endsAt] projects from. Without this the bar would sit empty for
      // the block's whole life and then jump straight to "ready to end".
      final total = targetDays ?? 0;
      if (total <= 0) return 0;
      final elapsed = DateTime.now().difference(run.startedDate).inDays;
      return (elapsed / total).clamp(0.0, 1.0);
    }
    return (weekNumber / w).clamp(0.0, 1.0);
  }

  /// Human-readable "how much is left" — a sessions-bounded run counts
  /// sessions, a calendar-bounded one counts days or weeks.
  String get remainingLabel {
    if (isLengthReached) return 'finished';
    if (!boundedBySessions) {
      final end = endsAt;
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
