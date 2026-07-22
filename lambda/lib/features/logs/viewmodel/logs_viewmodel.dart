import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/workout.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/workout_repository.dart';

class LogsState {
  const LogsState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.workouts = const [],
    this.pastSets = const [],
    this.activeTab = 0,
  });

  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final List<WorkoutWithSets> workouts;
  final List<PastSetRow> pastSets;
  final int activeTab;

  LogsState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    List<WorkoutWithSets>? workouts,
    List<PastSetRow>? pastSets,
    int? activeTab,
  }) =>
      LogsState(
        isLoading: isLoading ?? this.isLoading,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: clearError ? null : error ?? this.error,
        workouts: workouts ?? this.workouts,
        pastSets: pastSets ?? this.pastSets,
        activeTab: activeTab ?? this.activeTab,
      );
}

class LogsViewModel {
  LogsViewModel({WorkoutRepository? repo})
      : _repo = repo ?? WorkoutRepository();

  final WorkoutRepository _repo;
  final state = ValueNotifier(const LogsState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.loadWorkoutsWithSets(_userId),
        _repo.loadPastSetsTimeline(_userId),
      ]);
      state.value = state.value.copyWith(
        isLoading: false,
        workouts: results[0] as List<WorkoutWithSets>,
        pastSets: results[1] as List<PastSetRow>,
      );
    } catch (e) {
      state.value =
          state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    state.value = state.value.copyWith(isRefreshing: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.loadWorkoutsWithSets(_userId),
        _repo.loadPastSetsTimeline(_userId),
      ]);
      state.value = state.value.copyWith(
        isRefreshing: false,
        workouts: results[0] as List<WorkoutWithSets>,
        pastSets: results[1] as List<PastSetRow>,
      );
    } catch (e) {
      state.value =
          state.value.copyWith(isRefreshing: false, error: e.toString());
    }
  }

  void setTab(int i) => state.value = state.value.copyWith(activeTab: i);

  void dispose() => state.dispose();
}
