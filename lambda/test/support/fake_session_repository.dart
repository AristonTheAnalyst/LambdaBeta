import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/session_repository.dart';

/// The one session read the goals surfaces make, and nothing else.
///
/// `SessionRepository` is a wide surface — every live-session write lives on
/// it — and the goals screen and its sheet touch exactly one thing on it: the
/// past-sets timeline the lifetime outcomes and the sheet's axes derive from.
/// Everything else throws through `noSuchMethod`, which is the point: a goals
/// surface that started writing sessions would be a mistake worth failing on.
class FakeSessionRepository implements SessionRepository {
  /// What [loadPastSetsTimeline] answers with — the user's whole history.
  List<PastSetRow> timeline = const [];

  /// Set to make the read throw: the sheet's "couldn't read your history"
  /// path, which must never be rendered as an empty timeline.
  bool failTimeline = false;

  /// How many times the timeline was read — a sheet opened once reads once,
  /// and a sheet that read per build would show up here.
  int timelineReads = 0;

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async {
    timelineReads++;
    if (failTimeline) throw StateError('timeline read failed');
    return timeline;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
