import '../../../data/models/session_exercise_set.dart';

/// Personal-record computation engine.
///
/// A single set can be a PR on multiple axes at once. Doing `105kg × 3`
/// when your previous best at 3 reps was 100kg also means you'd beat your
/// previous 1RM and 2RM (if you can lift 105 for 3, you can lift it for
/// 1 or 2) — so one set can generate several [PrRecord]s.
enum PrType { repMax, weightMax }

/// The rep counts tracked for rep-max PRs. Anything above 30 is not a PR
/// axis — a `500kg × 100` set improves only these rep counts (1–10, 12, 15,
/// 20, 25, 30) plus the 500kg weight-max record. Kept in the engine so the
/// restriction applies at record-creation time everywhere, not just in views.
const kTrackedRepCounts = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30};

/// One PR event — an improvement to the best weight for a specific rep
/// count (repMax, e.g. a new 5RM), or an improvement to the most reps done
/// at a specific weight (weightMax, e.g. most reps at 100kg).
class PrRecord {
  const PrRecord({
    required this.exerciseId,
    required this.weight,
    required this.reps,
    required this.achievedDate,
    required this.sessionId,
    required this.type,
    this.sessionExerciseSetId,
    this.exerciseName,
    this.variationId,
    this.variationName,
    this.targetReps,
    this.targetWeight,
    this.isPropagated = false,
  });

  final String exerciseId;
  final String? exerciseName;
  final String? variationId;
  final String? variationName;
  final num weight;
  final num reps;
  final DateTime achievedDate;
  final String sessionId;

  /// The source set that produced this record. Plain reference (no FK) so
  /// the snapshot survives the set being deleted.
  final String? sessionExerciseSetId;
  final PrType type;

  /// For [PrType.repMax]: which rep count this improves (the N in "N-rep max").
  final int? targetReps;

  /// For [PrType.weightMax]: which weight this improves ("most reps at X").
  final num? targetWeight;

  /// True when this PR was inferred from a different performance rather
  /// than directly achieved.  E.g. a 1RM record produced by a 5-rep set
  /// is propagated (only the 5RM is explicit).  Weight-max records bumped
  /// by a heavier lift are also propagated.
  final bool isPropagated;

  /// Short label for the type, e.g. "1RM", "5RM", "100kg".
  String get typeLabel => switch (type) {
        PrType.repMax => '${targetReps ?? ''}RM',
        PrType.weightMax => '${targetWeight != null ? _fmt(targetWeight!) : ''}kg',
      };

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  factory PrRecord.fromMap(Map<String, dynamic> map) => PrRecord(
        exerciseId: map['custom_exercise_id'] as String? ?? '',
        exerciseName: map['exercise_name'] as String?,
        variationId: map['custom_variation_id'] as String?,
        variationName: map['variation_name'] as String?,
        weight: _toNum(map['weight']),
        reps: _toNum(map['reps']),
        achievedDate: _parseDate(map['achieved_date']),
        sessionId: (map['session_id'] as String?) ?? _sessionIdFromSet(map['session_exercise_set_id'] as String?),
        sessionExerciseSetId: map['session_exercise_set_id'] as String?,
        type: _typeFromString(map['pr_type'] as String? ?? 'repMax'),
        targetReps: _toInt(map['target_reps']),
        targetWeight: _toNumNullable(map['target_weight']),
        isPropagated: _toBool(map['is_propagated']),
      );

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    final t = DateTime.tryParse('$v');
    return t ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, dynamic> toMap() => {
        'session_exercise_set_id': sessionExerciseSetId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'weight': weight,
        'reps': reps,
        'achieved_date': achievedDate.toUtc().toIso8601String(),
        'pr_type': type.name,
        'target_reps': targetReps,
        'target_weight': targetWeight,
        'is_propagated': isPropagated ? 1 : 0,
      };

  static String _sessionIdFromSet(String? setId) => setId ?? '';

  static PrType _typeFromString(String s) => switch (s) {
        'weightMax' || 'weightClass' => PrType.weightMax, // weightClass = legacy
        _ => PrType.repMax,
      };

  static num _toNum(dynamic v) => v is num ? v : double.tryParse('$v') ?? 0;
  static num? _toNumNullable(dynamic v) => v == null ? null : _toNum(v);
  static int? _toInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }
}

/// The effective rep/volume value for a set — first reps entry, or duration
/// as a proxy for timed exercises. Null if the set has neither.
num? _effectiveReps(SessionExerciseSet s) =>
    s.reps.isNotEmpty ? s.reps.first : null;

