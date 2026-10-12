import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/logs_viewmodel.dart';

/// The logs list rides the shared timeline cache (2026-10-13): one sessions
/// query per load, the timeline read once for any number of loads, and the
/// PR counts from the cache's sorted copy.
class _FakeSessionRepo extends Fake implements SessionRepository {
  int sessionsReads = 0;

  @override
  Future<List<SessionWithSets>> loadSessionsWithSets(String userId) async {
    sessionsReads++;
    return [
      SessionWithSets(
        session: Session(
          sessionId: 'w1',
          userId: userId,
          createdDatetime: DateTime(2026, 10, 10),
          endDatetime: DateTime(2026, 10, 10, 10),
        ),
        sets: [],
      ),
    ];
  }
}

void main() {
  late _FakeSessionRepo repo;
  late int timelineReads;

  setUp(() {
    repo = _FakeSessionRepo();
    timelineReads = 0;
    PastSetsTimelineCache.loaderOverride = (userId) async {
      timelineReads++;
      return [
        PastSetRow(
          sessionExerciseSetId: 's1',
          sessionExerciseId: 'se1',
          sessionId: 'w1',
          userId: userId,
          exerciseId: 'ex1',
          setNumber: 1,
          reps: const [5],
          sessionCreatedDate: DateTime(2026, 10, 10, 10),
          weight: 100,
        ),
      ];
    };
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('load reads the timeline once and derives the PR counts', () async {
    final vm = LogsViewModel(repo: repo, userId: 'u1');
    await vm.load();

    expect(repo.sessionsReads, 1);
    expect(timelineReads, 1);
    expect(vm.state.value.prCountsBySession['w1']?['ex1'], 1,
        reason: 'the lone 100×5 with no prior history is a first PR');
    vm.dispose();
  });

  test('a second load rides the cache — zero new timeline queries', () async {
    final vm = LogsViewModel(repo: repo, userId: 'u1');
    await vm.load();
    await vm.load();

    expect(repo.sessionsReads, 2, reason: 'the sessions list still re-reads');
    expect(timelineReads, 1,
        reason: 'the timeline is cached — reloads pay nothing');
    vm.dispose();
  });
}
