import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/session/model/pr_engine.dart';

PastSetRow _set(
  String id, {
  required String exerciseId,
  String? variationId,
  required double weight,
  required int reps,
  DateTime? date,
  int setNumber = 1,
  String sessionId = 'w1',
}) =>
    PastSetRow(
      sessionExerciseSetId: id,
      sessionExerciseId: id,
      sessionId: sessionId,
      userId: 'u1',
      exerciseId: exerciseId,
      setNumber: setNumber,
      reps: [reps],
      sessionCreatedDate: date ?? DateTime(2024, 1, 1),
      variationId: variationId,
      weight: weight,
    );

void main() {
  group('frontier semantics', () {
    test('a set is a PR iff no prior set did ≥ these reps at ≥ this weight', () {
      // 110x1 does not dominate 100x5 (1 < 5) — lighter weight, more reps
      // is still new territory.
      final lighter = prEvents([
        _set('s1', exerciseId: 'bench', weight: 110, reps: 1),
        _set('s2', exerciseId: 'bench', weight: 100, reps: 5),
      ]);
      expect(lighter.length, 2);
      expect(lighter.last.weight, 100);

      // 100x5 dominates 100x4 — same weight, fewer reps is not a PR.
      final fewer = prEvents([
        _set('s1', exerciseId: 'bench', weight: 100, reps: 5),
        _set('s2', exerciseId: 'bench', weight: 100, reps: 4),
      ]);
      expect(fewer.length, 1);
      expect(fewer.single.weight, 100);
      expect(fewer.single.reps, 5);
    });

    test('one PR can beat two previous PRs — both befores survive', () {
      // 6x10, then 100x3 — two frontier points. 100x10 dominates BOTH:
      // beforeWeight 6 (best at ≥10 reps) and beforeReps 3 (best at 100kg).
      final events = prEvents([
        _set('s1', exerciseId: 'ex', weight: 6, reps: 10,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'ex', weight: 100, reps: 3,
            date: DateTime(2024, 1, 2)),
        _set('s3', exerciseId: 'ex', weight: 100, reps: 10,
            date: DateTime(2024, 1, 3)),
      ]);
      expect(events.length, 3);
      final third = events[2];
      expect(third.weight, 100);
      expect(third.reps, 10);
      expect(third.beforeWeight, 6);
      expect(third.beforeReps, 3);
    });

    test('an identical repeat is not a PR', () {
      final events = prEvents([
        _set('s1', exerciseId: 'bench', weight: 100, reps: 5),
        _set('s2', exerciseId: 'bench', weight: 100, reps: 5,
            date: DateTime(2024, 1, 2)),
      ]);
      expect(events.length, 1);
    });

    test('a dominated set still feeds later before-values', () {
      // 90x6 after 100x6 is NOT a PR, but a later 90x8 must report
      // "was 90 x 6", never a first.
      final events = prEvents([
        _set('s1', exerciseId: 'bench', weight: 100, reps: 6),
        _set('s2', exerciseId: 'bench', weight: 90, reps: 6,
            date: DateTime(2024, 1, 2)),
        _set('s3', exerciseId: 'bench', weight: 90, reps: 8,
            date: DateTime(2024, 1, 3)),
      ]);
      expect(events.length, 2);
      expect(events.last.beforeReps, 6);
    });
  });

  group('variation scoping', () {
    test('Pause Bench PR does not affect regular Bench', () {
      final events = prEvents([
        _set('s1',
            exerciseId: 'bench', variationId: 'pause', weight: 100, reps: 5),
        _set('s2', exerciseId: 'bench', weight: 60, reps: 5),
      ]);

      final pause = events.singleWhere((e) => e.variationId == 'pause');
      expect(pause.weight, 100);
      expect(pause.beforeWeight, isNull);

      // Regular Bench gets its OWN frontier — it must not see the
      // pause-bench 100kg.
      final regular = events.singleWhere((e) => e.variationId == null);
      expect(regular.weight, 60);
      expect(regular.beforeWeight, isNull);
    });

    test('null variation is a distinct key from a named variation', () {
      final events = prEvents([
        _set('s1', exerciseId: 'squat', weight: 100, reps: 5),
        _set('s2',
            exerciseId: 'squat', variationId: 'paused', weight: 120, reps: 5),
      ]);
      // Both curves get their own frontier — neither cancels the other.
      expect(events.length, 2);
      expect(
        events.singleWhere((e) => e.variationId == null).weight,
        100,
      );
      expect(
        events.singleWhere((e) => e.variationId == 'paused').weight,
        120,
      );
    });
  });

  group('bodyweight', () {
    test('bodyweight is weight 0; weighted lifts chain past it', () {
      // 10 bodyweight reps, then 5kg x 5 — two frontier extensions.
      final events = prEvents([
        _set('s1', exerciseId: 'pushup', weight: 0, reps: 10,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'pushup', weight: 5, reps: 5,
            date: DateTime(2024, 1, 2)),
      ]);
      expect(events.length, 2);
      expect(events.first.weight, 0);
      expect(events.first.reps, 10);
      // The 5kg set's rep-dimension before is the 0kg curve (0 ≤ 5 reps
      // done at 0kg implies the 5-rep best was 0).
      expect(events.last.beforeWeight, 0);
    });

    test('0x13 then 0x15 — the reps dimension advances at 0kg', () {
      final events = prEvents([
        _set('s1', exerciseId: 'dips', weight: 0, reps: 13,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'dips', weight: 0, reps: 15,
            date: DateTime(2024, 1, 2)),
      ]);
      expect(events.length, 2);
      expect(events.last.beforeReps, 13);
    });
  });

  group('chronological evolution', () {
    test('same variation frontier evolves — each extension is an event', () {
      final events = prEvents([
        _set('s1',
            exerciseId: 'bench', variationId: 'pause', weight: 80, reps: 5,
            date: DateTime(2024, 1, 1)),
        _set('s2',
            exerciseId: 'bench', variationId: 'pause', weight: 100, reps: 5,
            date: DateTime(2024, 2, 1)),
      ]);
      expect(events.length, 2);
      expect(events.first.beforeWeight, isNull);
      expect(events.last.weight, 100);
      expect(events.last.beforeWeight, 80);
    });

    test('sets in the same session order by set number', () {
      final events = prEvents([
        _set('s1', exerciseId: 'ex', weight: 0, reps: 10, setNumber: 1,
            date: DateTime(2024, 1, 2), sessionId: 'wB'),
        _set('s2', exerciseId: 'ex', weight: 0, reps: 12, setNumber: 2,
            date: DateTime(2024, 1, 2), sessionId: 'wB'),
      ]);
      expect(events.length, 2);
      expect(events.first.beforeReps, isNull); // First PR
      expect(events.last.beforeReps, 10);
    });
  });

  group('lenses', () {
    test('repMaxCurve is a pure projection — the N list never gates it', () {
      // 13 reps at 100kg: curve[13] = 100 even though 13 is not a
      // kTrackedRepCounts value; every n ≤ 13 inherits it.
      final curve = repMaxCurve([
        _set('s1', exerciseId: 'bench', weight: 100, reps: 13),
      ]);
      expect(curve[13], 100);
      expect(curve[12], 100);
      expect(curve[1], 100);
    });

    test('weightMaxCurve tracks exact weights — no fabricated entries', () {
      final curve = weightMaxCurve([
        _set('s1', exerciseId: 'ex', weight: 5, reps: 8),
        _set('s2', exerciseId: 'ex', weight: 100, reps: 10,
            date: DateTime(2024, 1, 2)),
      ]);
      // 100x10 implies the ≥8-rep max (the rep-max lens), but the EXACT
      // weight lens never invents a 10-rep set at 5kg.
      expect(curve, {5: 8, 100: 10});

      // The rep-max lens DOES inherit the heavier lift for n ≤ 10.
      final repCurve = repMaxCurve([
        _set('s1', exerciseId: 'ex', weight: 5, reps: 8),
        _set('s2', exerciseId: 'ex', weight: 100, reps: 10,
            date: DateTime(2024, 1, 2)),
      ]);
      expect(repCurve[8], 100);
    });

    test('repAxisHistory lists every set that raised the axis', () {
      final history = repAxisHistory([
        _set('s1', exerciseId: 'bench', weight: 80, reps: 5,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'bench', weight: 100, reps: 5,
            date: DateTime(2024, 2, 1)),
        _set('s3', exerciseId: 'bench', weight: 90, reps: 5,
            date: DateTime(2024, 3, 1)), // no raise — 100 already stands
      ], 5);
      expect(history.length, 2);
      expect(history.last.weight, 100);
    });

    test('weightAxisHistory lists every set that raised the max reps', () {
      final history = weightAxisHistory([
        _set('s1', exerciseId: 'ex', weight: 100, reps: 5),
        _set('s2', exerciseId: 'ex', weight: 100, reps: 8,
            date: DateTime(2024, 2, 1)),
        _set('s3', exerciseId: 'ex', weight: 100, reps: 6,
            date: DateTime(2024, 3, 1)), // no raise
      ], 100);
      expect(history.length, 2);
      expect(history.last.reps.first, 8);
    });
  });
}
