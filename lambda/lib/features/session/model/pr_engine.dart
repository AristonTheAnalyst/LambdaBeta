import '../../../data/models/workout_set.dart';

/// Personal-record computation engine.
///
/// A single set can be a PR on multiple axes at once. Doing `105kg × 3`
/// when your previous best at 3 reps was 100kg also means you'd beat your
/// previous 1RM and 2RM (if you can lift 105 for 3, you can lift it for
/// 1 or 2) — so one set can generate several [PrRecord]s.
enum PrType { absolute, repMax, weightClass }

/// One PR event — either an improvement to the all-time best weight for an
/// exercise (absolute), an improvement to the best weight for a specific rep
/// count (repMax, e.g. a new 5RM), or an improvement to the most reps done
/// at a specific weight (weightClass).
class PrRecord {
  const PrRecord({
    required this.exerciseId,
    required this.weight,
    required this.reps,
    required this.achievedDate,
    required this.workoutId,
    required this.type,
    this.setId,
    this.exerciseName,
    this.variationId,
    this.variationName,
    this.targetReps,
    this.targetWeight,
  });

  final String exerciseId;
  final String? exerciseName;
  final String? variationId;
  final String? variationName;
  final num weight;
  final num reps;
  final DateTime achievedDate;
  final String workoutId;

  /// The source set that produced this record. Plain reference (no FK) so
  /// the snapshot survives the set being deleted.
  final String? setId;
  final PrType type;

  /// For [PrType.repMax]: which rep count this improves (the N in "N-rep max").
  final int? targetReps;

  /// For [PrType.weightClass]: which weight this improves ("most reps at X").
  final num? targetWeight;

  /// Short label for the type, e.g. "1RM", "5RM", "100kg × 12", "Absolute".
  String get typeLabel => switch (type) {
        PrType.absolute => 'Absolute',
        PrType.repMax => '${targetReps ?? ''}RM',
        PrType.weightClass => '${targetWeight != null ? _fmt(targetWeight!) : ''}kg',
      };

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  factory PrRecord.fromMap(Map<String, dynamic> map) => PrRecord(
        exerciseId: map['custom_exercise_id'] as String,
        exerciseName: map['exercise_name'] as String?,
        variationId: map['custom_variation_id'] as String?,
        variationName: map['variation_name'] as String?,
        weight: _toNum(map['weight']),
        reps: _toNum(map['reps']),
        achievedDate: DateTime.parse(map['achieved_date'] as String),
        workoutId: (map['user_workout_id'] as String?) ?? _workoutIdFromSet(map['workout_set_id'] as String?),
        setId: map['workout_set_id'] as String?,
        type: _typeFromString(map['pr_type'] as String),
        targetReps: _toInt(map['target_reps']),
        targetWeight: _toNumNullable(map['target_weight']),
      );

  Map<String, dynamic> toMap() => {
        'workout_set_id': setId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'weight': weight,
        'reps': reps,
        'achieved_date': achievedDate.toUtc().toIso8601String(),
        'pr_type': type.name,
        'target_reps': targetReps,
        'target_weight': targetWeight,
        'is_active': 1,
      };

  static String _workoutIdFromSet(String? setId) => setId ?? '';

  static PrType _typeFromString(String s) => switch (s) {
        'absolute' => PrType.absolute,
        'weightClass' => PrType.weightClass,
        _ => PrType.repMax,
      };

  static num _toNum(dynamic v) => v is num ? v : double.tryParse('$v') ?? 0;
  static num? _toNumNullable(dynamic v) => v == null ? null : _toNum(v);
  static int? _toInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
}

/// The effective rep/volume value for a set — first reps entry, or duration
/// as a proxy for timed exercises. Null if the set has neither.
num? _effectiveReps(WorkoutSet s) =>
    s.reps.isNotEmpty ? s.reps.first : (s.duration.isNotEmpty ? s.duration.first : null);

/// The best weight ever lifted for "at least [repCount] reps" across
/// [sets] for [exerciseId] — the rep-max curve.
///
/// curve[N] = highest weight where the user has achieved ≥ N reps.
/// Monotone non-increasing in N.
Map<int, num> repMaxCurve(List<PastSetRow> sets, String exerciseId) {
  final curve = <int, num>{};
  for (final s in sets) {
    if (s.exerciseId != exerciseId) continue;
    final weight = s.weight;
    final reps = _effectiveReps(s);
    if (weight == null || reps == null) continue;
    for (var n = 1; n <= reps; n++) {
      final current = curve[n];
      if (current == null || weight > current) curve[n] = weight;
    }
  }
  return curve;
}

