import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/planned_target.dart';

/// The planned-target parser (2026-10-23): free-text targets are guides
/// unless they carry a number — a single value or an inclusive range. The
/// grammar the session surfaces draw is only as good as this reading, so
/// everything the app does with a target passes through here.
void main() {
  group('parsing', () {
    test('single weights', () {
      expect(parsePlannedWeight('60')?.isSingle, isTrue);
      expect(parsePlannedWeight('60')?.min, 60);
      expect(parsePlannedWeight('60.5')?.min, 60.5);
      expect(parsePlannedWeight(' 60 ')?.min, 60);
      expect(parsePlannedWeight('60 kg')?.min, 60);
      expect(parsePlannedWeight('60kgs')?.min, 60);
      expect(parsePlannedWeight('100 lb')?.min, 100);
      expect(
        parsePlannedWeight('0')?.min,
        0,
        reason: 'bodyweight is a real planned weight',
      );
    });

    test('weight ranges are inclusive and guided', () {
      final range = parsePlannedWeight('60-70');
      expect(range?.isSingle, isFalse);
      expect(range?.min, 60);
      expect(range?.max, 70);
      expect(parsePlannedWeight('60 - 70 kg')?.contains(65), isTrue);
      expect(parsePlannedWeight('60-70')?.equals(60), isFalse,
          reason: 'a range is never "the" value');
      expect(
        parsePlannedWeight('70-60'),
        isNull,
        reason: 'a backwards range is not a range anybody meant',
      );
    });

    test('rep readings are positive', () {
      expect(parsePlannedReps('5')?.min, 5);
      expect(parsePlannedReps('8-12')?.contains(9), isTrue);
      expect(parsePlannedReps('8 - 12 reps')?.contains(12), isTrue);
      expect(parsePlannedReps('8-12reps')?.min, 8);
      expect(parsePlannedReps('0'), isNull);
      expect(parsePlannedReps('-5'), isNull);
    });

    test('anything else is a guide only', () {
      for (final text in ['AMRAP', '3 RIR', '8,10', '8 12', '', '   ', null]) {
        expect(parsePlannedWeight(text), isNull, reason: 'weight "$text"');
        expect(parsePlannedReps(text), isNull, reason: 'reps "$text"');
      }
    });
  });

  group('adoption', () {
    test('only a single-number weight is recorded at Start', () {
      expect(plannedWeightValue('60'), 60);
      expect(plannedWeightValue('60.5'), 60.5);
      expect(plannedWeightValue('0'), 0);
      expect(plannedWeightValue('60-70'), isNull,
          reason: 'a range never becomes a logged value');
      expect(plannedWeightValue('AMRAP'), isNull);
      expect(plannedWeightValue(null), isNull);
    });
  });

  group('the chip', () {
    test('weight chips on a single number only', () {
      expect(weightIsPlan('60', 60), isTrue);
      expect(weightIsPlan('60 kg', 60), isTrue);
      expect(weightIsPlan('60', 65), isFalse);
      expect(weightIsPlan('60-70', 65), isFalse,
          reason: 'a weight range is a guide and never chips');
      expect(weightIsPlan('AMRAP', 60), isFalse);
      expect(weightIsPlan('60', null), isFalse);
    });

    test('reps chip on the number or inside the range, inclusive', () {
      expect(repsMatchPlan('5', 5), isTrue);
      expect(repsMatchPlan('8-12', 8), isTrue);
      expect(repsMatchPlan('8-12', 9), isTrue);
      expect(repsMatchPlan('8-12', 12), isTrue);
      expect(repsMatchPlan('8-12', 13), isFalse);
      expect(repsMatchPlan('5', 6), isFalse);
      expect(repsMatchPlan('AMRAP', 9), isFalse);
      expect(repsMatchPlan('8-12', null), isFalse);
    });
  });

  group('the row tint', () {
    test('empty cells and non-numeric targets never deviate', () {
      expect(weightInPlan('60', null), isTrue);
      expect(weightInPlan('60-70', null), isTrue);
      expect(weightInPlan('AMRAP', 60), isTrue);
      expect(weightInPlan(null, 60), isTrue);
      expect(repsInPlan('8-12', null), isTrue);
      expect(repsInPlan('3 RIR', 9), isTrue);
      expect(repsInPlan(null, 9), isTrue);
    });

    test('a range or number must be met', () {
      expect(weightInPlan('60', 60), isTrue);
      expect(weightInPlan('60', 65), isFalse);
      expect(weightInPlan('60-70', 65), isTrue);
      expect(weightInPlan('60-70', 75), isFalse);
      expect(repsInPlan('8-12', 9), isTrue);
      expect(repsInPlan('8-12', 15), isFalse);
      expect(repsInPlan('5', 5), isTrue);
      expect(repsInPlan('5', 6), isFalse);
    });
  });
}
