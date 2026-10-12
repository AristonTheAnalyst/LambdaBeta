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
  ExerciseViewModel({ExerciseRepository? repo, String? userId})
    : _repo = repo ?? ExerciseRepository(),
      _userIdOverride = userId;

  final ExerciseRepository _repo;
  final state = ValueNotifier(const ExerciseState());

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId => _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// Load-once guard: the hub embeds ONE screen instance now (2026-10-13),
  /// so a second fetch on an already-loaded catalog is a no-op. Mutations
  /// patch state in place and never go through this; the reactivate paths,
  /// which genuinely need a re-read, call [_fetchAllFull].
  Future<void> fetchAll() async {
    if (state.value.exercises.isNotEmpty) return;
    await _fetchAllFull();
  }

  Future<void> _fetchAllFull() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.fetchExercises(_userId),
        _repo.fetchVariations(_userId),
      ]);
      final exercises = results[0] as List<CustomExercise>;
      final variations = results[1] as List<CustomVariation>;
      // The detail map is exactly "one detail per exercise" — derived from
      // the list, not a third read (2026-10-13).
      final detailMap = {
        for (final ex in exercises) ex.exerciseId: ExerciseDetail(exercise: ex),
      };
      final usage = await _repo.fetchUsage(
        _userId,
        exercises: exercises,
        variations: variations,
      );
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

  /// The light pop-reload the exercise detail's caller needs: renames and
  /// archives made on the detail page show in the list without a full
  /// catalog + timeline rescan (2026-10-13).
  Future<void> refreshExercisesOnly() async {
    try {
      final exercises = await _repo.fetchExercises(_userId);
      state.value = state.value.copyWith(
        exercises: exercises,
        exerciseDetailMap: {
          for (final ex in exercises) ex.exerciseId: ExerciseDetail(exercise: ex),
        },
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
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
      // Patch in place — a rename must not rescan the catalog and the whole
      // timeline (2026-10-13).
      final renamed = s.editExercise!.copyWith(name: s.editExName.trim());
      state.value = s.copyWith(
        isSaving: false,
        clearEditEx: true,
        exercises: [
          for (final e in s.exercises)
            if (e.exerciseId == renamed.exerciseId) renamed else e,
        ],
        exerciseDetailMap: {
          ...s.exerciseDetailMap,
          renamed.exerciseId: ExerciseDetail(exercise: renamed),
        },
      );
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  /// Deletes a never-used exercise outright; archives a used one so history
  /// keeps it. Screens use [exerciseUsageCount] to pick their dialog copy.
  Future<void> deleteExercise(String exerciseId) async {
    final s = state.value;
    state.value = s.copyWith(clearEditEx: true);
    if (await _repo.exerciseUsageCount(exerciseId) > 0) {
      await _repo.deactivateExercise(exerciseId);
    } else {
      await _repo.hardDeleteExercise(exerciseId);
    }
    // Remove locally — the delete does not rescan the catalog (2026-10-13).
    state.value = state.value.copyWith(
      exercises: [
        for (final e in state.value.exercises)
          if (e.exerciseId != exerciseId) e,
      ],
      exerciseDetailMap: {
        for (final e in state.value.exerciseDetailMap.entries)
          if (e.key != exerciseId) e.key: e.value,
      },
    );
  }

  Future<int> exerciseUsageCount(String exerciseId) =>
      _repo.exerciseUsageCount(exerciseId);

  Future<List<CustomExercise>> fetchArchivedExercises() =>
      _repo.fetchArchivedExercises(_userId);

  Future<void> reactivateExercise(String exerciseId) async {
    await _repo.reactivateExercise(exerciseId);
    // A row is coming back from the archive — the lists must re-read rather
    // than patch (2026-10-13).
    await _fetchAllFull();
  }

  /// Renames an exercise directly (used by the per-exercise detail page,
  /// which doesn't drive the edit-modal state).
  Future<void> renameExercise(String exerciseId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (nameTooLong(trimmed)) return;
    await _repo.updateExercise(exerciseId, trimmed);
    final s = state.value;
    final renamed = s.exercises
        .firstWhere((e) => e.exerciseId == exerciseId)
        .copyWith(name: trimmed);
    state.value = s.copyWith(
      exercises: [
        for (final e in s.exercises)
          if (e.exerciseId == exerciseId) renamed else e,
      ],
      exerciseDetailMap: {
        ...s.exerciseDetailMap,
        exerciseId: ExerciseDetail(exercise: renamed),
      },
    );
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
    state.value = state.value.copyWith(
      variations: [
        for (final v in state.value.variations)
          if (v.variationId != variationId) v,
      ],
    );
  }

  Future<int> variationUsageCount(String variationId) =>
      _repo.variationUsageCount(variationId);

  Future<List<CustomVariation>> fetchArchivedVariations() =>
      _repo.fetchArchivedVariations(_userId);

  Future<void> reactivateVariation(String variationId) async {
    await _repo.reactivateVariation(variationId);
    await _fetchAllFull();
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
      final newEx = existing != null
          // Creating a name that matches an archived exercise restores it —
          // exercises are per-user, and a soft-deleted name must not block
          // re-creation (reactivating an active row is a no-op). The local
          // insert carries the ACTIVE spelling (archived date null).
          ? CustomExercise(
              exerciseId: existing.exerciseId,
              userId: existing.userId,
              name: existing.name,
            )
          : await _repo.createExercise(_userId, name);
      if (existing != null) {
        await _repo.reactivateExercise(existing.exerciseId);
      }
      final s2 = state.value;
      state.value = s2.copyWith(
        isCreatingEx: false,
        showCreateEx: false,
        // Insert locally — a create must not rescan the catalog + timeline
        // (2026-10-13). A fresh row has no usage, so it sorts last either way.
        exercises: [...s2.exercises, newEx],
        exerciseDetailMap: {
          ...s2.exerciseDetailMap,
          newEx.exerciseId: ExerciseDetail(exercise: newEx),
        },
        usage: {...s2.usage, newEx.exerciseId: const ExerciseUsage()},
      );
      return newEx.exerciseId;
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
      final newVar = existing != null
          // Creating a name that matches an archived variation restores it —
          // per-user soft-deletes must not block re-creation. The local
          // insert carries the ACTIVE spelling (archived date null).
          ? CustomVariation(
              variationId: existing.variationId,
              userId: existing.userId,
              name: existing.name,
            )
          : await _repo.createVariation(_userId, name);
      if (existing != null) {
        await _repo.reactivateVariation(existing.variationId);
      }
      final s2 = state.value;
      state.value = s2.copyWith(
        isCreatingVar: false,
        showCreateVar: false,
        // Insert locally — a create must not rescan the catalog + timeline
        // (2026-10-13).
        variations: [...s2.variations, newVar],
      );
      return newVar.variationId;
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
