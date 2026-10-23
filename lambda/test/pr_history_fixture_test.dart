import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/dev/pr_history_fixture.dart';

/// The demo's fake world is derived by the production engine, so these tests
/// pin two things at once: the hard-coded timeline and the history reading
/// the sheet draws from it.
void main() {
  group('PR History fixture', () {
    test('the feeds are the sizes the demo promises', () {
      expect(demoPrsFor('demo-bench').length, 12);
      expect(demoPrsFor('demo-incline').length, 5);
      expect(demoPrsFor('demo-fly').length, 3);
    });

    test('every event names its exercise and source set', () {
      for (final exercise in kDemoExercises) {
        for (final event in demoPrsFor(exercise.id)) {
          expect(event.exerciseId, exercise.id);
          expect(event.sessionExerciseSetId, isNotNull);
        }
      }
    });

    test('the fake session holds exactly five PR sets', () {
      expect(kDemoSessionPrCount, 5);
      expect(kDemoSessionPrSetIds, {
        'bench-8',
        'bench-9',
        'inc-4',
        'inc-5',
        'fly-3',
      });
      // The back-off set is dominated by the rep PR before it.
      expect(kDemoSessionPrSetIds, isNot(contains('bench-10')));
    });

    test('the oldest bench PR had nothing to beat', () {
      final first = demoPrsFor('demo-bench').first;
      expect(first.sessionExerciseSetId, 'bench-1');
      expect(first.beforeWeight, isNull);
      expect(first.beforeReps, isNull);
    });

    test('one set can beat both frontiers at once', () {
      final dual = demoPrsFor(
        'demo-bench',
      ).firstWhere((event) => event.sessionExerciseSetId == 'bench-4');
      // 70 × 8 beat 65 × 8 (the best weight at 8+ reps) and 70 × 5 (the
      // best reps at exactly 70kg) — one PR, two victims.
      expect(dual.weight, 70);
      expect(dual.reps, 8);
      expect(dual.beforeWeight, 65);
      expect(dual.beforeReps, 5);
    });

    test('the newest bench PR is the set that beat the rep record', () {
      final bench = demoPrsFor('demo-bench');
      expect(bench[bench.length - 2].sessionExerciseSetId, 'bench-8');
      expect(bench.last.sessionExerciseSetId, 'bench-9');
      final newest = bench.last;
      expect(newest.weight, 100);
      expect(newest.reps, 12);
      // A first at 12+ reps; the record it took was reps at exactly 100kg.
      expect(newest.beforeWeight, isNull);
      expect(newest.beforeReps, 10);
    });

    test('paused sets never touch the regular frontier', () {
      final paused = demoPrsFor(
        'demo-bench',
      ).where((event) => event.variationId == kDemoPausedVariationId).toList();
      expect(paused.length, 3);
      // The first paused set is first on both dimensions even though the
      // regular line was already at 90 × 3 — variation is part of the scope.
      expect(paused.first.sessionExerciseSetId, 'bench-p1');
      expect(paused.first.beforeWeight, isNull);
      expect(paused.first.beforeReps, isNull);
    });

    test('each variation line draws its own FIRST PR', () {
      // The sheet renders one FIRST PR per line that starts empty — the
      // regular bench line and its paused variation.
      final firsts = demoPrsFor('demo-bench')
          .where(
            (event) => event.beforeWeight == null && event.beforeReps == null,
          )
          .map((event) => event.sessionExerciseSetId)
          .toList();
      expect(firsts, ['bench-1', 'bench-p1']);
    });

    test('the stage rows are today\'s sets, in grid order', () {
      expect(
        [
          for (final set in demoSessionRows('demo-bench'))
            set.sessionExerciseSetId,
        ],
        ['bench-8', 'bench-9', 'bench-10'],
      );
      expect(
        [
          for (final set in demoSessionRows('demo-incline'))
            set.sessionExerciseSetId,
        ],
        ['inc-4', 'inc-5'],
      );
      expect(
        [
          for (final set in demoSessionRows('demo-fly'))
            set.sessionExerciseSetId,
        ],
        ['fly-3'],
      );
    });
  });
}
