import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/custom_exercise.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/repositories/exercise_repository.dart';

class ExerciseState {
  const ExerciseState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.exercises = const [],
    this.variations = const [],
    this.exerciseDetailMap = const {},
    this.activeTab = 0,
    this.exSearch = '',
    this.varSearch = '',
    // Edit exercise modal
    this.editExercise,
    this.editExName = '',
    this.editExOriginalVarIds = const {},
    this.editExDraftVarIds = const {},
    this.editExLoadingVars = false,
    // Edit variation modal
    this.editVariation,
    this.editVarName = '',
    this.editVarOriginalExIds = const {},
    this.editVarDraftExIds = const {},
    this.editVarLoadingExs = false,
    // Create modals
    this.createExName = '',
    this.createVarName = '',
    this.showCreateEx = false,
    this.showCreateVar = false,
    this.isCreatingEx = false,
    this.isCreatingVar = false,
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final List<CustomExercise> exercises;
  final List<CustomVariation> variations;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final int activeTab;
  final String exSearch;
  final String varSearch;

  final CustomExercise? editExercise;
  final String editExName;
  final Set<String> editExOriginalVarIds;
  final Set<String> editExDraftVarIds;
  final bool editExLoadingVars;

  final CustomVariation? editVariation;
  final String editVarName;
  final Set<String> editVarOriginalExIds;
  final Set<String> editVarDraftExIds;
  final bool editVarLoadingExs;

  final String createExName;
  final String createVarName;
  final bool showCreateEx;
  final bool showCreateVar;
  final bool isCreatingEx;
  final bool isCreatingVar;

  List<CustomExercise> get filteredExercises => exSearch.isEmpty
      ? exercises
      : exercises
          .where((e) =>
              e.name.toLowerCase().contains(exSearch.toLowerCase()))
          .toList();

  List<CustomVariation> get filteredVariations => varSearch.isEmpty
      ? variations
      : variations
          .where((v) =>
              v.name.toLowerCase().contains(varSearch.toLowerCase()))
          .toList();

  List<CustomVariation> get editExAssignedVars =>
      variations.where((v) => editExDraftVarIds.contains(v.variationId)).toList();

  List<CustomVariation> get editExAvailableVars =>
      variations.where((v) => !editExDraftVarIds.contains(v.variationId)).toList();

  List<CustomExercise> get editVarAssignedExs =>
      exercises.where((e) => editVarDraftExIds.contains(e.exerciseId)).toList();

  List<CustomExercise> get editVarAvailableExs =>
      exercises.where((e) => !editVarDraftExIds.contains(e.exerciseId)).toList();

  ExerciseState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    List<CustomExercise>? exercises,
    List<CustomVariation>? variations,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    int? activeTab,
    String? exSearch,
    String? varSearch,
    CustomExercise? editExercise,
    bool clearEditEx = false,
    String? editExName,
    Set<String>? editExOriginalVarIds,
    Set<String>? editExDraftVarIds,
    bool? editExLoadingVars,
    CustomVariation? editVariation,
    bool clearEditVar = false,
    String? editVarName,
    Set<String>? editVarOriginalExIds,
    Set<String>? editVarDraftExIds,
    bool? editVarLoadingExs,
    String? createExName,
    String? createVarName,
    bool? showCreateEx,
    bool? showCreateVar,
    bool? isCreatingEx,
    bool? isCreatingVar,
  }) =>
      ExerciseState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : error ?? this.error,
        exercises: exercises ?? this.exercises,
        variations: variations ?? this.variations,
        exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
        activeTab: activeTab ?? this.activeTab,
        exSearch: exSearch ?? this.exSearch,
        varSearch: varSearch ?? this.varSearch,
        editExercise: clearEditEx ? null : (editExercise ?? this.editExercise),
        editExName: clearEditEx ? '' : (editExName ?? this.editExName),
        editExOriginalVarIds: clearEditEx ? {} : (editExOriginalVarIds ?? this.editExOriginalVarIds),
        editExDraftVarIds: clearEditEx ? {} : (editExDraftVarIds ?? this.editExDraftVarIds),
        editExLoadingVars: clearEditEx ? false : (editExLoadingVars ?? this.editExLoadingVars),
        editVariation: clearEditVar ? null : (editVariation ?? this.editVariation),
        editVarName: clearEditVar ? '' : (editVarName ?? this.editVarName),
        editVarOriginalExIds: clearEditVar ? {} : (editVarOriginalExIds ?? this.editVarOriginalExIds),
        editVarDraftExIds: clearEditVar ? {} : (editVarDraftExIds ?? this.editVarDraftExIds),
        editVarLoadingExs: clearEditVar ? false : (editVarLoadingExs ?? this.editVarLoadingExs),
        createExName: createExName ?? this.createExName,
        createVarName: createVarName ?? this.createVarName,
        showCreateEx: showCreateEx ?? this.showCreateEx,
        showCreateVar: showCreateVar ?? this.showCreateVar,
        isCreatingEx: isCreatingEx ?? this.isCreatingEx,
        isCreatingVar: isCreatingVar ?? this.isCreatingVar,
      );
}

