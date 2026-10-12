import 'package:flutter/foundation.dart';

import '../models/session_exercise_set.dart';
import '../repositories/session_repository.dart';

/// One shared cache for the past-sets timeline (2026-10-13).
///
/// The timeline is the app's most-read and most-expensive query — every user
/// set ever logged, joined and hydrated — and screens re-ran it per open and
/// per edit. This memoizes it per user and hands out an oldest-first copy
/// for the PR engine's sorted walk, so a screen that just needs the numbers
/// pays nothing after the first read.
///
/// Freshness contract: every fact write in [SessionRepository] invalidates
/// (the repo is the single funnel — see the write methods there), the dev
/// sample-data seeder does too, the Flow Lab's database swap clears the
/// cache wholesale (a sandbox must never serve real rows or vice versa), and
/// `openDatabase` subscribes to the sync status stream so a remote download
/// invalidates once per sync round. Reads between a remote write and its
/// download are therefore as stale as any pull-based screen always was.
class PastSetsTimelineCache {
  PastSetsTimelineCache._();
  static final PastSetsTimelineCache instance = PastSetsTimelineCache._();

  final Map<String, Future<List<PastSetRow>>> _byUser = {};
  final Map<String, List<PastSetRow>> _ascByUser = {};

  /// How many times the cache has been invalidated — the guard that a new
  /// fact-writing path cannot forget to call [invalidate] (tests count it).
  int invalidations = 0;

  /// Host-test seam: when set, [get] reads through this loader instead of
  /// constructing a real [SessionRepository] (which would touch the
  /// PowerSync database). Cleared in test teardown.
  @visibleForTesting
  static Future<List<PastSetRow>> Function(String userId)? loaderOverride;

  /// The user's timeline (completed sessions, newest first), memoized until
  /// invalidated. The first read after an invalidation re-queries.
  Future<List<PastSetRow>> get(String userId) {
    return _byUser.putIfAbsent(
      userId,
      () => (loaderOverride ??
              (u) => SessionRepository().loadPastSetsTimeline(u))(
        userId,
      ).then((rows) {
        _ascByUser[userId] = [...rows]..sort((a, b) {
          final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
          return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
        });
        return rows;
      }),
    );
  }

  /// The same timeline oldest-first — the PR engine's walk order, sorted
  /// once at load instead of per derivation. Returns null before the first
  /// [get] completes.
  List<PastSetRow>? asc(String userId) => _ascByUser[userId];

  /// Drops the memoized timeline for [userId] — the next [get] re-reads.
  void invalidate([String? userId]) {
    if (userId == null) {
      _byUser.clear();
      _ascByUser.clear();
    } else {
      _byUser.remove(userId);
      _ascByUser.remove(userId);
    }
    invalidations++;
  }
}
