import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_set.dart';
import '../../../data/repositories/session_repository.dart';

class LogsState {
  const LogsState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.sessions = const [],
    this.pastSets = const [],
    this.activeTab = 0,
  });

  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final List<SessionWithSets> sessions;
  final List<PastSetRow> pastSets;
  final int activeTab;

  LogsState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    List<SessionWithSets>? sessions,
    List<PastSetRow>? pastSets,
    int? activeTab,
  }) =>
      LogsState(
        isLoading: isLoading ?? this.isLoading,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: clearError ? null : error ?? this.error,
        sessions: sessions ?? this.sessions,
        pastSets: pastSets ?? this.pastSets,
        activeTab: activeTab ?? this.activeTab,
      );
}

class LogsViewModel {
  LogsViewModel({SessionRepository? repo})
      : _repo = repo ?? SessionRepository();

  final SessionRepository _repo;
  final state = ValueNotifier(const LogsState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.loadSessionsWithSets(_userId),
        _repo.loadPastSetsTimeline(_userId),
      ]);
      state.value = state.value.copyWith(
        isLoading: false,
        sessions: results[0] as List<SessionWithSets>,
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
        _repo.loadSessionsWithSets(_userId),
        _repo.loadPastSetsTimeline(_userId),
      ]);
      state.value = state.value.copyWith(
        isRefreshing: false,
        sessions: results[0] as List<SessionWithSets>,
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
