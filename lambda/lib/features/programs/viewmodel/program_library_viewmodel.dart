import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';

class ProgramLibraryState {
  const ProgramLibraryState({
    this.isLoading = false,
    this.error,
    this.programs = const [],
    this.currentProgramId,
    this.settingCurrentId,
    this.showCreate = false,
    this.createName = '',
    this.isCreating = false,
    this.currentProgress,
    this.dueItems = const {},
  });

  final bool isLoading;
  final String? error;
  final List<Program> programs;
  final String? currentProgramId;
  // programId currently being set as current (drives a per-row spinner).
  final String? settingCurrentId;
  final bool showCreate;
  final String createName;
  final bool isCreating;

  /// Progress of the current program (null when none is current).
  final ProgramProgress? currentProgress;

  /// What each program is waiting on, keyed by program id.
  ///
  /// A map rather than a list because every reader asks "does THIS program have
  /// something due?" while rendering a card it already has. Empty is the norm —
  /// a due item is rare, and a card with none renders nothing.
  final Map<String, DueItem> dueItems;

  /// The current program pinned to the top, rest by created-date desc.
  List<Program> get sortedPrograms {
    final sorted = [...programs];
    sorted.sort((a, b) {
      if (a.programId == currentProgramId) return -1;
      if (b.programId == currentProgramId) return 1;
      return b.createdDate.compareTo(a.createdDate);
    });
    return sorted;
  }

  DueItem? dueFor(String programId) => dueItems[programId];

  ProgramLibraryState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<Program>? programs,
    String? currentProgramId,
    bool clearCurrentProgramId = false,
    String? settingCurrentId,
    bool clearSettingCurrentId = false,
    bool? showCreate,
    String? createName,
    bool? isCreating,
    ProgramProgress? currentProgress,
    Map<String, DueItem>? dueItems,
  }) =>
      ProgramLibraryState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        programs: programs ?? this.programs,
        currentProgramId: clearCurrentProgramId
            ? null
            : (currentProgramId ?? this.currentProgramId),
        settingCurrentId: clearSettingCurrentId
            ? null
            : (settingCurrentId ?? this.settingCurrentId),
        showCreate: showCreate ?? this.showCreate,
        createName: createName ?? this.createName,
        isCreating: isCreating ?? this.isCreating,
        currentProgress: currentProgress ?? this.currentProgress,
        dueItems: dueItems ?? this.dueItems,
      );
}

class ProgramLibraryViewModel {
  ProgramLibraryViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ProgramHistoryRepository? historyRepo,
  })  : _repo = repo ?? ProgramRepository(),
        _runRepo = runRepo ?? ProgramRunRepository(),
        _historyRepo = historyRepo ?? ProgramHistoryRepository();

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final ProgramHistoryRepository _historyRepo;
  final state = ValueNotifier(const ProgramLibraryState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<List<Program>> fetchArchivedPrograms() =>
      _repo.fetchArchivedPrograms(_userId);

  Future<void> reactivateProgram(String programId) async {
    await _repo.reactivateProgram(programId);
    await fetchAll();
  }

  Future<void> fetchAll() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final programs = await _repo.fetchPrograms(_userId);
      final currentRun = await _runRepo.getCurrentRun(_userId);
      ProgramProgress? progress;
      if (currentRun != null) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }
      final due = await _dueItems();
      state.value = state.value.copyWith(
        isLoading: false,
        programs: programs,
        currentProgramId: currentRun?.programId,
        clearCurrentProgramId: currentRun == null,
        currentProgress: progress,
        dueItems: due,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
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

  // ── Create ────────────────────────────────────────────────────────────────

  void openCreate() => state.value = state.value.copyWith(
      showCreate: true, createName: '');
  void closeCreate() => state.value = state.value.copyWith(showCreate: false);
  void setCreateName(String v) =>
      state.value = state.value.copyWith(createName: v);

  Future<String?> submitCreate() async {
    final s = state.value;
    final name = s.createName.trim();
    if (name.isEmpty) return null;
    state.value = s.copyWith(isCreating: true, clearError: true);
    try {
      final created = await _repo.createProgram(_userId, name: name);
      state.value = state.value.copyWith(isCreating: false, showCreate: false);
      await fetchAll();
      return created.programId;
    } catch (e) {
      state.value = state.value.copyWith(isCreating: false, error: e.toString());
      return null;
    }
  }

  // ── Row actions ──────────────────────────────────────────────────────────

  Future<void> duplicateProgram(String programId) async {
    try {
      await _repo.duplicateProgram(_userId, programId);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deleteProgram(String programId) async {
    try {
      // If the user is deleting the currently-running program, end the run
      // first so its progress is cleanly closed rather than silently lost
      // in the cascade delete.
      if (state.value.currentProgramId == programId) {
        await _runRepo.endCurrentRun(_userId);
      }
      await _repo.deleteProgram(programId);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// The program's active blocks, for the begin sheet's run picker.
  ///
  /// Not held in state: the list is read on demand for one sheet, and caching
  /// it would mean invalidating it every time a block is edited on another
  /// screen. A read of a handful of local rows is cheaper than that bookkeeping.
  Future<List<ProgramBlock>> blocksFor(String programId) =>
      _repo.fetchBlocks(programId);

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
      // Use the run returned directly from the write rather than re-reading
      // getCurrentRun immediately after — local PowerSync reads can lag a
      // just-completed remote write.
      final run = await _runRepo.startProgramRun(_userId, programId,
          progressionMode: progressionMode,
          targetSessions: targetSessions,
          targetWeeks: targetWeeks,
          endDate: endDate,
          blockId: blockId);
      if (_disposed) return;
      state.value = state.value.copyWith(
        clearSettingCurrentId: true,
        currentProgramId: run.programId,
      );
    } catch (e) {
      if (_disposed) return;
      state.value =
          state.value.copyWith(clearSettingCurrentId: true, error: e.toString());
    }
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