/// Walks the full set history chronologically (oldest first) and returns
/// every PR ever achieved. Maintains, per exercise:
///   - a running rep-max curve (`curve[N]` = best weight for ≥ N reps)
///   - the all-time best weight (absolute)
///   - the max reps done at each weight (weight-class)
///
/// [sets] may be in any order; this sorts by [PastSetRow.workoutCreatedDate].
List<PrRecord> fullPrTimeline(List<PastSetRow> sets) {
  final ordered = [...sets]..sort((a, b) => a.workoutCreatedDate.compareTo(b.workoutCreatedDate));

  final curve = <String, Map<int, num>>{}; // exerciseId → repCount → bestWeight
  final absolute = <String, num>{}; // exerciseId → bestWeight
  final absReps = <String, num>{}; // exerciseId → reps at bestWeight
  final maxRepsAtWeight = <String, Map<num, int>>{}; // exerciseId → weight → maxReps

  final prs = <PrRecord>[];

  for (final s in ordered) {
    final weight = s.weight;
    final reps = _effectiveReps(s);
    if (weight == null || reps == null) continue;

    final exCurve = curve.putIfAbsent(s.exerciseId, () => {});
    final exMaxReps = maxRepsAtWeight.putIfAbsent(s.exerciseId, () => {});

    // Absolute PR: weight exceeds the best ever, or equals it with more reps
    final abs = absolute[s.exerciseId];
    if (abs == null || weight > abs || (weight == abs && reps > (absReps[s.exerciseId] ?? 0))) {
      absolute[s.exerciseId] = weight;
      absReps[s.exerciseId] = reps;
      prs.add(PrRecord(
        exerciseId: s.exerciseId,
        exerciseName: s.exerciseName,
        variationId: s.variationId,
        variationName: s.variationName,
        weight: weight,
        reps: reps,
        achievedDate: s.workoutCreatedDate,
        workoutId: s.workoutId,
        setId: s.setId,
        type: PrType.absolute,
      ));
    }

    // Rep-max curve: one record per rep count N ≤ reps that this set improves
    for (var n = 1; n <= reps; n++) {
      final current = exCurve[n];
      if (current == null || weight > current) {
        exCurve[n] = weight;
        prs.add(PrRecord(
          exerciseId: s.exerciseId,
          exerciseName: s.exerciseName,
          variationId: s.variationId,
          variationName: s.variationName,
          weight: weight,
          reps: reps,
          achievedDate: s.workoutCreatedDate,
          workoutId: s.workoutId,
          setId: s.setId,
          type: PrType.repMax,
          targetReps: n,
        ));
      }
    }

    // Weight-class: most reps done at exactly this weight
    final curReps = exMaxReps[weight];
    if (curReps == null || reps > curReps) {
      exMaxReps[weight] = reps.toInt();
      prs.add(PrRecord(
        exerciseId: s.exerciseId,
        exerciseName: s.exerciseName,
        variationId: s.variationId,
        variationName: s.variationName,
        weight: weight,
        reps: reps,
        achievedDate: s.workoutCreatedDate,
        workoutId: s.workoutId,
        setId: s.setId,
        type: PrType.weightClass,
        targetWeight: weight,
      ));
    }
  }

  return prs;
}

/// The current best PR per exercise — the latest state of the rep-max curve
/// summarized as one record per exercise (the absolute best set).
List<PrRecord> currentPrs(List<PastSetRow> sets) {
  final prs = fullPrTimeline(sets);
  final seen = <String>{};
  final result = <PrRecord>[];
  // fullPrTimeline is chronological; the last absolute record per exercise
  // is the current best.
  for (final pr in prs) {
    if (pr.type == PrType.absolute && seen.add(pr.exerciseId)) {
      result.add(pr);
    }
  }
  return result;
}

/// PRs set during a single workout.
List<PrRecord> prsForWorkout(List<PastSetRow> sets, String workoutId) {
  return fullPrTimeline(sets).where((p) => p.workoutId == workoutId).toList();
}

/// PRs for a specific exercise (all types).
List<PrRecord> prsForExercise(List<PastSetRow> sets, String exerciseId) {
  return fullPrTimeline(sets).where((p) => p.exerciseId == exerciseId).toList();
}

/// PRs for a specific exercise + variation pair.
List<PrRecord> variationPrs(List<PastSetRow> sets, String variationId) {
  return fullPrTimeline(sets).where((p) => p.variationId == variationId).toList();
}

/// The best-ever weight×reps for an exercise — same semantics as
/// [PrType.absolute] but returned as a simple record for inline comparisons.
({num weight, num reps})? bestEverForExercise(List<PastSetRow> pastSets) {
  ({num weight, num reps})? best;
  for (final s in pastSets) {
    final weight = s.weight;
    final reps = _effectiveReps(s);
    if (weight == null || reps == null) continue;
    if (best == null || weight > best.weight || (weight == best.weight && reps > best.reps)) {
      best = (weight: weight, reps: reps);
    }
  }
  return best;
}
