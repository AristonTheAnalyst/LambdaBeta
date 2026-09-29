import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/session_repository.dart';
import '../../session/model/pr_engine.dart';

class LogsState {
  const LogsState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.sessions = const [],
    this.pastSets = const [],
    this.prCountsBySession = const {},
    this.activeTab = 0,
  });

  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final List<SessionWithSets> sessions;
  final List<PastSetRow> pastSets;

  /// sessionId → exerciseId → PR count, one `prEvents` walk per load (a
  /// set is a PR relative to all prior history, so counts must come from
  /// the global walk, never per-session sets). Feeds the session cards'
  /// trophy badges.
  final Map<String, Map<String, int>> prCountsBySession;

  final int activeTab;

  LogsState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    List<SessionWithSets>? sessions,
    List<PastSetRow>? pastSets,
    Map<String, Map<String, int>>? prCountsBySession,
    int? activeTab,
  }) =>
      LogsState(
        isLoading: isLoading ?? this.isLoading,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: clearError ? null : error ?? this.error,
        sessions: sessions ?? this.sessions,
        pastSets: pastSets ?? this.pastSets,
        prCountsBySession: prCountsBySession ?? this.prCountsBySession,
        activeTab: activeTab ?? this.activeTab,
      );
}

class LogsViewModel {
  LogsViewModel({SessionRepository? repo})
      : _repo = repo ?? SessionRepository();

  final SessionRepository _repo;
  final state = ValueNotifier(const LogsState());
  bool _disposed = false;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  /// sessionId → exerciseId → PR count from one global `prEvents` walk.
  static Map<String, Map<String, int>> _prCountsBySession(
    List<PastSetRow> pastSets,
  ) {
    final out = <String, Map<String, int>>{};
    for (final e in prEvents(pastSets)) {
      final byExercise = out.putIfAbsent(e.sessionId, () => {});
      byExercise[e.exerciseId] = (byExercise[e.exerciseId] ?? 0) + 1;
    }
    return out;
  }

  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.loadSessionsWithSets(_userId),
        _repo.loadPastSetsTimeline(_userId),
      ]);
      if (_disposed) return;
      final pastSets = results[1] as List<PastSetRow>;
      state.value = state.value.copyWith(
        isLoading: false,
        sessions: results[0] as List<SessionWithSets>,
        pastSets: pastSets,
        prCountsBySession: _prCountsBySession(pastSets),
      );
    } catch (e) {
      if (_disposed) return;
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
      if (_disposed) return;
      final pastSets = results[1] as List<PastSetRow>;
      state.value = state.value.copyWith(
        isRefreshing: false,
        sessions: results[0] as List<SessionWithSets>,
        pastSets: pastSets,
        prCountsBySession: _prCountsBySession(pastSets),
      );
    } catch (e) {
      if (_disposed) return;
      state.value =
          state.value.copyWith(isRefreshing: false, error: e.toString());
    }
  }

  /// Hard-deletes a session with its exercise + set rows, then rebuilds the
  /// list. Reloads via [refresh] rather than [load] so the panel doesn't
  /// flash its loading spinner over a list the user is still reading. A
  /// failed delete leaves the list untouched and records the error.
  Future<void> deleteSession(String sessionId) async {
    try {
      await _repo.deleteSession(sessionId);
    } catch (e) {
      if (_disposed) return;
      state.value = state.value.copyWith(error: e.toString());
      return;
    }
    if (_disposed) return;
    await refresh();
  }

  void setTab(int i) {
    if (_disposed) return;
    state.value = state.value.copyWith(activeTab: i);
  }

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
