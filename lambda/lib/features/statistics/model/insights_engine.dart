import '../../../data/models/workout_set.dart';
import '../../session/model/pr_engine.dart';

/// Pure computation module for the Insights screen — no DB, no widgets.
/// Every function takes already-loaded [PastSetRow]s / [PrRecord]s plus
/// filter params and returns aggregated data for the charts and metric cards.

enum InsightRange {
  week('1W', 7),
  fortnight('2W', 14),
  month('1M', 30),
  threeMonths('3M', 90),
  sixMonths('6M', 180),
  year('1Y', 365);

  const InsightRange(this.label, this.startOffset);

  final String label;

  /// Days of history the range covers.
  final int startOffset;

  double get weeks => startOffset / 7.0;
}

/// The bucket a date falls into for a given range's granularity:
/// day ranges → midnight; week ranges → Monday midnight; month ranges → 1st.
DateTime bucketStart(DateTime d, InsightRange range) {
  switch (range) {
    case InsightRange.week:
    case InsightRange.fortnight:
      return DateTime(d.year, d.month, d.day);
    case InsightRange.month:
    case InsightRange.threeMonths:
      return DateTime(d.year, d.month, d.day)
          .subtract(Duration(days: d.weekday - 1));
    case InsightRange.sixMonths:
    case InsightRange.year:
      return DateTime(d.year, d.month);
  }
}

/// Every bucket in the range window, oldest first — including empty ones so
/// charts span the full period rather than only the days with data.
List<DateTime> bucketsFor(InsightRange range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: range.startOffset - 1));
  final out = <DateTime>[];
  DateTime? prev;
  for (var d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
    final b = bucketStart(d, range);
    if (b != prev) {
      out.add(b);
      prev = b;
    }
  }
  return out;
}

/// Count of [events] landing in each of [buckets], aligned by index.
List<int> countsPerBucket(
    List<DateTime> buckets, List<DateTime> events, InsightRange range) {
  final map = <DateTime, int>{};
  for (final e in events) {
    final b = bucketStart(e, range);
    map[b] = (map[b] ?? 0) + 1;
  }
  return [for (final b in buckets) map[b] ?? 0];
}

bool _inWindow(DateTime d, InsightRange range, DateTime now) =>
    !d.isAfter(now) &&
    d.isAfter(now.subtract(Duration(days: range.startOffset)));

/// Sets within the range window, filtered by exercise/variation
/// (empty selection = all). Works on the raw timeline.
List<PastSetRow> filterSets(
  List<PastSetRow> sets,
  InsightRange range,
  Set<String> exercises,
  Set<String?> variations,
  DateTime now,
) {
  return sets.where((s) {
    if (!_inWindow(s.workoutCreatedDate, range, now)) return false;
    if (exercises.isNotEmpty && !exercises.contains(s.exerciseId)) return false;
    if (variations.isNotEmpty && !variations.contains(s.variationId)) return false;
    return true;
  }).toList();
}

/// PRs within the range window, filtered by exercise/variation.
/// [prs] should already be the full timeline (computed over all history),
/// so records remain correct relative to prior PRs, not the truncated window.
List<PrRecord> filterPrs(
  List<PrRecord> prs,
  InsightRange range,
  Set<String> exercises,
  Set<String?> variations,
  DateTime now,
) {
  return prs.where((p) {
    if (!_inWindow(p.achievedDate, range, now)) return false;
    if (exercises.isNotEmpty && !exercises.contains(p.exerciseId)) return false;
    if (variations.isNotEmpty && !variations.contains(p.variationId)) return false;
    return true;
  }).toList();
}

/// The effective rep value for a set — first reps entry, else duration as a
/// proxy for timed exercises (mirrors the PR engine's semantics).
num? effectiveReps(WorkoutSet s) =>
    s.reps.isNotEmpty ? s.reps.first : (s.duration.isNotEmpty ? s.duration.first : null);

/// Weight distribution. Bodyweight (null weight) counts as 0kg; keys are
/// weights rounded to the nearest [kWeightBucket] kg.
const int kWeightBucket = 5;

Map<int, int> weightHistogram(List<PastSetRow> sets) {
  final h = <int, int>{};
  for (final s in sets) {
    final w = s.weight ?? 0;
    final b = ((w / kWeightBucket).round() * kWeightBucket);
    h[b] = (h[b] ?? 0) + 1;
  }
  return h;
}

const List<({String label, int min, int? max})> kRepRanges = [
  (label: '1-3', min: 1, max: 3),
  (label: '4-6', min: 4, max: 6),
  (label: '7-10', min: 7, max: 10),
  (label: '11-15', min: 11, max: 15),
  (label: '16-20', min: 16, max: 20),
  (label: '21+', min: 21, max: null),
];

/// Rep range → count (effective reps bucketed into [kRepRanges]).
Map<String, int> repsHistogram(List<PastSetRow> sets) {
  final h = <String, int>{};
  for (final s in sets) {
    final r = effectiveReps(s);
    if (r == null || r < 1) continue;
    final rr = kRepRanges.firstWhere((range) {
      final max = range.max;
      return max == null ? r >= range.min : (r >= range.min && r <= max);
    });
    h[rr.label] = (h[rr.label] ?? 0) + 1;
  }
  return h;
}

// ── Metric cards ──────────────────────────────────────────────────────────────

typedef PrMetrics = ({int total, double perWeek, num? best1rm});
typedef SetMetrics = ({int total, double perWeek, int exercises});
typedef WeightMetrics = ({int mostHit, double avgWeight, num? maxWeight});
typedef RepMetrics = ({String topRange, double avgReps, int totalReps});

PrMetrics prMetrics(List<PrRecord> prs, InsightRange range) {
  final total = prs.length;
  num? best1rm;
  for (final p in prs) {
    if (p.type == PrType.repMax && p.targetReps == 1) {
      if (best1rm == null || p.weight > best1rm) best1rm = p.weight;
    }
  }
  return (total: total, perWeek: total / range.weeks, best1rm: best1rm);
}

SetMetrics setMetrics(List<PastSetRow> sets, InsightRange range) {
  final exercises = sets.map((s) => s.exerciseId).toSet().length;
  return (total: sets.length, perWeek: sets.length / range.weeks, exercises: exercises);
}

WeightMetrics weightMetrics(List<PastSetRow> sets, Map<int, int> histogram) {
  var mostHit = 0, mostHitCount = -1;
  histogram.forEach((bucket, count) {
    if (count > mostHitCount) {
      mostHitCount = count;
      mostHit = bucket;
    }
  });
  var sum = 0.0, n = 0;
  num? maxWeight;
  for (final s in sets) {
    final w = s.weight;
    if (w == null) continue; // bodyweight excluded from weight averages
    sum += w;
    n++;
    if (maxWeight == null || w > maxWeight) maxWeight = w;
  }
  return (mostHit: mostHit, avgWeight: n == 0 ? 0 : sum / n, maxWeight: maxWeight);
}

RepMetrics repMetrics(List<PastSetRow> sets, Map<String, int> histogram) {
  String top = '—';
  var topCount = -1;
  histogram.forEach((label, count) {
    if (count > topCount) {
      topCount = count;
      top = label;
    }
  });
  var sum = 0.0, n = 0, total = 0;
  for (final s in sets) {
    final r = effectiveReps(s);
    if (r == null || r < 1) continue;
    sum += r;
    n++;
    total += r.toInt();
  }
  return (topRange: top, avgReps: n == 0 ? 0 : sum / n, totalReps: total);
}
