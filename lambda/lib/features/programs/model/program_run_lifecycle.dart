import 'package:flutter/foundation.dart';

import '../../../data/models/program_run.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import 'achievements_derivation.dart';

/// Everything that happens to a run, in one place.
///
/// The rules a run follows are not complicated — begin, edit the config, end,
/// record what it produced — but they were previously spelled out once per
/// screen that could start one, and the spellings disagreed in ways that lost
/// data. The library's begin used the repository's run id but never closed the
/// run it replaced; the detail screen's closed the replaced run but addressed
/// every later write with an id it had minted itself, which no row ever carried.
/// Two paths, two half-correct answers. They now call the same methods, so they
/// cannot disagree again.
///
/// Lives here, beside [AchievementsDerivation] and for the same layering reason:
/// the ordering rules belong to the feature, not the data layer.
class ProgramRunLifecycle {
  ProgramRunLifecycle({
    ProgramRunRepository? runRepo,
    ProgramHistoryRepository? historyRepo,
    AchievementsDerivation? derivation,
  }) : _runRepo = runRepo ?? ProgramRunRepository(),
       _historyRepo = historyRepo ?? ProgramHistoryRepository(),
       _derivation = derivation ?? AchievementsDerivation();

  final ProgramRunRepository _runRepo;
  final ProgramHistoryRepository _historyRepo;
  final AchievementsDerivation _derivation;

