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
        sessions:
            _maps(raw['sessions']).map(AchievementSession.fromMap).toList(),
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

  /// The strongest set in the window for this goal's exercise, whether or not
  /// it met the target — the panel shows *how close* a missed goal came, which
  /// is the whole reason a goal is worth reviewing.
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
/// A goal is met when some single set for its exercise reaches the target
/// weight AND the target reps — `weight >= targetWeight && reps >= targetReps`.
/// Not the PR frontier, which answers a different question ("is this the best
/// ever?") than a goal does ("did I do the thing I said I would?").
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
    PastSetRow? strongestQualifying;

    for (final set in sets) {
      if (set.exerciseId != exerciseId) continue;
      // Exact, null included: a no-variation goal asks for plain sets, so a
      // paused set is out of scope — not evidence for a near miss either.
      if (set.variationId != goal.variationId) continue;
      final date = set.sessionCreatedDate;
      if (date.isBefore(from) || !date.isBefore(to)) continue;

      if (_heavierThan(set, strongest)) strongest = set;
      if (_meetsTarget(set, goal) && _heavierThan(set, strongestQualifying)) {
        strongestQualifying = set;
      }
    }

    // The heaviest qualifying set is the evidence for a hit; for a miss, the
    // heaviest set at all — so a missed goal reports how close it came rather
    // than how recently it was attempted.
    final evidence = strongestQualifying ?? strongest;
    out.add(GoalAchievement(
      goal: goal,
      achieved: strongestQualifying != null,
      evidenceWeight: evidence == null ? null : (evidence.weight ?? 0),
      evidenceReps:
          evidence == null || evidence.reps.isEmpty ? null : evidence.reps.first,
      evidenceDate: evidence?.sessionCreatedDate,
      evidenceVariationId: evidence?.variationId,
    ));
  }
  return out;
}

/// Bodyweight is weight 0 in the logging model, so a null weight is a real
/// value here and must not read as "no evidence".
bool _heavierThan(PastSetRow set, PastSetRow? than) =>
    than == null || (set.weight ?? 0) > (than.weight ?? 0);

bool _meetsTarget(PastSetRow set, Goal goal) {
  final weight = (set.weight ?? 0).toDouble();
  final reps = set.reps.isEmpty ? 0.0 : set.reps.first.toDouble();
  return weight >= (goal.targetWeight ?? 0) &&
      reps >= (goal.targetReps?.toDouble() ?? 0);
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
