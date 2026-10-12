import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/sort_compare.dart';
import '../../../data/models/block_sequence.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_run.dart';
import '../../../data/models/program_usage.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../model/achievements_derivation.dart';
import '../model/program_run_lifecycle.dart';

/// What the Programs list orders by — a per-run UI choice, not persisted.
/// `lastModified` is the default: editing a program is what makes it current
/// again, and an edited program is what the user is most likely looking for.
enum ProgramSortCriterion { lastModified, name, lastUsed, mostUsed }

class ProgramLibraryState {
  const ProgramLibraryState({
    this.isLoading = false,
    this.error,
    this.programs = const [],
    this.currentProgramId,
    this.pausedProgramIds = const {},
    this.settingCurrentId,
    this.currentProgress,
    this.historyWarning,
    this.dueItems = const {},
    this.blockedWithoutBlocks = const {},
    this.usage = const {},
    this.sort = ProgramSortCriterion.lastModified,
    this.sortDesc = true,
  });

  final bool isLoading;
  final String? error;
  final List<Program> programs;
  final String? currentProgramId;

  /// Programs with a run that was stepped away from — open, resumable, not
  /// running. A set of ids rather than the runs themselves: the card only has
  /// to badge itself, and "paused" is a state, not a summary to render.
  final Set<String> pausedProgramIds;

  // programId currently being set as current (drives a per-row spinner).
  final String? settingCurrentId;

  /// Progress of the current program (null when none is current).
  final ProgramProgress? currentProgress;

  /// A run that ended because its program was archived, and whose closing
  /// record could not be written. The run is over either way, but the lost
  /// record has to be visible somewhere.
  final String? historyWarning;

  /// What each program is waiting on, keyed by program id.
  ///
  /// A map rather than a list because every reader asks "does THIS program have
  /// something due?" while rendering a card it already has. Empty is the norm —
  /// a due item is rare, and a card with none renders nothing.
  final Map<String, DueItem> dueItems;

  /// Programs made of blocks that have none yet.
  ///
  /// The one state a blocked program cannot be begun from: a run follows a
  /// block, and there is nothing here to follow. A set of ids rather than a
  /// count per program because the card asks one yes/no question of it, and
  /// a blocked program with zero blocks is exactly the state the old
  /// `blocks.isEmpty` inference could not tell from a simple program — which
  /// is why it is counted here rather than guessed at on the card.
  final Set<String> blockedWithoutBlocks;

  /// Per-program training activity (newest logged session, sessions logged) —
  /// what the "last used" / "most used" sorts read. Absent = nothing logged.
  final Map<String, ProgramUsage> usage;

  final ProgramSortCriterion sort;
  final bool sortDesc;

