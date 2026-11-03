/// The numeric reading of a planned target — the one place a free-text
/// target ("60", "8-12", "AMRAP", "3 RIR") is turned into numbers.
///
/// Planned targets are free text by design: the plan is a suggestion, not a
/// schema. Most targets are not measurable at all — `AMRAP`, `3 RIR` and
/// legacy comma lists ("8,10") parse to null and stay guide-only. What does
/// parse is a single number or an inclusive range, with the unit a user
/// naturally types ("60 kg", "8-12 reps") tolerated (2026-10-23).
///
/// The three readings the session surfaces draw from this:
/// - a **single planned weight** is recorded as the set's real weight when
///   the session starts ([plannedWeightValue]);
/// - a real value **matches** the plan when it equals a single number
///   (weight) or lands inside a number/range (reps) — the white-on-blue chip;
/// - a real value **contradicts** the plan when it falls outside a range or
///   off a single number — the set row retires its blue tint.
library;

/// A parsed target: one value or an inclusive range.
class PlannedTarget {
  const PlannedTarget.value(num value)
      : min = value,
        max = value,
        isSingle = true;

  const PlannedTarget.range(this.min, this.max) : isSingle = false;

  final num min;
  final num max;
  final bool isSingle;

  bool contains(num actual) => actual >= min && actual <= max;

  /// Equality for a single value; a range is never "the" value.
  bool equals(num actual) => isSingle && actual == min;
}

/// `60`, `60 kg`, `60.5`, or `60-70` — non-negative. Ranges are guides: a
/// weight range never becomes a logged weight.
PlannedTarget? parsePlannedWeight(String? text) =>
    _parse(text, _weightUnits, positive: false);

/// `5`, `8-12`, `8 - 12 reps` — positive. A planned rep count is always a
/// guide; this only ever matches what the user types.
PlannedTarget? parsePlannedReps(String? text) =>
    _parse(text, _repUnits, positive: true);

const _weightUnits = {'kg', 'kgs', 'lb', 'lbs'};
const _repUnits = {'rep', 'reps'};

PlannedTarget? _parse(
  String? text,
  Set<String> units, {
  required bool positive,
}) {
  if (text == null) return null;
  var s = text.trim().toLowerCase();
  if (s.isEmpty) return null;

  // Peel a trailing unit if the text carries one ("60 kg", "8-12reps").
  for (final unit in units) {
    if (s.endsWith(unit)) {
      s = s.substring(0, s.length - unit.length).trimRight();
      break;
    }
  }
  if (s.isEmpty) return null;

  final match = _rangePattern.firstMatch(s);
  if (match == null) return null;

  final first = double.tryParse(match.group(1)!);
  final second = match.group(2) == null
      ? null
      : double.tryParse(match.group(2)!);
  if (first == null) return null;
  if (second == null) {
    if (positive ? first <= 0 : first < 0) return null;
    return PlannedTarget.value(first);
  }
  if (positive ? first <= 0 || second <= 0 : first < 0 || second < 0) {
    return null;
  }
  // "12-8" is not a range anybody meant; leave it a guide.
  if (second < first) return null;
  return PlannedTarget.range(first, second);
}

final _rangePattern =
    RegExp(r'^(\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?))?$');

/// The weight to record when the session starts: a single non-negative
/// number, or null when the target is a range or not a number at all.
double? plannedWeightValue(String? target) {
  final parsed = parsePlannedWeight(target);
  return parsed == null || !parsed.isSingle ? null : parsed.min.toDouble();
}

/// The weight cell's chip: a real weight that equals a single planned
/// number. A weight range is a guide and never chips.
bool weightIsPlan(String? target, num? actual) {
  final parsed = parsePlannedWeight(target);
  return actual != null && parsed != null && parsed.equals(actual);
}

/// The row tint's weight rule: empty cells and non-numeric targets never
/// deviate; a number or range must be met.
bool weightInPlan(String? target, num? actual) {
  if (actual == null) return true;
  final parsed = parsePlannedWeight(target);
  return parsed == null || parsed.contains(actual);
}

/// The reps cell's chip **and** the row tint's reps rule: a real rep count
/// equal to the planned number or inside its inclusive range. Empty cells
/// are the tint's "no deviation" (null), but never a chip.
bool repsMatchPlan(String? target, num? actual) {
  final parsed = parsePlannedReps(target);
  return actual != null && parsed != null && parsed.contains(actual);
}

/// The row tint's reps rule: empty cells and non-numeric targets never
/// deviate.
bool repsInPlan(String? target, num? actual) {
  if (actual == null) return true;
  final parsed = parsePlannedReps(target);
  return parsed == null || parsed.contains(actual);
}
