import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/name_limit.dart';
import '../../../core/utils/sort_compare.dart';
import '../../../data/models/custom_exercise.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/repositories/exercise_repository.dart';

/// What the Exercises and Variations lists order by — a per-run UI choice,
/// not persisted. `lastUsed` is the default because recency is what makes
/// the list useful; a library ordered by creation buries what you train.
enum ExerciseSortCriterion { lastUsed, name, mostUsed }

class ExerciseState {
  const ExerciseState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.exercises = const [],
    this.variations = const [],
    this.exerciseDetailMap = const {},
    this.usage = const {},
    this.activeTab = 0,
    this.exSearch = '',
    this.varSearch = '',
    this.exPage = 0,
    this.varPage = 0,
    this.exSort = ExerciseSortCriterion.lastUsed,
    this.exSortDesc = true,
    this.varSort = ExerciseSortCriterion.lastUsed,
    this.varSortDesc = true,
    // Edit exercise modal
    this.editExercise,
    this.editExName = '',
    // Edit variation modal
    this.editVariation,
    this.editVarName = '',
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
  final Map<String, ExerciseUsage> usage;
  final int activeTab;
  final String exSearch;
  final String varSearch;
  final int exPage;
  final int varPage;

  /// Each list sorts independently — same criteria, own choice.
  final ExerciseSortCriterion exSort;
  final bool exSortDesc;
  final ExerciseSortCriterion varSort;
  final bool varSortDesc;

  final CustomExercise? editExercise;
  final String editExName;

  final CustomVariation? editVariation;
  final String editVarName;

  final String createExName;
  final String createVarName;
  final bool showCreateEx;
  final bool showCreateVar;
  final bool isCreatingEx;
  final bool isCreatingVar;

  static const _pageSize = 10;

  List<CustomExercise> get filteredExercises => exSearch.isEmpty
      ? exercises
      : exercises
            .where((e) => e.name.toLowerCase().contains(exSearch.toLowerCase()))
            .toList();

  List<CustomVariation> get filteredVariations => varSearch.isEmpty
      ? variations
      : variations
            .where(
              (v) => v.name.toLowerCase().contains(varSearch.toLowerCase()),
            )
            .toList();

