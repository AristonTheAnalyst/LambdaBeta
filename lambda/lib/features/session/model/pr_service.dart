import '../../../data/repositories/session_repository.dart';
import 'pr_engine.dart';

/// Derives PRs on demand from the full set history — the single source of
/// truth is `fact_session_set`; nothing is persisted or kept in sync.
///
/// The derivation is a pure function of the sets, so it is correct by
/// construction: editing or deleting a set changes every PR view on the next
/// read. A heavy user's timeline (~15k sets over 3 years) derives in ~10ms,
/// and results are memoized until [invalidate] is called (any set write), so
/// repeat reads are free.
class PrService {
  PrService({SessionRepository? sessionRepo})
      : _sessionRepo = sessionRepo ?? SessionRepository();

  final SessionRepository _sessionRepo;

  List<PrRecord>? _cachedTimeline;
  bool _cacheDirty = true;

  /// Call after ANY set write (log, edit, duplicate, delete) so the next
  /// read re-derives. Cheap — the derivation itself is only ~10ms.
  void invalidate() {
    _cacheDirty = true;
    _cachedTimeline = null;
  }

  /// The full PR timeline derived from current history. Memoized until the
  /// next invalidation.
  Future<List<PrRecord>> timeline(String userId) async {
    final cached = _cachedTimeline;
    if (!_cacheDirty && cached != null) return cached;
    final sets = await _sessionRepo.loadPastSetsTimeline(userId);
    final derived = fullPrTimeline(sets);
    _cachedTimeline = derived;
    _cacheDirty = false;
    return derived;
  }

  /// PRs achieved during one session.
  Future<List<PrRecord>> forSession(String userId, String sessionId) async {
    final all = await timeline(userId);
    return all.where((p) => p.sessionId == sessionId).toList();
  }

  /// All PRs for one exercise.
  Future<List<PrRecord>> forExercise(String userId, String exerciseId) async {
    final all = await timeline(userId);
    return all.where((p) => p.exerciseId == exerciseId).toList();
  }

  /// PRs whose source sets are in [setIds].
  Future<List<PrRecord>> forSets(String userId, List<String> setIds) async {
    final all = await timeline(userId);
    return all.where((p) => p.setId != null && setIds.contains(p.setId)).toList();
  }

  Future<int> count(String userId) async => (await timeline(userId)).length;
}
