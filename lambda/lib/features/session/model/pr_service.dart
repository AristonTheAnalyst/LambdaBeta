import '../../../data/repositories/session_repository.dart';
import 'pr_engine.dart';

/// Derives PR events on demand from the full set history — the single
/// source of truth is `fact_session_exercise_set` (joined through
/// fact_session_exercise); nothing is persisted or kept in sync.
///
/// The derivation is a pure function of the sets, so it is correct by
/// construction: editing or deleting a set changes every PR view on the
/// next read. A heavy user's timeline (~15k sets over 3 years) derives in
/// ~10ms, and results are memoized until [invalidate] is called (any set
/// write), so repeat reads are free.
class PrService {
  PrService({SessionRepository? sessionRepo})
      : _sessionRepo = sessionRepo ?? SessionRepository();

  final SessionRepository _sessionRepo;

  List<PrEvent>? _cachedEvents;
  bool _cacheDirty = true;

  /// Call after ANY set write (log, edit, duplicate, delete) so the next
  /// read re-derives. Cheap — the derivation itself is only ~10ms.
  void invalidate() {
    _cacheDirty = true;
    _cachedEvents = null;
  }

  /// Every PR event, oldest first — one per set that extended its pair's
  /// best-ever frontier. Memoized until the next invalidation.
  Future<List<PrEvent>> timeline(String userId) async {
    final cached = _cachedEvents;
    if (!_cacheDirty && cached != null) return cached;
    final sets = await _sessionRepo.loadPastSetsTimeline(userId);
    final derived = prEvents(sets);
    _cachedEvents = derived;
    _cacheDirty = false;
    return derived;
  }

  /// PR events achieved during one session.
  Future<List<PrEvent>> forSession(String userId, String sessionId) async {
    final all = await timeline(userId);
    return all.where((e) => e.sessionId == sessionId).toList();
  }

  /// All PR events for one exercise.
  Future<List<PrEvent>> forExercise(String userId, String exerciseId) async {
    final all = await timeline(userId);
    return all.where((e) => e.exerciseId == exerciseId).toList();
  }

  /// PR events whose source sets are in [setIds].
  Future<List<PrEvent>> forSets(String userId, List<String> setIds) async {
    final all = await timeline(userId);
    return all.where((e) => e.sessionExerciseSetId != null && setIds.contains(e.sessionExerciseSetId)).toList();
  }

  /// The achievement count — one per PR event.
  Future<int> count(String userId) async =>
      (await timeline(userId)).length;
}