  /// The current program pinned to the top, the rest by the chosen sort.
  List<Program> get sortedPrograms {
    final dir = sortDesc ? -1 : 1;
    final sorted = [...programs];
    sorted.sort((a, b) {
      if (a.programId == currentProgramId) return -1;
      if (b.programId == currentProgramId) return 1;
      final byCriterion = switch (sort) {
        ProgramSortCriterion.name =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()) * dir,
        ProgramSortCriterion.lastUsed => compareNullable(
          usage[a.programId]?.lastUsed,
          usage[b.programId]?.lastUsed,
          dir,
        ),
        ProgramSortCriterion.lastModified =>
          a.updatedDate.compareTo(b.updatedDate) * dir,
        ProgramSortCriterion.mostUsed =>
          ((usage[a.programId]?.sessions ?? 0) -
                  (usage[b.programId]?.sessions ?? 0)) *
              dir,
      };
      // Name breaks every tie — two equal dates must still read A–Z.
      return byCriterion != 0
          ? byCriterion
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  DueItem? dueFor(String programId) => dueItems[programId];

  /// Whether this program is made of blocks and has none to run.
  bool hasNothingToRun(String programId) =>
      blockedWithoutBlocks.contains(programId);

  /// Whether this program has a run waiting to be picked back up.
  bool isPaused(String programId) => pausedProgramIds.contains(programId);

  /// Whether entering [programId] would step some other program's current run
  /// aside.
  ///
  /// The question is not "is anything current" but "is something *else*
  /// current": entering the program that is already running displaces nothing.
  bool displacesCurrentRun(String programId) =>
      currentProgramId != null && currentProgramId != programId;

  /// The name of the program that would be stepped aside, when [programs] can
  /// supply one.
  ///
  /// Null is not the same fact as "nothing is displaced" — that question is
  /// [displacesCurrentRun], and the two are separate because a run whose
  /// program row is missing from the list is still a run that will be paused,
  /// with the confirmation falling back to "another program".
  String? displacedProgramName(String programId) {
    if (!displacesCurrentRun(programId)) return null;
    for (final p in programs) {
      if (p.programId == currentProgramId) return p.name;
    }
    return null;
  }

  /// Whether anything other than [programId] is paused — what entering a run
  /// leaves exactly where it is.
  bool otherRunPaused(String programId) =>
      pausedProgramIds.any((id) => id != programId);

  ProgramLibraryState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<Program>? programs,
    String? currentProgramId,
    bool clearCurrentProgramId = false,
    Set<String>? pausedProgramIds,
    String? settingCurrentId,
    bool clearSettingCurrentId = false,
    ProgramProgress? currentProgress,
    bool clearCurrentProgress = false,
    String? historyWarning,
    bool clearHistoryWarning = false,
    Map<String, DueItem>? dueItems,
    Set<String>? blockedWithoutBlocks,
    Map<String, ProgramUsage>? usage,
    ProgramSortCriterion? sort,
    bool? sortDesc,
  }) =>
      ProgramLibraryState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        programs: programs ?? this.programs,
        currentProgramId: clearCurrentProgramId
            ? null
            : (currentProgramId ?? this.currentProgramId),
        pausedProgramIds: pausedProgramIds ?? this.pausedProgramIds,
        settingCurrentId: clearSettingCurrentId
            ? null
            : (settingCurrentId ?? this.settingCurrentId),
        // `currentProgress: null` cannot mean "clear" through a `??` copyWith
        // — ending a run has to say so explicitly.
        currentProgress:
            clearCurrentProgress ? null : (currentProgress ?? this.currentProgress),
        historyWarning:
            clearHistoryWarning ? null : (historyWarning ?? this.historyWarning),
        dueItems: dueItems ?? this.dueItems,
        blockedWithoutBlocks: blockedWithoutBlocks ?? this.blockedWithoutBlocks,
        usage: usage ?? this.usage,
        sort: sort ?? this.sort,
        sortDesc: sortDesc ?? this.sortDesc,
      );
}

