import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/program.dart';
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
      state.value = state.value.copyWith(
        isLoading: false,
        programs: programs,
        currentProgramId: currentRun?.programId,
        clearCurrentProgramId: currentRun == null,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────

  void openCreate() =>
      state.value = state.value.copyWith(showCreate: true, createName: '');
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

  Future<void> archiveProgram(String programId) async {
    try {
      await _repo.archiveProgram(programId);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> setCurrentProgram(String programId) async {
    state.value = state.value.copyWith(settingCurrentId: programId, clearError: true);
    try {
      // Use the run returned directly from the write rather than re-reading
      // getCurrentRun immediately after — local PowerSync reads can lag a
      // just-completed remote write.
      final run = await _runRepo.startProgramRun(_userId, programId);
      state.value = state.value.copyWith(
        clearSettingCurrentId: true,
        currentProgramId: run.programId,
      );
    } catch (e) {
      state.value =
          state.value.copyWith(clearSettingCurrentId: true, error: e.toString());
    }
  }

  void dispose() => state.dispose();
}
