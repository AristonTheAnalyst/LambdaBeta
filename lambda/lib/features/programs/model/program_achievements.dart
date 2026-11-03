import 'dart:convert';

import '../../../data/models/goal.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../exercises/model/exercise_insights.dart';
import '../../session/model/pr_engine.dart';

/// What a program run has produced, derived over a window.
///
/// Derived live while the run is open, and serialized onto the close review
/// when it ends — the ONE deliberate exception to this repo's derive-on-read
/// philosophy. A finished block's record must not change because someone later
/// corrected a set. The rule stays clean: **in-progress runs derive, closed
/// runs show the frozen record.**
///
/// [encode] / [decode] round-trip into the same type, so the frozen record and
/// the live view are literally the same shape and cannot drift into two
/// interpretations of the same history.
class ProgramAchievements {
  const ProgramAchievements({
    required this.from,
    this.until,
    this.sessions = const [],
    this.prs = const [],
    this.goals = const [],
    this.weightStart,
    this.weightEnd,
  });

  /// The window opens here — the previous checkpoint, or the start of the run.
  final DateTime from;

  /// Exclusive upper bound; null means "now".
  final DateTime? until;

  /// Completed sessions attributed to the run, oldest first.
  final List<AchievementSession> sessions;

  /// Every frontier-extending set in the window, newest first.
  final List<PrEvent> prs;

  final List<GoalAchievement> goals;

  /// Bodyweight at the edges of the window, when the user logged any.
  final double? weightStart;
  final double? weightEnd;

  int get achievedGoalCount => goals.where((g) => g.achieved).length;

  int get missedGoalCount => goals.where((g) => !g.achieved).length;

  /// Nothing to report — not "no rows", but "nothing worth a checkpoint".
  /// Bodyweight alone does not qualify: it moves for reasons that have nothing
  /// to do with the program.
  bool get isEmpty => sessions.isEmpty && prs.isEmpty && goals.isEmpty;

  /// The frozen document written to `fact_program_review.achievements_json`.
  String encode() => jsonEncode(toJson());

  /// Decodes a frozen record, or returns null when there is none or the
  /// document cannot be read (written by a newer build). A closed run whose
  /// record is unreadable renders as an empty panel, never as a crash.
  static ProgramAchievements? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return null;
      return ProgramAchievements(
        from: _date(raw['from']) ?? DateTime.now(),
        until: _date(raw['until']),
        weightStart: _num(raw['weight_start'])?.toDouble(),
        weightEnd: _num(raw['weight_end'])?.toDouble(),
        sessions: _maps(
          raw['sessions'],
        ).map(AchievementSession.fromMap).toList(),
        prs: _maps(raw['prs']).map(_prFromMap).toList(),
        goals: _maps(raw['goals']).map(GoalAchievement.fromMap).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'from': from.toUtc().toIso8601String(),
    'until': until?.toUtc().toIso8601String(),
    'weight_start': weightStart,
    'weight_end': weightEnd,
    'sessions': sessions.map((s) => s.toMap()).toList(),
    'prs': prs.map(_prToMap).toList(),
    'goals': goals.map((g) => g.toMap()).toList(),
  };
}

/// One goal's outcome across a window — the goal itself plus what met it.
///
/// Evidence is three display values rather than a `PastSetRow`: the frozen
/// record has to round-trip, and a row reference through a decode would point
/// at set data the record deliberately does not carry. Three values are also
/// all the panel renders.
class GoalAchievement {
  const GoalAchievement({
    required this.goal,
    required this.achieved,
    this.evidenceWeight,
    this.evidenceReps,
    this.evidenceDate,
    this.evidenceVariationId,
  });

  final Goal goal;
  final bool achieved;

  /// The set the outcome is told by. A hit's evidence is the **earliest**
  /// set that met the target — the set that achieved the goal (2026-10-20).
  /// A miss's is the strongest set in the window, whether or not it met the
  /// target, so the panel shows *how close* a missed goal came.
  final num? evidenceWeight;
  final num? evidenceReps;
  final DateTime? evidenceDate;
  final String? evidenceVariationId;

  Map<String, dynamic> toMap() => {
    'goal_id': goal.goalId,
    'text': goal.text,
    'exercise_id': goal.exerciseId,
    'target_weight': goal.targetWeight,
    'target_reps': goal.targetReps,
    // A multi-set goal's rungs (2026-10-26). Written only when there are any,
    // so a single-set record keeps the document it always had — an added
    // empty key would change every old snapshot's bytes and its hash.
    if (goal.targets.isNotEmpty)
      'targets': [for (final t in goal.targets) t.toMap()],
    'achieved': achieved,
    'evidence_weight': evidenceWeight,
    'evidence_reps': evidenceReps,
    'evidence_date': evidenceDate?.toUtc().toIso8601String(),
    'evidence_variation_id': evidenceVariationId,
  };

