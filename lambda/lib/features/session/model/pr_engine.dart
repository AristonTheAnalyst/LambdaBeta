import '../../../data/models/session_exercise_set.dart';

/// Personal-record computation engine.
///
/// The core definition: a set is a PR iff it extends its (exercise ×
/// variation) pair's best-ever frontier — no prior set did at least this
/// many reps at at least this weight. One set = ONE event, even when it
/// beats prior records on both dimensions at once (weight and reps are the
/// same relation viewed from opposite sides). Everything axis-shaped —
/// N-rep max curves, weight-max curves, per-axis progressions — is a
/// projection, a LENS computed by the insights surfaces over raw history,
/// never part of detection.

/// The rep counts the insights surfaces display on their rep-max curves.
/// A display config only — detection does not depend on it, and lenses
/// work at any N.
const kTrackedRepCounts = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30};

/// One PR event — a set that extended its pair's best-ever frontier.
/// [beforeWeight] / [beforeReps] are the two previous frontier values it
/// beat (null = first on that dimension): the previous best weight at ≥
/// this many reps, and the previous best reps at exactly this weight. A
/// single event can beat both at once — one PR, two "was" facts.
class PrEvent {
  const PrEvent({
    required this.exerciseId,
    required this.weight,
    required this.reps,
    required this.achievedDate,
    required this.sessionId,
    this.sessionExerciseSetId,
    this.exerciseName,
    this.variationId,
    this.variationName,
    this.beforeWeight,
    this.beforeReps,
  });

  final String exerciseId;
  final String? exerciseName;
  final String? variationId;
  final String? variationName;
  final num weight;
  final num reps;
  final DateTime achievedDate;
  final String sessionId;

  /// The source set that produced this event. Plain reference (no FK) so
  /// the event survives the set being deleted.
  final String? sessionExerciseSetId;

  /// Previous best weight for ≥ [reps] reps — null = first time doing
  /// this many reps.
  final num? beforeWeight;

  /// Previous best reps at exactly [weight] — null = first time at this
  /// weight.
  final num? beforeReps;
}

/// The effective rep value for a set — first reps entry. Null if empty.
num? _effectiveReps(SessionExerciseSet s) =>
    s.reps.isNotEmpty ? s.reps.first : null;

/// Walks the full set history chronologically (oldest first) and returns
/// every PR event — one per set that extended its (exercise × variation)
/// pair's best-ever frontier.
///
/// Dominance rule: a set (w, r) is a PR iff no prior set had weight ≥ w
/// AND reps ≥ r. So 100×5 after 110×1 IS a PR (110 doesn't cover 5 reps),
/// and 100×4 after 100×5 is not. Bodyweight is weight 0. NULL variation is
/// its own distinct key — a Pause Bench PR never affects regular Bench.
///
/// [sets] may be in any order; sorted by session date, then set number
/// (sets in the SAME session share a timestamp, and Dart's sort is not
/// stable — the tie-break keeps intra-session order deterministic).
List<PrEvent> prEvents(List<PastSetRow> sets) {
  final ordered = [...sets]..sort((a, b) {
    final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
    return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
  });

  // (exercise, variation) → (minReps → best weight, exact weight → best reps)
  final state = <(String, String?), (Map<int, num>, Map<num, num>)>{};
  final events = <PrEvent>[];

  for (final s in ordered) {
    // A free row with no exercise has no PR axis — skip it.
    final exerciseId = s.exerciseId;
    if (exerciseId == null) continue;
    // Null weight = bodyweight (0kg) — only reps are mandatory for a PR.
    final weight = s.weight ?? 0;
    final reps = _effectiveReps(s);
    if (reps == null) continue;

    final pair = state.putIfAbsent(
      (exerciseId, s.variationId),
      () => ({}, {}),
    );
    final bestWeightForMinReps = pair.$1;
    final bestRepsAtExactWeight = pair.$2;

    final repsInt = reps.toInt();
    final prevWeight = bestWeightForMinReps[repsInt];
    final prevReps = bestRepsAtExactWeight[weight];

    if (prevWeight == null || prevWeight < weight) {
      events.add(PrEvent(
        exerciseId: exerciseId,
        exerciseName: s.exerciseName,
        variationId: s.variationId,
        variationName: s.variationName,
        weight: weight,
        reps: reps,
        achievedDate: s.sessionCreatedDate,
        sessionId: s.sessionId,
        sessionExerciseSetId: s.sessionExerciseSetId,
        beforeWeight: prevWeight,
        beforeReps: prevReps,
      ));
    }

    // The frontier updates on EVERY set — dominated sets still feed the
    // before-values of later events (90×6 after 100×6 is not a PR, but a
    // later 90×8 must report "was 90 × 6", never a first).
    if (prevReps == null || reps > prevReps) {
      bestRepsAtExactWeight[weight] = reps;
    }
    for (var n = 1; n <= reps; n++) {
      final cur = bestWeightForMinReps[n];
      if (cur == null || weight > cur) bestWeightForMinReps[n] = weight;
    }
  }
  return events;
}

// ── Lenses — pure projections over raw history for the insights surfaces ──
// These derive from ALL sets, not from events: 110×2 was never a "3RM PR",
// but it still feeds the 3-rep lens the moment a ≥3-rep set lifts it.

/// curve[N] = highest weight with ≥ N reps across the given (already
/// scoped — exercise/variation filtered) sets. Monotone non-increasing in
/// N. Bodyweight is weight 0.
Map<int, num> repMaxCurve(List<PastSetRow> sets) {
  final curve = <int, num>{};
  for (final s in sets) {
    final weight = s.weight ?? 0;
    final reps = _effectiveReps(s);
    if (reps == null) continue;
    for (var n = 1; n <= reps; n++) {
      final current = curve[n];
      if (current == null || weight > current) curve[n] = weight;
    }
  }
  return curve;
}

/// The most reps ever done at each exact weight across the scoped sets.
Map<num, num> weightMaxCurve(List<PastSetRow> sets) {
  final curve = <num, num>{};
  for (final s in sets) {
    final weight = s.weight ?? 0;
    final reps = _effectiveReps(s);
    if (reps == null) continue;
    final cur = curve[weight];
    if (cur == null || reps > cur) curve[weight] = reps;
  }
  return curve;
}

/// Chronological progression of one rep-count axis — every set that raised
/// the best weight at ≥ [repCount] reps, oldest first. The insights
/// axis-history lens (e.g. the "5RM history" sheet).
List<PastSetRow> repAxisHistory(List<PastSetRow> sets, int repCount) {
  final ordered = [...sets]..sort((a, b) {
    final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
    return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
  });
  final out = <PastSetRow>[];
  num? best;
  for (final s in ordered) {
    final reps = _effectiveReps(s);
    if (reps == null || reps < repCount) continue;
    final weight = s.weight ?? 0;
    if (best == null || weight > best) {
      best = weight;
      out.add(s);
    }
  }
  return out;
}

/// Chronological progression of one weight axis — every set that raised
/// the max reps at exactly [weight], oldest first. Lens.
List<PastSetRow> weightAxisHistory(List<PastSetRow> sets, num weight) {
  final ordered = [...sets]..sort((a, b) {
    final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
    return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
  });
  final out = <PastSetRow>[];
  num? best;
  for (final s in ordered) {
    if ((s.weight ?? 0) != weight) continue;
    final reps = _effectiveReps(s);
    if (reps == null) continue;
    if (best == null || reps > best) {
      best = reps;
      out.add(s);
    }
  }
  return out;
}
