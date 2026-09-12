import '../../../data/models/session_exercise_set.dart';
import '../../session/model/pr_engine.dart';

/// Pure computations for the per-exercise insights page — no DB, no widgets.
/// Everything derives from the already-loaded past-sets timeline, so date-
/// filter and variation switching are instant client-side recomputes.

/// Sets for one exercise across ALL variations, oldest first.
List<PastSetRow> setsForExercise(List<PastSetRow> all, String exerciseId) {
  final out = all.where((s) => s.exerciseId == exerciseId).toList()
    ..sort((a, b) => a.sessionCreatedDate.compareTo(b.sessionCreatedDate));
  return out;
}

/// Sets for one exercise scoped to ONE variation. null means the "no
/// variation" scope — sets logged without a variation.
List<PastSetRow> setsScoped(
  List<PastSetRow> all,
  String exerciseId,
  String? variationId,
) {
  final out = all
      .where(
        (s) => s.exerciseId == exerciseId && s.variationId == variationId,
      )
      .toList()
    ..sort((a, b) => a.sessionCreatedDate.compareTo(b.sessionCreatedDate));
  return out;
}

/// The variations this exercise has been logged with, in first-use order —
/// [(id, display name)]. The caller adds the "All Variations" option.
List<({String? id, String name})> variationsFor(List<PastSetRow> scopedAll) {
  final seen = <String?>{};
  final out = <({String? id, String name})>[];
  for (final s in scopedAll) {
    if (!seen.add(s.variationId)) continue;
    out.add((
      id: s.variationId,
      name: s.variationName?.isNotEmpty == true
          ? s.variationName!
          : (s.variationId == null ? 'No variation' : s.variationId!),
    ));
  }
  return out;
}

/// Every PR event whose date lands in [from, to), newest first — one per
/// frontier-extending set, so one rung on the journey per set.
List<PrEvent> prsInWindow(
  List<PastSetRow> scopedSets,
  DateTime from,
  DateTime to,
) {
  final out = <PrEvent>[];
  for (final p in prEvents(scopedSets)) {
    final d = p.achievedDate;
    if (d.isBefore(from) || !d.isBefore(to)) continue;
    out.add(p);
  }
  out.sort((a, b) => b.achievedDate.compareTo(a.achievedDate));
  return out;
}

/// Best set in [from, to) — highest weight, ties broken by reps.
/// Null when nothing was logged in the window. (Bodyweight counts as 0kg.)
({double weight, double reps})? bestInWindow(
  List<PastSetRow> scopedSets,
  DateTime from,
  DateTime to,
) {
  ({double weight, double reps})? best;
  for (final s in scopedSets) {
    final d = s.sessionCreatedDate;
    if (d.isBefore(from) || !d.isBefore(to)) continue;
    final w = s.weight ?? 0;
    final r = s.reps.isNotEmpty ? s.reps.first.toDouble() : 0.0;
    if (best == null ||
        w > best.weight ||
        (w == best.weight && r > best.reps)) {
      best = (weight: w, reps: r);
    }
  }
  return best;
}

/// Best set logged ON [day] (all history, same scoping) — null when none.
({double weight, double reps})? bestOnDay(
  List<PastSetRow> scopedSets,
  DateTime day,
) {
  final from = DateTime(day.year, day.month, day.day);
  return bestInWindow(scopedSets, from, from.add(const Duration(days: 1)));
}

/// PR frequency denominator — the window length in weeks.
double weeksIn(int days) => days / 7;

/// Distinct calendar weeks (Monday-start) within [from, to) that contain at
/// least one set — the "how many weeks did I actually train this" count.
/// Per-week rates divide by THIS, not by the calendar window, so a fresh
/// exercise isn't diluted by idle weeks.
int activeWeeksInWindow(
  List<PastSetRow> scopedSets,
  DateTime from,
  DateTime to,
) {
  final weeks = <DateTime>{};
  for (final s in scopedSets) {
    final d = s.sessionCreatedDate;
    if (d.isBefore(from) || !d.isBefore(to)) continue;
    weeks.add(
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1)),
    );
  }
  return weeks.length;
}

/// The rep-max curve as of a point in time — only sets logged before
/// [before] count. curve[N] = best weight for ≥ N reps. (Bodyweight is 0kg,
/// so a pure-bodyweight exercise yields a flat 0kg curve.)
Map<int, num> curveAt(List<PastSetRow> scopedSets, DateTime before) {
  final curve = <int, num>{};
  for (final s in scopedSets) {
    if (!s.sessionCreatedDate.isBefore(before)) continue;
    final weight = s.weight ?? 0;
    final reps = s.reps.isNotEmpty ? s.reps.first : 0;
    if (reps < 1) continue;
    for (final n in kTrackedRepCounts) {
      if (n > reps) break;
      final current = curve[n];
      if (current == null || weight > current) curve[n] = weight;
    }
  }
  return curve;
}

/// Most reps performed at exactly [weight] before [before] — null when none.
int? maxRepsAtWeight(
  List<PastSetRow> scopedSets,
  DateTime before,
  num weight,
) {
  int? best;
  for (final s in scopedSets) {
    if (!s.sessionCreatedDate.isBefore(before)) continue;
    if ((s.weight ?? 0) != weight) continue;
    final reps = s.reps.isNotEmpty ? s.reps.first.toInt() : 0;
    if (reps > (best ?? 0)) best = reps;
  }
  return best;
}

/// Distinct weights, most-used first (ties: heavier first), capped at
/// [limit]. Callers pass window-scoped sets so the filter is respected.
List<num> weightsByUsage(List<PastSetRow> scopedSets, {int limit = 10}) {
  final counts = <num, int>{};
  for (final s in scopedSets) {
    final w = s.weight ?? 0;
    counts[w] = (counts[w] ?? 0) + 1;
  }
  final ws = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : b.compareTo(a);
    });
  return ws.take(limit).toList();
}

/// Most reps logged before [before] — the bodyweight progression axis.
int? maxRepsAt(List<PastSetRow> scopedSets, DateTime before) {
  int? best;
  for (final s in scopedSets) {
    if (!s.sessionCreatedDate.isBefore(before)) continue;
    final reps = s.reps.isNotEmpty ? s.reps.first.toInt() : 0;
    if (reps > (best ?? 0)) best = reps;
  }
  return best;
}