class ExerciseViewModel {
  ExerciseViewModel({ExerciseRepository? repo})
      : _repo = repo ?? ExerciseRepository();

  final ExerciseRepository _repo;
  final state = ValueNotifier(const ExerciseState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> fetchAll() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final exercises  = await _repo.fetchExercises(_userId);
      final variations = await _repo.fetchVariations(_userId);
      final detailMap  = await _repo.fetchExerciseDetailMap(_userId);
      state.value = state.value.copyWith(
        isLoading: false,
        exercises: exercises,
        variations: variations,
        exerciseDetailMap: detailMap,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setTab(int i) => state.value = state.value.copyWith(activeTab: i);
  void setExSearch(String q) => state.value = state.value.copyWith(exSearch: q);
  void setVarSearch(String q) => state.value = state.value.copyWith(varSearch: q);

  // ── Open edit exercise ─────────────────────────────────────────────────────

  Future<void> openEditExercise(CustomExercise ex) async {
    state.value = state.value.copyWith(
      editExercise: ex,
      editExName: ex.name,
      editExLoadingVars: true,
      clearError: true,
    );
    try {
      final bridges = await _repo.fetchBridges(_userId);
      final varIds = bridges
          .where((b) => b['custom_exercise_id'] == ex.exerciseId)
          .map((b) => b['custom_variation_id'] as String)
          .toSet();
      state.value = state.value.copyWith(
        editExOriginalVarIds: varIds,
        editExDraftVarIds: Set.from(varIds),
        editExLoadingVars: false,
      );
    } catch (_) {
      state.value = state.value.copyWith(editExLoadingVars: false);
    }
  }

  void closeEditExercise() => state.value = state.value.copyWith(clearEditEx: true);

  void setEditExName(String v) => state.value = state.value.copyWith(editExName: v);

  void addEditExVarIds(List<String> ids) {
    final next = Set<String>.from(state.value.editExDraftVarIds)..addAll(ids);
    state.value = state.value.copyWith(editExDraftVarIds: next);
  }

  void removeEditExVarId(String id) {
    final next = Set<String>.from(state.value.editExDraftVarIds)..remove(id);
    state.value = state.value.copyWith(editExDraftVarIds: next);
  }

  Future<void> saveEditExercise() async {
    final s = state.value;
    if (s.editExercise == null || s.editExName.trim().isEmpty) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateExercise(s.editExercise!.exerciseId, s.editExName.trim());

      // Diff bridge assignments
      final toAdd    = s.editExDraftVarIds.difference(s.editExOriginalVarIds);
      final toRemove = s.editExOriginalVarIds.difference(s.editExDraftVarIds);
      for (final varId in toAdd) {
        await _repo.addBridge(_userId, s.editExercise!.exerciseId, varId);
      }
      for (final varId in toRemove) {
        await _repo.removeBridge(s.editExercise!.exerciseId, varId);
      }

      state.value = state.value.copyWith(isSaving: false, clearEditEx: true);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  Future<void> deleteExercise(String exerciseId) async {
    state.value = state.value.copyWith(clearEditEx: true);
    await _repo.deactivateExercise(exerciseId);
    await fetchAll();
  }

  // ── Open edit variation ────────────────────────────────────────────────────

  Future<void> openEditVariation(CustomVariation v) async {
    state.value = state.value.copyWith(
      editVariation: v,
      editVarName: v.name,
      editVarLoadingExs: true,
      clearError: true,
    );
    try {
      final bridges = await _repo.fetchBridges(_userId);
      final exIds = bridges
          .where((b) => b['custom_variation_id'] == v.variationId)
          .map((b) => b['custom_exercise_id'] as String)
          .toSet();
      state.value = state.value.copyWith(
        editVarOriginalExIds: exIds,
        editVarDraftExIds: Set.from(exIds),
        editVarLoadingExs: false,
      );
    } catch (_) {
      state.value = state.value.copyWith(editVarLoadingExs: false);
    }
  }

  void closeEditVariation() => state.value = state.value.copyWith(clearEditVar: true);

  void setEditVarName(String v) => state.value = state.value.copyWith(editVarName: v);

  void addEditVarExIds(List<String> ids) {
    final next = Set<String>.from(state.value.editVarDraftExIds)..addAll(ids);
    state.value = state.value.copyWith(editVarDraftExIds: next);
  }

  void removeEditVarExId(String id) {
    final next = Set<String>.from(state.value.editVarDraftExIds)..remove(id);
    state.value = state.value.copyWith(editVarDraftExIds: next);
  }

  Future<void> saveEditVariation() async {
    final s = state.value;
    if (s.editVariation == null || s.editVarName.trim().isEmpty) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateVariation(s.editVariation!.variationId, s.editVarName.trim());

      final toAdd    = s.editVarDraftExIds.difference(s.editVarOriginalExIds);
      final toRemove = s.editVarOriginalExIds.difference(s.editVarDraftExIds);
      for (final exId in toAdd) {
        await _repo.addBridge(_userId, exId, s.editVariation!.variationId);
      }
      for (final exId in toRemove) {
        await _repo.removeBridge(exId, s.editVariation!.variationId);
      }

      state.value = state.value.copyWith(isSaving: false, clearEditVar: true);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  Future<void> deleteVariation(String variationId) async {
    state.value = state.value.copyWith(clearEditVar: true);
    await _repo.deactivateVariation(variationId);
    await fetchAll();
  }

  // ── Create exercise ────────────────────────────────────────────────────────

  void openCreateExercise() =>
      state.value = state.value.copyWith(showCreateEx: true, createExName: '');
  void closeCreateExercise() =>
      state.value = state.value.copyWith(showCreateEx: false);
  void setCreateExName(String v) =>
      state.value = state.value.copyWith(createExName: v);

  Future<String?> submitCreateExercise() async {
    final s = state.value;
    final name = s.createExName.trim();
    if (name.isEmpty) return null;
    state.value = s.copyWith(isCreatingEx: true);
    try {
      final existing = await _repo.findExerciseByName(_userId, name);
      String id;
      if (existing != null) {
        if (existing.isActive) {
          state.value = state.value.copyWith(
              isCreatingEx: false,
              error: '"$name" already exists.');
          return null;
        }
        await _repo.reactivateExercise(existing.exerciseId);
        id = existing.exerciseId;
      } else {
        final created = await _repo.createExercise(_userId, name);
        id = created.exerciseId;
      }
      state.value = state.value.copyWith(isCreatingEx: false, showCreateEx: false);
      await fetchAll();
      return id;
    } catch (e) {
      state.value = state.value.copyWith(isCreatingEx: false, error: e.toString());
      return null;
    }
  }

  // ── Create variation ───────────────────────────────────────────────────────

  void openCreateVariation() => state.value =
      state.value.copyWith(showCreateVar: true, createVarName: '');
  void closeCreateVariation() =>
      state.value = state.value.copyWith(showCreateVar: false);
  void setCreateVarName(String v) =>
      state.value = state.value.copyWith(createVarName: v);

  Future<String?> submitCreateVariation() async {
    final s = state.value;
    final name = s.createVarName.trim();
    if (name.isEmpty) return null;
    state.value = s.copyWith(isCreatingVar: true);
    try {
      final existing = await _repo.findVariationByName(_userId, name);
      String id;
      if (existing != null) {
        if (existing.isActive) {
          state.value = state.value.copyWith(
              isCreatingVar: false, error: '"$name" already exists.');
          return null;
        }
        await _repo.reactivateVariation(existing.variationId);
        id = existing.variationId;
      } else {
        final created = await _repo.createVariation(_userId, name);
        id = created.variationId;
      }
      state.value = state.value.copyWith(isCreatingVar: false, showCreateVar: false);
      await fetchAll();
      return id;
    } catch (e) {
      state.value = state.value.copyWith(isCreatingVar: false, error: e.toString());
      return null;
    }
  }

  void dispose() => state.dispose();
}