  factory GoalAchievement.fromMap(Map<String, dynamic> map) => GoalAchievement(
    // A frozen record is read long after the goal row may be gone — goals
    // are facts, and facts hard-delete — so the outcome carries its own
    // copy of what was being chased. `userId` is not part of the record.
    goal: Goal(
      goalId: '${map['goal_id']}',
      userId: '',
      text: map['text'] as String?,
      exerciseId: map['exercise_id'] as String?,
      targetWeight: _num(map['target_weight']),
      targetReps: _num(map['target_reps'])?.toInt(),
      targets: [
        for (final entry
            in (map['targets'] is List ? map['targets'] as List : const []))
          if (entry is Map)
            GoalTargetSet.fromMap(entry.cast<String, dynamic>()),
      ],
    ),
    achieved: map['achieved'] == true,
    evidenceWeight: _num(map['evidence_weight']),
    evidenceReps: _num(map['evidence_reps']),
    evidenceDate: _date(map['evidence_date']),
    evidenceVariationId: map['evidence_variation_id'] as String?,
  );
}

/// Every PR event in `[from, to)` across every exercise and variation, newest
/// first.
///
/// `prsInWindow` works per (exercise, variation) scope — a frontier is per
/// pair — so the sets are grouped first and the results merged. Grouping rather
/// than filtering one flat list is what makes a PR in one lift visible
/// alongside a PR in another, which is the entire point of a review.
List<PrEvent> prsAcrossScopes(
  List<PastSetRow> sets,
  DateTime from,
  DateTime to,
) {
  final byScope = <String, List<PastSetRow>>{};
  for (final s in sets) {
    final exerciseId = s.exerciseId;
    if (exerciseId == null) continue;
    byScope.putIfAbsent('$exerciseId|${s.variationId}', () => []).add(s);
  }

  final out = <PrEvent>[];
  for (final scoped in byScope.values) {
    out.addAll(prsInWindow(scoped, from, to));
  }
  out.sort((a, b) => b.achievedDate.compareTo(a.achievedDate));
  return out;
}

/// Which goals in [goals] were met by sets logged in `[from, to)`.
///
/// A goal is met when every one of its requirements ([Goal.requirements]) is
/// reached by a **distinct** set in scope — a single set can satisfy two rungs
/// ("100 × 5" is also "90 × 3"), but two rungs always need two sets. A
/// single-set goal (one requirement) therefore reduces to the original rule:
/// some set at or above the target weight AND reps. Not the PR frontier, which
/// answers a different question ("is this the best ever?") than a goal does
/// ("did I do the thing I said I would?").
///
/// A goal names exactly one variation, or none — and "none" is a scope of its
/// own rather than a wildcard. A goal on plain bench is met by plain bench
/// sets only; a goal on paused bench by paused sets only, and neither answers
/// the other. That is the same per-(exercise × variation) scoping the PR
/// frontier uses, so a goal and a PR can never disagree about which lift a set
/// belongs to.
List<GoalAchievement> evaluateGoals({
  required List<Goal> goals,
  required List<PastSetRow> sets,
  required DateTime from,
  required DateTime to,
}) {
  final out = <GoalAchievement>[];
  for (final goal in goals) {
    // A free-text goal ("get stronger") has nothing to measure. Carried through
    // unachieved rather than dropped, so the review still lists it and the user
    // can see it was never a number.
    final exerciseId = goal.exerciseId;
    if (exerciseId == null) {
      out.add(GoalAchievement(goal: goal, achieved: false));
      continue;
    }

    PastSetRow? strongest;
    for (final set in sets) {
      if (set.exerciseId != exerciseId) continue;
      // Exact, null included: a no-variation goal asks for plain sets, so a
      // paused set is out of scope — not evidence for a near miss either.
      if (set.variationId != goal.variationId) continue;
      final date = set.sessionCreatedDate;
      if (date.isBefore(from) || !date.isBefore(to)) continue;

      if (_heavierThan(set, strongest)) strongest = set;
    }

    final witnesses = goalWitnessSets(
      sets: sets,
      exerciseId: exerciseId,
      variationId: goal.variationId,
      requirements: goal.requirements,
      from: from,
      to: to,
    );

    // A hit's evidence is the set that COMPLETED the goal — for one
    // requirement the earliest set that met it (2026-10-20), for several the
    // last of the witnesses, because the goal was not achieved before every
    // rung had its set. That is the one the `G` marks wherever it is drawn.
    // A miss's evidence is the heaviest set at all, so the report says how
    // close it came rather than how recently it was attempted.
    final evidence = witnesses == null ? strongest : _latest(witnesses);
    out.add(
      GoalAchievement(
        goal: goal,
        achieved: witnesses != null,
        evidenceWeight: evidence == null ? null : (evidence.weight ?? 0),
        evidenceReps: evidence == null || evidence.reps.isEmpty
            ? null
            : evidence.reps.first,
        evidenceDate: evidence?.sessionCreatedDate,
        evidenceVariationId: evidence?.variationId,
      ),
    );
  }
  return out;
}

