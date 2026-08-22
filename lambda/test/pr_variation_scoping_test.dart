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

    test('bodyweight sets never feed the weighted rep-max curve', () {
      // 10 bodyweight reps, then 5kg x 5: the 5kg set must NOT generate
      // rep-max records comparing against 0kg, and the bodyweight 10 reps
      // must not be beaten by 5 weighted reps on the weight-max axis.
      final sets = [
        _set('s1', exerciseId: 'pushup', weight: 0, reps: 10,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'pushup', weight: 5, reps: 5,
            date: DateTime(2024, 1, 2)),
      ];
      final prs = fullPrTimeline(sets);

      // The bodyweight 10-rep set generates NO rep-max records — 0kg never
      // feeds the weighted curve.
      final repMaxFromBodyweight = prs.where((p) =>
          p.type == PrType.repMax && p.weight == 0);
      expect(repMaxFromBodyweight, isEmpty);

      // The 5kg set gets its own rep-max records (1-5RM at 5kg) — the
      // previous 0kg curve is not consulted, so the display's "before" is
      // absent rather than 0kg.
      final repMax5 = prs.where((p) =>
          p.type == PrType.repMax && p.weight == 5 && p.targetReps == 5);
      expect(repMax5.length, 1);
      expect(repMax5.first.isPropagated, isFalse);

      // The bodyweight 10-rep weight-max (at 0kg) is not beaten by 5 reps.
      final zeroWeightMax = prs.where((p) =>
          p.type == PrType.weightMax && p.targetWeight == 0);
      expect(zeroWeightMax.length, 1);
      expect(zeroWeightMax.first.reps, 10);

      // The 5kg lift creates its own weight-max record (5 reps at 5kg).
      final fiveWeightMax = prs.where((p) =>
          p.type == PrType.weightMax && p.targetWeight == 5);
      expect(fiveWeightMax.length, 1);
      expect(fiveWeightMax.first.reps, 5);
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

  group('weight-max propagation', () {
    test('only bumps weights that were explicitly lifted', () {
      // 5kg x 8, then 100kg x 10: the heavier set implies more reps at 5kg,
      // but weights the user never lifted (7.5, 10, 12.5, ...) get nothing.
      final sets = [
        _set('s1', exerciseId: 'ex', weight: 5, reps: 8,
            date: DateTime(2024, 1, 1)),
        _set('s2', exerciseId: 'ex', weight: 100, reps: 10,
            date: DateTime(2024, 1, 2)),
      ];
      final prs = fullPrTimeline(sets);

      final weightMax = prs.where((p) => p.type == PrType.weightMax).toList();
      final targets = weightMax.map((p) => p.targetWeight).toSet();
      expect(targets, {5, 100},
          reason: 'propagation must never fabricate weights never lifted');

      // 5kg: explicit 8 first, then bumped to 10 by the 100kg set.
      final five = weightMax.where((p) => p.targetWeight == 5).toList();
      expect(five.length, 2);
      expect(five.last.reps, 10);
      expect(five.last.isPropagated, isTrue);

      // 100kg: the explicit record only.
      final hundred = weightMax.where((p) => p.targetWeight == 100).toList();
      expect(hundred.length, 1);
      expect(hundred.first.reps, 10);
      expect(hundred.first.isPropagated, isFalse);
    });
  });

  group('session before-tracking', () {
    PastSetRow row(String setId, int setNumber, double weight, int reps) =>
        PastSetRow(
          sessionSetId: setId,
          sessionId: 'wB',
          userId: 'u1',
          exerciseId: 'pushup',
          setNumber: setNumber,
          reps: [reps],
          sessionCreatedDate: DateTime(2024, 1, 2),
          weight: weight,
        );

    test('first record on an axis keeps a null before when a later set '
        're-hits the axis', () {
      // Two bodyweight sets in one session: 0kg x 10, then 0kg x 12. The
      // 0x10 record must keep before = null — an axis-keyed map would get
      // overwritten by the 0x12 record's before (the 0x10 record itself) and
      // render "0kg: 10 reps → 10 reps" instead of "(First PR)".
      final records =
          fullPrTimeline([row('b1', 1, 0, 10), row('b2', 2, 0, 12)]);
      final before = sessionBeforeMaps(records, 'wB');

      final first0 = records.firstWhere((r) =>
          r.type == PrType.weightMax &&
          r.targetWeight == 0 &&
          r.reps == 10 &&
          !r.isPropagated);
      expect(
          before.weightMax[
              (first0.exerciseId, first0.variationId, 0, first0.setId)],
          isNull,
          reason: 'the first 0kg PR must render as First PR, not against itself');

      final second0 = records.firstWhere((r) =>
          r.type == PrType.weightMax &&
          r.targetWeight == 0 &&
          r.reps == 12 &&
          !r.isPropagated);
      expect(
          before.weightMax[(second0.exerciseId, second0.variationId, 0, second0.setId)]
              ?.reps,
          10);
    });

    test('two rep-max records on one axis keep their own befores', () {
      // 100 x 5 then 120 x 5: the first 5RM's before stays null, the
      // second's is the 100kg record.
      final records =
          fullPrTimeline([row('b1', 1, 100, 5), row('b2', 2, 120, 5)]);
      final before = sessionBeforeMaps(records, 'wB');

      final first5 = records.firstWhere((r) =>
          r.type == PrType.repMax && r.targetReps == 5 && r.weight == 100);
      expect(
          before.repMax[(first5.exerciseId, first5.variationId, 5, first5.setId)],
          isNull,
          reason: 'the first 5RM must render as First PR, not "100kg → 100kg"');

      final second5 = records.firstWhere((r) =>
          r.type == PrType.repMax && r.targetReps == 5 && r.weight == 120);
      expect(
          before
              .repMax[(second5.exerciseId, second5.variationId, 5, second5.setId)]
              ?.weight,
          100);
    });
  });
}
