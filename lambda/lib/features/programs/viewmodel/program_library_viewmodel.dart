import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_progress.dart';
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
    this.createProgression = 'sequential',
    this.isCreating = false,
    this.currentProgress,
  });

  final bool isLoading;
  final String? error;
  final List<Program> programs;
  final String? currentProgramId;
  // programId currently being set as current (drives a per-row spinner).
  final String? settingCurrentId;
  final bool showCreate;
  final String createName;
  final String createProgression;
  final bool isCreating;

  /// Progress of the current program (null when none is current).
  final ProgramProgress? currentProgress;

  /// Current program pinned to the top, rest by created-date desc.
  List<Program> get sortedPrograms {
    final sorted = [...programs];
    sorted.sort((a, b) {
      if (a.programId == currentProgramId) return -1;
      if (b.programId == currentProgramId) return 1;
      return b.createdDate.compareTo(a.createdDate);
    });
    return sorted;
  }

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
    String? createProgression,
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
        createProgression: createProgression ?? this.createProgression,
        isCreating: isCreating ?? this.isCreating,
        currentProgress: currentProgress ?? this.currentProgress,
      );
}

class ProgramLibraryViewModel {
  ProgramLibraryViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
  })  : _repo = repo ?? ProgramRepository(),
        _runRepo = runRepo ?? ProgramRunRepository();

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final state = ValueNotifier(const ProgramLibraryState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

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
      state.value = state.value.copyWith(
        isLoading: false,
        programs: programs,
        currentProgramId: currentRun?.programId,
        clearCurrentProgramId: currentRun == null,
        currentProgress: progress,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────

  void openCreate() => state.value = state.value.copyWith(
      showCreate: true, createName: '', createProgression: 'sequential');
  void closeCreate() => state.value = state.value.copyWith(showCreate: false);
  void setCreateName(String v) =>
      state.value = state.value.copyWith(createName: v);
  void setCreateProgression(String v) =>
      state.value = state.value.copyWith(createProgression: v);

  Future<String?> submitCreate() async {
    final s = state.value;
    final name = s.createName.trim();
    if (name.isEmpty) return null;
    state.value = s.copyWith(isCreating: true, clearError: true);
    try {
      final created = await _repo.createProgram(_userId,
          name: name, progressionMode: s.createProgression);
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

  Future<void> archiveProgram(String programId) async {
    try {
      await _repo.archiveProgram(programId);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> setCurrentProgram(
    String programId, {
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
  }) async {
    if (_disposed) return;
    state.value = state.value.copyWith(settingCurrentId: programId, clearError: true);
    try {
      // Use the run returned directly from the write rather than re-reading
      // getCurrentRun immediately after — local PowerSync reads can lag a
      // just-completed remote write.
      final run = await _runRepo.startProgramRun(_userId, programId,
          targetSessions: targetSessions,
          targetWeeks: targetWeeks,
          endDate: endDate);
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