/// The best weight ever lifted for "at least [repCount] reps" across
/// [sets] for the (exerciseId, variationId) pair — the rep-max curve.
/// PR curves are scoped per exercise × variation: a Pause Bench PR never
/// affects regular Bench. NULL variation is its own distinct key.
///
/// curve[N] = highest weight where the user has achieved ≥ N reps.
/// Monotone non-increasing in N.
Map<int, num> repMaxCurve(List<PastSetRow> sets, String exerciseId,
    {String? variationId}) {
  final curve = <int, num>{};
  for (final s in sets) {
    if (s.exerciseId != exerciseId) continue;
    if (s.variationId != variationId) continue;
    // Bodyweight is just weight 0 — it feeds the curve like any other weight.
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

/// Walks the full set history chronologically (oldest first) and returns
/// every PR ever achieved. Maintains, per exercise:
///   - a running rep-max curve (`curve[N]` = best weight for ≥ N reps)
///   - the max reps done at each weight (weight-max)
///
/// [sets] may be in any order; this sorts by [PastSetRow.sessionCreatedDate].
List<PrRecord> fullPrTimeline(List<PastSetRow> sets) {
  // Sort by date, then by set number — sets logged in the SAME session
  // share a timestamp, and Dart's sort is not stable, so the tie-break
  // keeps intra-session order deterministic (5x7 before 5x9).
  final ordered = [...sets]..sort((a, b) {
    final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
    return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
  });

  final curve = <(String, String?), Map<int, num>>{}; // (exercise, variation) → repCount → bestWeight
  final maxRepsAtWeight = <(String, String?), Map<num, int>>{}; // (exercise, variation) → weight → maxReps

  final prs = <PrRecord>[];

  for (final s in ordered) {
    // A free row with no exercise has no PR axis — skip it.
    final exerciseId = s.exerciseId;
    if (exerciseId == null) continue;
    // Null weight = bodyweight (0kg) — only reps are mandatory for a PR.
    final weight = s.weight ?? 0;
    final reps = _effectiveReps(s);
    if (reps == null) continue;

    final exCurve = curve.putIfAbsent((exerciseId, s.variationId), () => {});
    final exMaxReps = maxRepsAtWeight.putIfAbsent((exerciseId, s.variationId), () => {});

    // Rep-max curve: one record per tracked rep count N ≤ reps that this set
    // improves. The EXPLICIT record goes to the highest tracked value the
    // set covers — reps falling between tracked values (e.g. 13) claim the
    // floor (12RM) as the achieved record, because ≥12 reps were performed;
    // every lower tracked N stays propagated.
    // Bodyweight (0kg) feeds the curve like any other weight — a 13-rep
    // dips set is a 12RM at 0kg.
    var maxTracked = 0;
    for (final n in kTrackedRepCounts) {
      if (n <= reps && n > maxTracked) maxTracked = n;
    }
    if (maxTracked > 0) {
      for (final n in kTrackedRepCounts) {
        if (n > reps) break;
        final current = exCurve[n];
        if (current == null || weight > current) {
          exCurve[n] = weight;
          prs.add(PrRecord(
            exerciseId: exerciseId,
            exerciseName: s.exerciseName,
            variationId: s.variationId,
            variationName: s.variationName,
            weight: weight,
            reps: reps,
            achievedDate: s.sessionCreatedDate,
            sessionId: s.sessionId,
            sessionExerciseSetId: s.sessionExerciseSetId,
            type: PrType.repMax,
            targetReps: n,
            isPropagated: n != maxTracked,
          ));
        }
      }
    }

    // Weight-max: most reps at a weight, monotone non-increasing.
    // If you can lift W × R you can lift any lighter weight at least R times.
    final newReps = reps.toInt();
    final effectiveMax = exMaxReps.entries
        .where((e) => e.key >= weight && (weight > 0 || e.key == 0))
        .fold<int>(0, (m, e) => e.value > m ? e.value : m);
    if (newReps > effectiveMax) {
      exMaxReps[weight] = newReps;
      // Explicit weight-max record for the weight actually lifted.
      prs.add(PrRecord(
        exerciseId: exerciseId,
        exerciseName: s.exerciseName,
        variationId: s.variationId,
        variationName: s.variationName,
        weight: weight,
        reps: reps,
        achievedDate: s.sessionCreatedDate,
        sessionId: s.sessionId,
        sessionExerciseSetId: s.sessionExerciseSetId,
        type: PrType.weightMax,
        targetWeight: weight,
        isPropagated: false,
      ));
      // Propagate downward to lighter weights that were EXPLICITLY lifted
      // before (existing map keys) whose implied max-reps also increased.
      // Weights the user never actually lifted are never fabricated — doing
      // 100kg × 10 does not invent a record for 95kg. Never reaches 0kg —
      // the bodyweight axis tracks its own reps independently.
      for (final entry in exMaxReps.entries.toList()) {
        if (entry.key < weight && entry.key > 0 && entry.value < newReps) {
          exMaxReps[entry.key] = newReps;
          prs.add(PrRecord(
            exerciseId: exerciseId,
            exerciseName: s.exerciseName,
            variationId: s.variationId,
            variationName: s.variationName,
            weight: entry.key,
            reps: newReps,
            achievedDate: s.sessionCreatedDate,
            sessionId: s.sessionId,
            sessionExerciseSetId: s.sessionExerciseSetId,
            type: PrType.weightMax,
            targetWeight: entry.key,
            isPropagated: true,
          ));
        }
      }
    }
  }

  return prs;
}

/// Achieved records — the only ones a user should ever SEE: propagated
/// records are curve internals (a stronger set implies weaker axes), never
/// something actually performed.
List<PrRecord> achievedRecords(List<PrRecord> records) =>
    records.where((p) => !p.isPropagated).toList();

/// Countable records — explicit rep-max only. Weight-max (any weight,
/// bodyweight 0kg included) is display-only trivia, never a count.
List<PrRecord> countableRecords(List<PrRecord> records) =>
    records.where((p) => !p.isPropagated && p.type == PrType.repMax).toList();

/// Before-tracking for one session's records: maps each record belonging to
/// [sessionId] to the previous record on its axis — history OR an earlier set
/// in the same session. Keyed per source set so two records on the same axis
/// in one session each keep their own before; an axis-keyed map would
/// overwrite the first record's null before with itself and misreport a
/// first PR as "10 reps → 10 reps" instead of "(First PR)".
/// Callers pass achieved-only records — propagated records never chain.
({Map<(String, String?, int, String?), PrRecord?> repMax,
        Map<(String, String?, num, String?), PrRecord?> weightMax})
    sessionBeforeMaps(List<PrRecord> records, String sessionId) {
  final repMax = <(String, String?, int, String?), PrRecord?>{};
  final weightMax = <(String, String?, num, String?), PrRecord?>{};
  final lastRepMax = <(String, String?, int), PrRecord?>{};
  final lastWeightMax = <(String, String?, num), PrRecord?>{};
  for (final r in records) {
    if (r.type == PrType.repMax && r.targetReps != null) {
      final axis = (r.exerciseId, r.variationId, r.targetReps!);
      if (r.sessionId == sessionId) {
        repMax[(r.exerciseId, r.variationId, r.targetReps!, r.sessionExerciseSetId)] =
            lastRepMax[axis];
      }
      lastRepMax[axis] = r;
    } else if (r.type == PrType.weightMax && r.targetWeight != null) {
      final axis = (r.exerciseId, r.variationId, r.targetWeight!);
      if (r.sessionId == sessionId) {
        weightMax[(r.exerciseId, r.variationId, r.targetWeight!, r.sessionExerciseSetId)] =
            lastWeightMax[axis];
      }
      lastWeightMax[axis] = r;
    }
  }
  return (repMax: repMax, weightMax: weightMax);
}

/// PRs set during a single workout.
List<PrRecord> prsForWorkout(List<PastSetRow> sets, String sessionId) {
  return fullPrTimeline(sets).where((p) => p.sessionId == sessionId).toList();
}

/// PRs for a specific exercise (all types).
List<PrRecord> prsForExercise(List<PastSetRow> sets, String exerciseId) {
  return fullPrTimeline(sets).where((p) => p.exerciseId == exerciseId).toList();
}

/// PRs for a specific exercise + variation pair.
List<PrRecord> variationPrs(List<PastSetRow> sets, String variationId) {
  return fullPrTimeline(sets).where((p) => p.variationId == variationId).toList();
}

/// The best-ever weight×reps for an exercise — returned as a simple record
/// for the live-session PR baseline.
({num weight, num reps})? bestEverForExercise(List<PastSetRow> pastSets,
    {String? variationId}) {
  ({num weight, num reps})? best;
  for (final s in pastSets) {
    if (variationId != null && s.variationId != variationId) continue;
    final weight = s.weight ?? 0; // bodyweight sets count as 0kg
    final reps = _effectiveReps(s);
    if (reps == null) continue;
    if (best == null || weight > best.weight || (weight == best.weight && reps > best.reps)) {
      best = (weight: weight, reps: reps);
    }
  }
  return best;
}
