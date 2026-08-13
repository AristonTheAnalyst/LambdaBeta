import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session_set.dart';
import 'package:lambda/features/session/model/pr_engine.dart';

PastSetRow _set(
  String id, {
  required String exerciseId,
  String? variationId,
  required double weight,
  required int reps,
  DateTime? date,
}) =>
    PastSetRow(
      sessionSetId: id,
      sessionId: 'w1',
      userId: 'u1',
      exerciseId: exerciseId,
      setNumber: 1,
      reps: [reps],
      sessionCreatedDate: date ?? DateTime(2024, 1, 1),
      variationId: variationId,
      weight: weight,
    );

void main() {
  group('variation-scoped PR curves', () {
    test('Pause Bench PR does not affect regular Bench', () {
      final sets = [
        _set('s1',
            exerciseId: 'bench',
            variationId: 'pause',
            weight: 100,
            reps: 5),
        _set('s2', exerciseId: 'bench', weight: 60, reps: 5),
      ];
      final prs = fullPrTimeline(sets);

      // Pause Bench 100x5: explicit 5RM at 100 (pause) + propagated 1-4RM.
      final pause5 = prs.where((p) =>
          p.variationId == 'pause' &&
          p.type == PrType.repMax &&
          p.targetReps == 5);
      expect(pause5.length, 1);
      expect(pause5.first.isPropagated, isFalse);
      expect(pause5.first.weight, 100);

      // Regular Bench 60x5 gets its OWN 5RM at 60 — it must not see the
      // pause-bench 100kg curve.
      final regular5 = prs.where((p) =>
          p.variationId == null &&
          p.type == PrType.repMax &&
          p.targetReps == 5);
      expect(regular5.length, 1);
      expect(regular5.first.weight, 60);
      expect(regular5.first.isPropagated, isFalse);
    });

    test('null variation is a distinct key from a named variation', () {
      final sets = [
        _set('s1', exerciseId: 'squat', weight: 100, reps: 5),
        _set('s2',
            exerciseId: 'squat',
            variationId: 'paused',
            weight: 120,
            reps: 5),
      ];
      final prs = fullPrTimeline(sets);

      // Both curves get their own 5RM — neither cancels the other.
      final regular = prs.where((p) =>
          p.variationId == null &&
          p.type == PrType.repMax &&
          p.targetReps == 5);
      final paused = prs.where((p) =>
          p.variationId == 'paused' &&
          p.type == PrType.repMax &&
          p.targetReps == 5);
      expect(regular.first.weight, 100);
      expect(paused.first.weight, 120);
    });

    test('weight-max is also scoped per variation', () {
      final sets = [
        _set('s1',
            exerciseId: 'bench',
            variationId: 'pause',
            weight: 100,
            reps: 5),
        _set('s2', exerciseId: 'bench', weight: 100, reps: 3),
      ];
      final prs = fullPrTimeline(sets);

      // Pause: most reps at 100 = 5. Regular: most reps at 100 = 3 —
      // independent curves.
      final pauseMax = prs.where((p) =>
          p.variationId == 'pause' &&
          p.type == PrType.weightMax &&
          p.targetWeight == 100);
      final regularMax = prs.where((p) =>
          p.variationId == null &&
          p.type == PrType.weightMax &&
          p.targetWeight == 100);
      expect(pauseMax.first.reps, 5);
      expect(regularMax.first.reps, 3);
    });

    test('same variation curve evolves chronologically', () {
      final sets = [
        _set('s1',
            exerciseId: 'bench',
            variationId: 'pause',
            weight: 80,
            reps: 5,
            date: DateTime(2024, 1, 1)),
        _set('s2',
            exerciseId: 'bench',
            variationId: 'pause',
            weight: 100,
            reps: 5,
            date: DateTime(2024, 2, 1)),
      ];
      final prs = fullPrTimeline(sets);

      final pause5 = prs
          .where((p) =>
              p.variationId == 'pause' &&
              p.type == PrType.repMax &&
              p.targetReps == 5)
          .toList();
      // Both sets improved the 5RM (80 then 100) — two records, last wins.
      expect(pause5.length, 2);
      expect(pause5.last.weight, 100);
    });
  });
}