  /// The exercises in view, sorted by the current criterion and direction,
  /// with name as the tiebreak (two equal dates must still read A–Z).
  List<CustomExercise> get sortedExercises {
    final dir = exSortDesc ? -1 : 1;
    final sorted = [...filteredExercises]
      ..sort((a, b) {
        final byCriterion = switch (exSort) {
          ExerciseSortCriterion.lastUsed => compareNullable(
            usage[a.exerciseId]?.lastUsed,
            usage[b.exerciseId]?.lastUsed,
            dir,
          ),
          ExerciseSortCriterion.name =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()) * dir,
          ExerciseSortCriterion.mostUsed =>
            ((usage[a.exerciseId]?.sets ?? 0) -
                    (usage[b.exerciseId]?.sets ?? 0)) *
                dir,
        };
        return byCriterion != 0
            ? byCriterion
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return sorted;
  }

  List<CustomVariation> get sortedVariations {
    final dir = varSortDesc ? -1 : 1;
    final sorted = [...filteredVariations]
      ..sort((a, b) {
        final byCriterion = switch (varSort) {
          ExerciseSortCriterion.lastUsed => compareNullable(
            usage[a.variationId]?.lastUsed,
            usage[b.variationId]?.lastUsed,
            dir,
          ),
          ExerciseSortCriterion.name =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()) * dir,
          ExerciseSortCriterion.mostUsed =>
            ((usage[a.variationId]?.sets ?? 0) -
                    (usage[b.variationId]?.sets ?? 0)) *
                dir,
        };
        return byCriterion != 0
            ? byCriterion
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return sorted;
  }

  List<CustomExercise> get pagedExercises {
    final start = (exPage * _pageSize).clamp(0, sortedExercises.length);
    final end = ((exPage + 1) * _pageSize).clamp(0, sortedExercises.length);
    return sortedExercises.sublist(start, end);
  }

  List<CustomVariation> get pagedVariations {
    final start = (varPage * _pageSize).clamp(0, sortedVariations.length);
    final end = ((varPage + 1) * _pageSize).clamp(0, sortedVariations.length);
    return sortedVariations.sublist(start, end);
  }

  bool get canPrevEx => exPage > 0;
  bool get canNextEx => (exPage + 1) * _pageSize < sortedExercises.length;
  bool get canPrevVar => varPage > 0;
  bool get canNextVar => (varPage + 1) * _pageSize < sortedVariations.length;

  int get exTotal => sortedExercises.length;
  int get varTotal => sortedVariations.length;

  ExerciseState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    List<CustomExercise>? exercises,
    List<CustomVariation>? variations,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    Map<String, ExerciseUsage>? usage,
    int? activeTab,
    String? exSearch,
    String? varSearch,
    int? exPage,
    int? varPage,
    ExerciseSortCriterion? exSort,
    bool? exSortDesc,
    ExerciseSortCriterion? varSort,
    bool? varSortDesc,
    CustomExercise? editExercise,
    bool clearEditEx = false,
    String? editExName,
    CustomVariation? editVariation,
    bool clearEditVar = false,
    String? editVarName,
    String? createExName,
    String? createVarName,
    bool? showCreateEx,
    bool? showCreateVar,
    bool? isCreatingEx,
    bool? isCreatingVar,
  }) => ExerciseState(
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : error ?? this.error,
    exercises: exercises ?? this.exercises,
    variations: variations ?? this.variations,
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    usage: usage ?? this.usage,
    activeTab: activeTab ?? this.activeTab,
    exSearch: exSearch ?? this.exSearch,
    varSearch: varSearch ?? this.varSearch,
    exPage: exPage ?? this.exPage,
    varPage: varPage ?? this.varPage,
    exSort: exSort ?? this.exSort,
    exSortDesc: exSortDesc ?? this.exSortDesc,
    varSort: varSort ?? this.varSort,
    varSortDesc: varSortDesc ?? this.varSortDesc,
    editExercise: clearEditEx ? null : (editExercise ?? this.editExercise),
    editExName: clearEditEx ? '' : (editExName ?? this.editExName),
    editVariation: clearEditVar ? null : (editVariation ?? this.editVariation),
    editVarName: clearEditVar ? '' : (editVarName ?? this.editVarName),
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
      final exercises = await _repo.fetchExercises(_userId);
      final variations = await _repo.fetchVariations(_userId);
      final detailMap = await _repo.fetchExerciseDetailMap(_userId);
      final usage = await _repo.fetchUsage(_userId);
      state.value = state.value.copyWith(
        isLoading: false,
        exercises: exercises,
        variations: variations,
        exerciseDetailMap: detailMap,
        usage: usage,
      );
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setTab(int i) =>
      state.value = state.value.copyWith(activeTab: i, exPage: 0, varPage: 0);
  void setExSearch(String q) =>
      state.value = state.value.copyWith(exSearch: q, exPage: 0);
  void setVarSearch(String q) =>
      state.value = state.value.copyWith(varSearch: q, varPage: 0);

  /// Change a list's ordering; the page resets because page 3 of one
  /// ordering is not page 3 of another.
  void setExSort(ExerciseSortCriterion c, bool descending) =>
      state.value =
          state.value.copyWith(exSort: c, exSortDesc: descending, exPage: 0);
  void setVarSort(ExerciseSortCriterion c, bool descending) =>
      state.value =
          state.value.copyWith(varSort: c, varSortDesc: descending, varPage: 0);

  void nextExPage() =>
      state.value = state.value.copyWith(exPage: state.value.exPage + 1);
  void prevExPage() =>
      state.value = state.value.copyWith(exPage: state.value.exPage - 1);
  void nextVarPage() =>
      state.value = state.value.copyWith(varPage: state.value.varPage + 1);
  void prevVarPage() =>
      state.value = state.value.copyWith(varPage: state.value.varPage - 1);

  // ── Open edit exercise ─────────────────────────────────────────────────────

  Future<void> openEditExercise(CustomExercise ex) async {
    state.value = state.value.copyWith(
      editExercise: ex,
      editExName: ex.name,
      clearError: true,
    );
  }

  void closeEditExercise() =>
      state.value = state.value.copyWith(clearEditEx: true);

  void setEditExName(String v) =>
      state.value = state.value.copyWith(editExName: v);

  Future<void> saveEditExercise() async {
    final s = state.value;
    if (s.editExercise == null || s.editExName.trim().isEmpty) return;
    if (nameTooLong(s.editExName)) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateExercise(
        s.editExercise!.exerciseId,
        s.editExName.trim(),
      );

      state.value = state.value.copyWith(isSaving: false, clearEditEx: true);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  /// Deletes a never-used exercise outright; archives a used one so history
  /// keeps it. Screens use [exerciseUsageCount] to pick their dialog copy.
  Future<void> deleteExercise(String exerciseId) async {
    state.value = state.value.copyWith(clearEditEx: true);
    if (await _repo.exerciseUsageCount(exerciseId) > 0) {
      await _repo.deactivateExercise(exerciseId);
    } else {
      await _repo.hardDeleteExercise(exerciseId);
    }
    await fetchAll();
  }

  Future<int> exerciseUsageCount(String exerciseId) =>
      _repo.exerciseUsageCount(exerciseId);

  Future<List<CustomExercise>> fetchArchivedExercises() =>
      _repo.fetchArchivedExercises(_userId);

  Future<void> reactivateExercise(String exerciseId) async {
    await _repo.reactivateExercise(exerciseId);
    await fetchAll();
  }

  /// Renames an exercise directly (used by the per-exercise detail page,
  /// which doesn't drive the edit-modal state).
  Future<void> renameExercise(String exerciseId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (nameTooLong(trimmed)) return;
    await _repo.updateExercise(exerciseId, trimmed);
    await fetchAll();
  }

  // ── Open edit variation ────────────────────────────────────────────────────

  Future<void> openEditVariation(CustomVariation v) async {
    // Variations are a flat library since schema v2 (no exercise assignment) —
    // editing is name-only.
    state.value = state.value.copyWith(
      editVariation: v,
      editVarName: v.name,
      clearError: true,
    );
  }

  void closeEditVariation() =>
      state.value = state.value.copyWith(clearEditVar: true);

  void setEditVarName(String v) =>
      state.value = state.value.copyWith(editVarName: v);

  Future<void> saveEditVariation() async {
    final s = state.value;
    if (s.editVariation == null || s.editVarName.trim().isEmpty) return;
    if (nameTooLong(s.editVarName)) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateVariation(
        s.editVariation!.variationId,
        s.editVarName.trim(),
      );

      state.value = state.value.copyWith(isSaving: false, clearEditVar: true);
      await fetchAll();
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  /// Deletes a never-used variation outright; archives a used one so history
  /// keeps it. Screens use [variationUsageCount] to pick their dialog copy.
  Future<void> deleteVariation(String variationId) async {
    state.value = state.value.copyWith(clearEditVar: true);
    if (await _repo.variationUsageCount(variationId) > 0) {
      await _repo.deactivateVariation(variationId);
    } else {
      await _repo.hardDeleteVariation(variationId);
    }
    await fetchAll();
  }

  Future<int> variationUsageCount(String variationId) =>
      _repo.variationUsageCount(variationId);

  Future<List<CustomVariation>> fetchArchivedVariations() =>
      _repo.fetchArchivedVariations(_userId);

  Future<void> reactivateVariation(String variationId) async {
    await _repo.reactivateVariation(variationId);
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
    if (nameTooLong(name)) return null;
    state.value = s.copyWith(isCreatingEx: true);
    try {
      final existing = await _repo.findExerciseByName(_userId, name);
      String id;
      if (existing != null) {
        // Creating a name that matches an archived exercise restores it —
        // exercises are per-user, and a soft-deleted name must not block
        // re-creation (reactivating an active row is a no-op).
        await _repo.reactivateExercise(existing.exerciseId);
        id = existing.exerciseId;
      } else {
        final created = await _repo.createExercise(_userId, name);
        id = created.exerciseId;
      }
      state.value = state.value.copyWith(
        isCreatingEx: false,
        showCreateEx: false,
      );
      await fetchAll();
      return id;
    } catch (e) {
      state.value = state.value.copyWith(
        isCreatingEx: false,
        error: e.toString(),
      );
      return null;
    }
  }

  // ── Create variation ───────────────────────────────────────────────────────

  void openCreateVariation() => state.value = state.value.copyWith(
    showCreateVar: true,
    createVarName: '',
  );
  void closeCreateVariation() =>
      state.value = state.value.copyWith(showCreateVar: false);
  void setCreateVarName(String v) =>
      state.value = state.value.copyWith(createVarName: v);

  Future<String?> submitCreateVariation() async {
    final s = state.value;
    final name = s.createVarName.trim();
    if (name.isEmpty) return null;
    if (nameTooLong(name)) return null;
    state.value = s.copyWith(isCreatingVar: true);
    try {
      final existing = await _repo.findVariationByName(_userId, name);
      String id;
      if (existing != null) {
        // Creating a name that matches an archived variation restores it —
        // per-user soft-deletes must not block re-creation.
        await _repo.reactivateVariation(existing.variationId);
        id = existing.variationId;
      } else {
        final created = await _repo.createVariation(_userId, name);
        id = created.variationId;
      }
      state.value = state.value.copyWith(
        isCreatingVar: false,
        showCreateVar: false,
      );
      await fetchAll();
      return id;
    } catch (e) {
      state.value = state.value.copyWith(
        isCreatingVar: false,
        error: e.toString(),
      );
      return null;
    }
  }

  void dispose() => state.dispose();
}
