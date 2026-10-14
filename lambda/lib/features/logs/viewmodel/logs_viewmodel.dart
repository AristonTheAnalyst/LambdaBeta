import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/cache/past_sets_timeline_cache.dart';
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
  LogsViewModel({SessionRepository? repo, String? userId})
    : _repo = repo ?? SessionRepository(),
      _userIdOverride = userId;

  final SessionRepository _repo;
  final state = ValueNotifier(const LogsState());
  bool _disposed = false;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId => _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// sessionId → exerciseId → PR count from one global walk over the
  /// load-time-sorted timeline — the cache's asc copy, so the walk never
  /// re-sorts (2026-10-13).
  static Map<String, Map<String, int>> _prCountsBySession(
    List<PastSetRow> pastSetsAsc,
  ) {
    final out = <String, Map<String, int>>{};
    for (final e in prEventsSorted(pastSetsAsc)) {
      final byExercise = out.putIfAbsent(e.sessionId, () => {});
      byExercise[e.exerciseId] = (byExercise[e.exerciseId] ?? 0) + 1;
    }
    return out;
  }

  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      // The timeline comes from the shared cache — the first reader pays
      // the query; every later one (this list, session detail, library,
      // exercise detail) rides it until a write or sync round invalidates
      // (2026-10-13).
      final userId = _userId;
      final results = await Future.wait([
        _repo.loadSessionsWithSets(userId),
        PastSetsTimelineCache.instance.get(userId),
      ]);
      if (_disposed) return;
      final pastSets = results[1] as List<PastSetRow>;
      final asc = PastSetsTimelineCache.instance.asc(userId) ?? pastSets;
      state.value = state.value.copyWith(
        isLoading: false,
        sessions: results[0] as List<SessionWithSets>,
        pastSets: pastSets,
        prCountsBySession: _prCountsBySession(asc),
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
      final userId = _userId;
      final results = await Future.wait([
        _repo.loadSessionsWithSets(userId),
        PastSetsTimelineCache.instance.get(userId),
      ]);
      if (_disposed) return;
      final pastSets = results[1] as List<PastSetRow>;
      final asc = PastSetsTimelineCache.instance.asc(userId) ?? pastSets;
      state.value = state.value.copyWith(
        isRefreshing: false,
        sessions: results[0] as List<SessionWithSets>,
        pastSets: pastSets,
        prCountsBySession: _prCountsBySession(asc),
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