  /// Begins a run and **pauses** whatever it replaced.
  ///
  /// Returns the run the repository actually created — its id is the one every
  /// later write must address — plus the run that was stepped aside, when
  /// there was one. Pausing cuts no record and ends nothing: the run that was
  /// left keeps its id, its config, its block and every session attributed to
  /// it, and the caller can say so ("Lambda paused X — pick it back up any
  /// time"). Only an explicit end freezes a run's record.
  ///
  /// The begin either succeeds or does not happen (it throws on failure);
  /// there is no half-state left to warn about, which is what the old
  /// `closeWarning` was for — that warning belonged to a begin that *ended*
  /// the run it replaced.
  Future<({ProgramRun run, ProgramRun? pausedRun})> begin({
    required String userId,
    required String programId,
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async {
    // Read what we are about to step aside BEFORE stepping it aside —
    // afterwards there is nothing left that says which run it was.
    ProgramRun? previous;
    try {
      previous = await _runRepo.getCurrentRun(userId);
    } catch (_) {
      // A diagnostic read must not block a begin; treated as "nothing was
      // running".
    }

    final run = await _runRepo.startProgramRun(
      userId,
      programId,
      progressionMode: progressionMode,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate,
      blockId: blockId,
    );

    // Re-beginning the same row (a retry that got far enough to insert) is not
    // a replacement — nothing was stepped aside for it.
    //
    // Returned in its new state, not as it was read: the caller says "Lambda
    // paused X" and every later read of this object has to agree.
    final paused = previous != null && previous.programRunId != run.programRunId
        ? previous.asPaused()
        : null;
    return (run: run, pausedRun: paused);
  }

  /// Ends the user's current run and cuts its close record.
  ///
  /// Returns null on success, or a warning when the run ended but its record
  /// could not be written. Throws if the end itself fails — that leaves the run
  /// looking active, which the caller must know about.
  Future<String?> end({required String userId}) async {
    ProgramRun? run;
    try {
      run = await _runRepo.getCurrentRun(userId);
    } catch (_) {
      // Fall through: the end below is what matters, and a run we cannot read
      // is a run we cannot record.
    }
    await _runRepo.endCurrentRun(userId);
    if (run == null) return null;
    return close(run, userId: userId);
  }

  /// Ends one named run — current *or* paused — and cuts its close record.
  ///
  /// This is "End program" for a run that is not running: [end] ends whatever
  /// is current, which a paused run never is, so ending one has to be asked
  /// for by name. Ending is always an explicit act; the user can end a run
  /// they are not finished with, and its record says what it got to.
  Future<String?> endRun(ProgramRun run, {required String userId}) async {
    await _runRepo.endRun(run.programRunId);
    return close(run, userId: userId);
  }

  /// Puts a paused run back in charge.
  ///
  /// Same run, same id, same config, same block, same attribution — which is
  /// the whole difference between pausing and ending. Progress and the
  /// next-workout pick therefore resume exactly where they were left.
  Future<void> resume(ProgramRun run, {required String userId}) =>
      _runRepo.resumeRun(userId, run.programRunId);

  /// Starts an attempt over: the old run is **ended with its record**, and a
  /// fresh run begins.
  ///
  /// What a restart carries over is nothing about the run — new id, fresh
  /// config (the caller opens the sheet prefilled with the old numbers so
  /// "fresh" is a choice rather than an amnesia), the session cursor back at
  /// the first workout, the count back at zero.
  ///
  /// What it does not destroy: every logged session stays a `fact_session` row
  /// attributed to the old run, the program and its workouts are untouched,
  /// and program-scoped goals remain in force — they belong to the program,
  /// not to an attempt at it. Nothing is claimed twice either: the restart's
  /// close record is a checkpoint, so the new run's achievements window opens
  /// where the old attempt ended.
  ///
  /// Scoped to what the old run ran: restarting a block restarts that block,
  /// not the program around it.
  Future<({ProgramRun run, ProgramRun? pausedRun, String? warning})> restart({
    required ProgramRun oldRun,
    required String userId,
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
  }) async {
    // A current run is ended through the by-user path (which is the one that
    // can reach it); a paused one by id. Both cut the record.
    final warning = oldRun.isCurrent
        ? await end(userId: userId)
        : await endRun(oldRun, userId: userId);

    final result = await begin(
      userId: userId,
      programId: oldRun.programId,
      progressionMode: progressionMode ?? oldRun.progressionMode,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate,
      blockId: oldRun.blockId,
    );
    return (run: result.run, pausedRun: result.pausedRun, warning: warning);
  }

  /// Writes the close record for [run]: the achievements it produced, frozen,
  /// as one review carrying the snapshot of what the run ran.
  ///
  /// Returns null on success, or a warning string on failure — never throws.
  /// The run is over by the time this runs; an error that propagated from here
  /// would have the caller reporting a failed end for an end that happened.
  Future<String?> close(ProgramRun run, {required String userId}) async {
    try {
      // The window opens at the previous checkpoint of this scope — or, on a
      // first run, exactly where the run started. Nothing before this run
      // belongs to it, and a program-level review cut in between does not open
      // a block's window: they are different scopes, and neither answers for
      // the other.
      final from = await _historyRepo.checkpointFor(
        run.programId,
        blockId: run.blockId,
        fallback: run.startedDate,
      );
      final achievements = await _derivation.derive(
        userId: userId,
        from: from,
        programId: run.programId,
        blockId: run.blockId,
      );
      await _historyRepo.closeRun(
        userId: userId,
        programId: run.programId,
        runId: run.programRunId,
        // `block_id` is the scope: null closes the program, an id closes that
        // block. It is the only thing distinguishing the two.
        blockId: run.blockId,
        achievementsJson: achievements.encode(),
      );
      return null;
    } catch (e) {
      // Logged rather than silent — a lost record is invisible otherwise, and
      // the caller surfaces the returned warning.
      debugPrint(
        'ProgramRunLifecycle: closing run ${run.programRunId} '
        'failed: $e',
      );
      return 'The run ended, but its record could not be saved.';
    }
  }

  /// Updates a run's config, returning the run as it now stands.
  ///
  /// The rebuild preserves every field the caller did not touch — `blockId`
  /// most of all: editing a block run's duration through a rebuild that
  /// recomputed only its arguments used to silently drop the block, which
  /// un-blocks the run for goal scoping and mislabels its close record.
  Future<ProgramRun> updateConfig(
    ProgramRun run, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) async {
    await _runRepo.updateRunConfig(
      run.programRunId,
      progressionMode: progressionMode,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate,
      clearSessions: clearSessions,
      clearWeeks: clearWeeks,
      clearEndDate: clearEndDate,
    );
    return withConfig(
      run,
      progressionMode: progressionMode,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate,
      clearSessions: clearSessions,
      clearWeeks: clearWeeks,
      clearEndDate: clearEndDate,
    );
  }

  /// The pure half of [updateConfig] — the run with the passed changes applied
  /// and everything else, including the block, left alone.
  static ProgramRun withConfig(
    ProgramRun run, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) {
    return ProgramRun(
      programRunId: run.programRunId,
      programId: run.programId,
      userId: run.userId,
      startedDate: run.startedDate,
      endedDate: run.endedDate,
      isCurrent: run.isCurrent,
      blockId: run.blockId,
      progressionMode: progressionMode ?? run.progressionMode,
      targetSessions: clearSessions
          ? null
          : (targetSessions ?? run.targetSessions),
      targetWeeks: clearWeeks ? null : (targetWeeks ?? run.targetWeeks),
      endDate: clearEndDate ? null : (endDate ?? run.endDate),
    );
  }
}