/// Bodyweight is weight 0 in the logging model, so a null weight is a real
/// value here and must not read as "no evidence".
bool _heavierThan(PastSetRow set, PastSetRow? than) =>
    than == null || (set.weight ?? 0) > (than.weight ?? 0);

/// Timeline order: the earlier session first, and inside one session the
/// lower set number — a session's rows all share its timestamp, so the
/// number is the only tie-break there is (2026-10-20).
bool _earlierThan(PastSetRow set, PastSetRow than) {
  final d = set.sessionCreatedDate.compareTo(than.sessionCreatedDate);
  return d < 0 || (d == 0 && set.setNumber < than.setNumber);
}

/// The set that completed [goal] — the latest witness of its requirement list
/// — or null while it stands (2026-10-26).
///
/// The completion row under the deadline opens this set's workout, and the
/// frozen record's `Completed <day>` reads from it. For a single-set goal it
/// is the earliest set that met the target, which is what that row has always
/// shown; for several rungs it is the rung that finished the list.
PastSetRow? goalCompletionSet({
  required Goal goal,
  required List<PastSetRow> sets,
}) {
  final exerciseId = goal.exerciseId;
  if (exerciseId == null) return null;
  final witnesses = goalWitnessSets(
    sets: sets,
    exerciseId: exerciseId,
    variationId: goal.variationId,
    requirements: goal.requirements,
  );
  if (witnesses == null || witnesses.isEmpty) return null;
  return _latest(witnesses);
}

/// The latest of [sets] in timeline order — the set whose arrival completed a
/// multi-set goal.
PastSetRow _latest(List<PastSetRow> sets) {
  var latest = sets.first;
  for (final set in sets.skip(1)) {
    if (_earlierThan(latest, set)) latest = set;
  }
  return latest;
}

bool _reachesRequirement(PastSetRow set, GoalTargetSet requirement) =>
    setReachesTarget(set, weight: requirement.weight, reps: requirement.reps);

/// Whether [set] reaches [weight] × [reps] — the one goal rule: a single set
/// at or above BOTH numbers.
///
/// Shared by [evaluateGoals] and the New Goal form's "already beat this" check
/// (2026-10-19), so the two can never disagree about whether a set counts.
/// Bulk and zero both read as 0 — bodyweight is a real weight, and a goal
/// that states only one of the two numbers asks only about that one.
///
/// A set with no reps was never performed (2026-10-23): Start can record a
/// plan's weight into the row, and that adopted value alone must not light a
/// weight-only goal's `G` before the user has done any reps.
bool setReachesTarget(PastSetRow set, {num? weight, int? reps}) {
  if (set.reps.isEmpty) return false;
  final setWeight = (set.weight ?? 0).toDouble();
  final setReps = set.reps.first.toDouble();
  return setWeight >= (weight ?? 0) && setReps >= (reps?.toDouble() ?? 0);
}

/// The set that **first** met a goal — the earliest set that reaches the
/// target, scoped to exactly [exerciseId] × [variationId], exactly the scope
/// [evaluateGoals] applies (2026-10-20).
///
/// This is the set that achieved the goal, so it is the one the `G` badge
/// marks on every set grid, and the one the focused goal sheet's completion
/// row opens. A goal is achieved once: later sets that also reach the target
/// are repeats, not achievements, and stay unmarked.
///
/// The single-requirement form of [goalWitnessSets] — one target pair is a
/// one-rung list, and both go through the same matching rule (2026-10-26).
PastSetRow? earliestSetReaching({
  required List<PastSetRow> sets,
  required String exerciseId,
  required String? variationId,
  num? weight,
  int? reps,
}) {
  final witnesses = goalWitnessSets(
    sets: sets,
    exerciseId: exerciseId,
    variationId: variationId,
    requirements: [GoalTargetSet(weight: weight, reps: reps)],
  );
  return witnesses?.first;
}