class ProgramLibraryViewModel {
  ProgramLibraryViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ProgramHistoryRepository? historyRepo,
    AchievementsDerivation? achievementsDerivation,
    String? userId,
  })  : _repo = repo ?? ProgramRepository(),
        _runRepo = runRepo ?? ProgramRunRepository(),
        _historyRepo = historyRepo ?? ProgramHistoryRepository(),
        _userIdOverride = userId {
    _lifecycle = ProgramRunLifecycle(
      runRepo: _runRepo,
      historyRepo: _historyRepo,
      derivation: achievementsDerivation,
    );
  }

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final ProgramHistoryRepository _historyRepo;
  final String? _userIdOverride;
  late final ProgramRunLifecycle _lifecycle;
  final state = ValueNotifier(const ProgramLibraryState());

  /// The signed-in user. Overridable because host tests cannot construct
  /// `Supabase.instance` at all.
  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  Future<List<Program>> fetchArchivedPrograms() =>
      _repo.fetchArchivedPrograms(_userId);

  Future<void> reactivateProgram(String programId) async {
    await _repo.reactivateProgram(programId);
    await fetchAll();
  }

  /// Change the list's ordering, applied live from the sort sheet.
  void setSort(ProgramSortCriterion criterion, bool descending) =>
      state.value = state.value.copyWith(sort: criterion, sortDesc: descending);

  /// Sessions that a [hardDeleteProgram] would unlink — see
  /// [ProgramRepository.programSessionCount].
  Future<int> programSessionCount(String programId) =>
      _repo.programSessionCount(programId);

  Future<void> hardDeleteProgram(String programId) async {
    await _repo.hardDeleteProgram(programId);
    await fetchAll();
  }

  Future<void> fetchAll() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final programs = await _repo.fetchPrograms(_userId);
      final currentRun = await _runRepo.getCurrentRun(_userId);
      // Runs that were stepped away from. Read rather than derived from the
      // cards: "paused" is not a property of a program, it is a property of a
      // run that program happens to have open.
      final pausedRuns = await _runRepo.fetchPausedRuns(_userId);
      ProgramProgress? progress;
      if (currentRun != null) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }
      final due = await _dueItems();
      final usage = await _usage();
      state.value = state.value.copyWith(
        isLoading: false,
        programs: programs,
        currentProgramId: currentRun?.programId,
        clearCurrentProgramId: currentRun == null,
        pausedProgramIds: {for (final r in pausedRuns) r.programId},
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        dueItems: due,
        blockedWithoutBlocks: await _blockedWithoutBlocks(programs),
        usage: usage,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: friendlyError(e));
    }
  }

  /// Which of [programs] are blocked but have no blocks to run.
  ///
  /// One grouped count for the whole list rather than a read per card. A
  /// failed count is treated as "every program has what it needs": the cost of
  /// being wrong that way is a Begin that opens a sheet which then says there
  /// is nothing to run, while the cost of the other way is a card telling the
  /// user to add a block to a program that already has one.
  Future<Set<String>> _blockedWithoutBlocks(List<Program> programs) async {
    final blocked = programs.where((p) => p.usesBlocks).toList();
    if (blocked.isEmpty) return const {};
    try {
      final counts = await _repo.fetchActiveBlockCounts(_userId);
      return {
        for (final p in blocked)
          if ((counts[p.programId] ?? 0) == 0) p.programId,
      };
    } catch (_) {
      return const {};
    }
  }

  /// The due prompts, keyed by program.
  ///
  /// Swallows its failure on purpose: a due check that throws must not blank a
  /// library that loaded perfectly well — the badge is an addition to the
  /// screen, not the screen. At most one item per program is kept, earliest
  /// first, because a card can only show one.
  Future<Map<String, DueItem>> _dueItems() async {
    try {
      final items = await _historyRepo.fetchDueItems(_userId);
      final out = <String, DueItem>{};
      for (final item in items) {
        out.putIfAbsent(item.programId, () => item);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Per-program training activity, for the sort.
  ///
  /// Swallows its failure for the same reason [_dueItems] does: an ordering
  /// aid that throws must not blank a library that loaded perfectly well —
  /// the affected criteria just fall back to their name tiebreak.
  Future<Map<String, ProgramUsage>> _usage() async {
    try {
      return await _repo.fetchProgramUsage(_userId);
    } catch (_) {
      return const {};
    }
  }

  // ── Row actions ──────────────────────────────────────────────────────────

  Future<void> duplicateProgram(String programId) async {
    try {
      await _repo.duplicateProgram(_userId, programId);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  Future<void> deleteProgram(String programId) async {
    try {
      // Archiving takes every open run with it, and an open run is either
      // current or paused. Both are ended and closed here: a run that ends
      // because its program was archived produced something, and that record
      // is the only place it survives. A paused run matters most of all —
      // left open it could never be resumed (its program is gone) and never
      // end, so it would sit as a phantom pause forever.
      String? warning;
      if (state.value.currentProgramId == programId) {
        warning = await _lifecycle.end(userId: _userId);
      }
      // A separate read rather than an `else`: the two states are mutually
      // exclusive today, and reading both means this stays correct if they
      // ever are not.
      final paused = await _runRepo.fetchPausedRun(
        _userId,
        programId: programId,
      );
      if (paused != null) {
        warning ??= await _lifecycle.endRun(paused, userId: _userId);
      }
      await _repo.deleteProgram(programId);
      await fetchAll();
      if (warning != null && !_disposed) {
        state.value = state.value.copyWith(historyWarning: warning);
      }
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// The block a begin of this program would run — its next unended block.
  ///
  /// Read on demand for one sheet rather than held in state: caching it would
  /// mean invalidating it every time a block is edited or a run ends on another
  /// screen, and two local reads are cheaper than that bookkeeping.
  ///
  /// [BlockSequence] answers this of the program's blocks *and* its runs, so a
  /// paused program resumes into the block it was on, and a program whose
  /// blocks have all been run begins again at the first — a finished program is
  /// repeatable. Null means the program has no blocks at all, which is the one
  /// state a blocked begin cannot start from.
  Future<ProgramBlock?> nextBlockFor(String programId) async {
    final blocks = await _repo.fetchBlocks(programId);
    if (blocks.isEmpty) return null;
    final runs = await _runRepo.fetchRunsForProgram(programId);
    return BlockSequence(blocks: blocks, runs: runs).nextBlock;
  }

  Future<void> setCurrentProgram(
    String programId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async {
    if (_disposed) return;
    state.value = state.value.copyWith(settingCurrentId: programId, clearError: true);
    try {
      // The lifecycle steps aside the run this replaces — this screen can
      // switch away from another program's run, and that run keeps everything
      // it produced; it is paused, not ended.
      final result = await _lifecycle.begin(
        userId: _userId,
        programId: programId,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        blockId: blockId,
      );
      // The run comes from the write itself rather than a re-read: local
      // PowerSync reads can lag a just-completed remote write.
      ProgramProgress? progress;
      try {
        progress = await _runRepo.getProgress(_userId);
      } catch (_) {}
      // A simple program remembers the length it was just begun with, so the
      // next begin opens on that number. Best-effort and guarded inside the
      // repository — the run is live either way.
      await _repo.rememberDefaultTargetSessions(
        programId,
        blockId: blockId,
        targetSessions: targetSessions,
      );
      final due = await _dueItems();
      if (_disposed) return;
      // The badge follows the begin: whatever was current is now paused, and
      // the program just begun is not.
      final paused = {...state.value.pausedProgramIds}
        ..remove(result.run.programId);
      if (result.pausedRun != null) paused.add(result.pausedRun!.programId);
      state.value = state.value.copyWith(
        clearSettingCurrentId: true,
        currentProgramId: result.run.programId,
        pausedProgramIds: paused,
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        dueItems: due,
      );
    } catch (e) {
      if (_disposed) return;
      state.value =
          state.value.copyWith(clearSettingCurrentId: true, error: friendlyError(e));
    }
  }

  /// Picks a paused run back up, without a sheet.
  ///
  /// Resume takes no config: the run already has one, and it is the whole point
  /// of pausing that the config, the block and the session attribution survive.
  /// Everything this does is flip which row is current — so the only thing that
  /// can need saying afterwards is that it did not work.
  Future<void> resumeProgram(String programId) async {
    if (_disposed) return;
    state.value = state.value.copyWith(settingCurrentId: programId, clearError: true);
    try {
      final run = await _runRepo.fetchPausedRun(_userId, programId: programId);
      if (run == null) {
        // The badge and the row disagree — the card offered Resume for
        // something that is not paused any more. Refresh so the card stops
        // offering it, rather than leaving a button that cannot work.
        if (_disposed) return;
        state.value = state.value.copyWith(clearSettingCurrentId: true);
        await fetchAll();
        return;
      }
      // Read what the resume is about to step aside BEFORE stepping it aside —
      // afterwards nothing is left that says which run it was. Normally there
      // is nothing: the card only offers Resume while this program is not
      // current. But this screen is not the only writer, and a run that loses
      // its place has to end up badged as paused rather than silently vanish.
      ProgramRun? displaced;
      try {
        displaced = await _runRepo.getCurrentRun(_userId);
      } catch (_) {}

      await _lifecycle.resume(run, userId: _userId);

      // Read the winner back rather than assuming it: the resume is a local
      // write, and this check is what makes "now current" a fact instead of a
      // claim. Same discipline as the detail screen's resume.
      ProgramRun? current;
      try {
        current = await _runRepo.getCurrentRun(_userId);
      } catch (_) {}
      if (_disposed) return;
      if (current?.programRunId != run.programRunId) {
        // The write did not take. Re-read rather than render a guess — and
        // re-read FIRST, because the refresh clears the error field and the
        // explanation has to outlive it.
        await fetchAll();
        if (_disposed) return;
        state.value = state.value.copyWith(error: 'Could not resume that program.');
        return;
      }

      ProgramProgress? progress;
      try {
        progress = await _runRepo.progressFor(run);
      } catch (_) {}
      final due = await _dueItems();
      if (_disposed) return;

      // The badge follows the write: this program is no longer paused, and
      // whatever the resume displaced now is.
      final paused = {...state.value.pausedProgramIds}..remove(programId);
      if (displaced != null && displaced.programRunId != run.programRunId) {
        paused.add(displaced.programId);
      }
      state.value = state.value.copyWith(
        clearSettingCurrentId: true,
        currentProgramId: programId,
        pausedProgramIds: paused,
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        dueItems: due,
      );
    } catch (e) {
      if (_disposed) return;
      state.value = state.value.copyWith(clearSettingCurrentId: true);
      // A resume can fail after the row moved; re-read so the cards say what
      // is actually true rather than what this screen assumed. The error goes
      // on afterwards — the refresh is what clears the error field.
      await fetchAll();
      if (_disposed) return;
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