/// The sets that achieved [requirements] — one **distinct** set per
/// requirement, in requirement order — or null when they were not all met
/// (2026-10-26).
///
/// One set can satisfy several requirements ("100 × 5" also reaches "90 × 3"),
/// so this is a bipartite assignment rather than a per-requirement search.
/// Greedy in requirement order is not enough: it hands the only 140 set to the
/// 100 rung and strands the 140 one. The sets are walked in timeline order and
/// each one tries to enter the matching by an augmenting path (Kuhn's
/// algorithm), re-pairing requirements that already found a set — so the
/// assignment exists whenever one exists. The walk stops at the first set
/// whose arrival completes the matching: that is the moment the goal was
/// achieved.
///
/// [Goal.requirements] empty means an exercise goal that states no numbers —
/// one empty requirement, which any performed set meets. That is the reading
/// this evaluation has always had for such a goal; callers that want "no
/// target, no verdict" (the creation form's caption) check for themselves.
List<PastSetRow>? goalWitnessSets({
  required List<PastSetRow> sets,
  required String exerciseId,
  required String? variationId,
  required List<GoalTargetSet> requirements,
  DateTime? from,
  DateTime? to,
}) {
  final wanted = requirements.isEmpty ? const [GoalTargetSet()] : requirements;
  final candidates =
      <PastSetRow>[
        for (final set in sets)
          if (set.exerciseId == exerciseId &&
              set.variationId == variationId &&
              (from == null || !set.sessionCreatedDate.isBefore(from)) &&
              (to == null || set.sessionCreatedDate.isBefore(to)))
            set,
      ]..sort((a, b) {
        final byDate = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
        return byDate != 0 ? byDate : a.setNumber.compareTo(b.setNumber);
      });

  // requirement index → the candidate index that holds it. -1 = unmatched.
  final owner = List<int>.filled(wanted.length, -1);
  var matched = 0;
  for (var s = 0; s < candidates.length; s++) {
    final visited = List<bool>.filled(wanted.length, false);
    if (!_augment(s, candidates, wanted, owner, visited)) continue;
    matched++;
    if (matched == wanted.length) {
      return [for (final index in owner) candidates[index]];
    }
  }
  return null;
}

/// One augmenting step of [goalWitnessSets]: try to seat candidate [setIndex]
/// at some requirement it reaches, evicting (and re-seating) that
/// requirement's current set when it has one.
bool _augment(
  int setIndex,
  List<PastSetRow> candidates,
  List<GoalTargetSet> requirements,
  List<int> owner,
  List<bool> visited,
) {
  final set = candidates[setIndex];
  for (var r = 0; r < requirements.length; r++) {
    if (visited[r] || !_reachesRequirement(set, requirements[r])) continue;
    visited[r] = true;
    final holder = owner[r];
    if (holder < 0 ||
        _augment(holder, candidates, requirements, owner, visited)) {
      owner[r] = setIndex;
      return true;
    }
  }
  return false;
}

/// The `fact_session_exercise_set` ids that achieved one of [goals] — the
/// sets drawn green with the `G` badge (2026-10-20).
///
/// Every witness is listed — a multi-set goal needs one set per requirement,
/// all distinct — and a set that achieves two goals is listed once, because
/// the badge says "a goal was achieved here", not which one (2026-10-26).
/// Free-text goals have nothing to measure and mark nothing.
Set<String> goalAchievingSetIds({
  required List<Goal> goals,
  required List<PastSetRow> sets,
}) {
  final ids = <String>{};
  for (final goal in goals) {
    final exerciseId = goal.exerciseId;
    if (exerciseId == null) continue;
    final witnesses = goalWitnessSets(
      sets: sets,
      exerciseId: exerciseId,
      variationId: goal.variationId,
      requirements: goal.requirements,
    );
    if (witnesses == null) continue;
    for (final set in witnesses) {
      ids.add(set.sessionExerciseSetId);
    }
  }
  return ids;
}

// ── Serialization helpers ──────────────────────────────────────────────────

Map<String, dynamic> _prToMap(PrEvent e) => {
  'exercise_id': e.exerciseId,
  'exercise_name': e.exerciseName,
  'variation_id': e.variationId,
  'variation_name': e.variationName,
  'weight': e.weight,
  'reps': e.reps,
  'date': e.achievedDate.toUtc().toIso8601String(),
  'session_id': e.sessionId,
  'before_weight': e.beforeWeight,
  'before_reps': e.beforeReps,
};

/// Rebuilds a real [PrEvent], ids and all, so the frozen record renders through
/// the same PR row widget the live view uses instead of a parallel one.
PrEvent _prFromMap(Map<String, dynamic> map) => PrEvent(
  exerciseId: '${map['exercise_id']}',
  exerciseName: map['exercise_name'] as String?,
  variationId: map['variation_id'] as String?,
  variationName: map['variation_name'] as String?,
  weight: _num(map['weight']) ?? 0,
  reps: _num(map['reps']) ?? 0,
  achievedDate: _date(map['date']) ?? DateTime.now(),
  sessionId: '${map['session_id']}',
  beforeWeight: _num(map['before_weight']),
  beforeReps: _num(map['before_reps']),
);

List<Map<String, dynamic>> _maps(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList(growable: false);
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse('$v');
}
