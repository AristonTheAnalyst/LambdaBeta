import 'dart:convert';

/// A goal — either free text, or an exercise-specific target
/// (e.g. "bench 100kg × 1"). Goals are unattached (2026-10-08): the program
/// and block columns are dormant, like day scheduling — the scope resolution
/// around them stays in the data layer, but nothing files a new goal anywhere.
///
/// There is no `achievedDate`. Achievement is a per-run fact, so a single
/// column could not express "achieved in Block 1, missed in Block 3"; the
/// outcome is frozen per run into the close review instead. While a run is
/// open it is derived — see [evaluateGoals].
///
/// [description] is the one place free prose lives: notes about the goal
/// itself, typed in the focused goal sheet. Nothing derives from it — a goal
/// is still just a set to beat.
///
/// [targetDate] is when it should be beaten by (2026-10-19), and
/// [targetDateHistory] remembers every move of that deadline — a goal whose
/// date slipped is a fact worth keeping, not an overwrite. Both are optional:
/// a goal with no clock on it is still a goal.
///
/// A goal is ONE target pair or a **list of them** (2026-10-26): a multi-set
/// goal names several rungs ("100 × 5, then 110 × 3"), every one of which a
/// session must meet with a distinct set. [targets] holds that list and is
/// empty for a single-set goal, which keeps its numbers in [targetWeight] /
/// [targetReps] exactly as it always has — one storage shape per shape, never
/// a mirrored copy. [requirements] is the one reading every consumer uses, so
/// nothing has to ask which shape it is holding.
class Goal {
  const Goal({
    required this.goalId,
    required this.userId,
    this.createdByUserId,
    this.programId,
    this.blockId,
    this.programRunId,
    this.text,
    this.description,
    this.exerciseId,
    this.variationId,
    this.targetWeight,
    this.targetReps,
    this.targets = const [],
    this.targetDate,
    this.targetDateHistory = const [],
    this.createdDate,
  });

  final String goalId;
  final String userId;
  final String? createdByUserId;

  /// The program this goal belongs to. NULL = standalone (no program scope).
  final String? programId;

  /// The block this goal belongs to. NULL = the whole program.
  final String? blockId;

  /// The run it was created under, for goals that predate scoping. Goals are
  /// not bound to a run — a scope outlives every attempt at it.
  final String? programRunId;

  /// Free-text goal. Set when there's no exercise target.
  final String? text;

  /// Notes about the goal itself — why it matters, what to watch. Free text,
  /// edited in place from the focused goal sheet; NULL when there are none
  /// (blank is normalized away on write).
  final String? description;

  /// Exercise-specific target — which exercise, at what weight × reps.
  final String? exerciseId;

  /// The one variation this target is scoped to. NULL = the exercise
  /// performed with no variation — a scope of its own, not a wildcard.
  final String? variationId;

  final num? targetWeight;
  final int? targetReps;

  /// A multi-set goal's requirements, in the order they are listed and
  /// matched. Empty on a single-set goal — see [requirements] for the one
  /// reading that covers both shapes. Read from `fact_goal_target`; a row
  /// written before that table existed simply has none.
  final List<GoalTargetSet> targets;

  /// The day the goal should be hit by. NULL = no deadline — the goal is
  /// chased without a clock on it.
  final DateTime? targetDate;

  /// Every adjustment to [targetDate], oldest first. Empty = never moved.
  final List<GoalTargetDateChange> targetDateHistory;

  /// When the goal was said — stamped by the row at insert
  /// (`goal_created_date`, NOT NULL) and never edited (2026-10-19). Null only
  /// on a goal read out of a document that predates the column (a snapshot's
  /// copy), never on a row read from `fact_goal`.
  final DateTime? createdDate;

  bool get isExerciseGoal =>
      exerciseId != null ||
      targetWeight != null ||
      targetReps != null ||
      targets.isNotEmpty;

  /// Whether this goal lists more than one requirement — the shape the card,
  /// the sheet and the set form draw differently (2026-10-26).
  bool get isMultiSet => targets.isNotEmpty;

  /// The goal's requirements, whichever storage shape holds them: the child
  /// rows when there are any, otherwise the parent's single pair as a list of
  /// one. Empty when the goal names an exercise but no numbers at all (a
  /// "train bench more" goal) and for a free-text goal with no exercise.
  ///
  /// The one reading every consumer uses — evaluation, the card, the sheet —
  /// so none of them has to ask which shape it is holding.
  List<GoalTargetSet> get requirements {
    if (targets.isNotEmpty) return targets;
    if (targetWeight == null && targetReps == null) return const [];
    return [GoalTargetSet(weight: targetWeight, reps: targetReps)];
  }

  /// Whether this goal is chased while [blockId] runs.
  ///
  /// A program-level goal is in force through every block of its program; a
  /// block-level goal only while its own block does. Passing null (a blockless
  /// run) therefore yields exactly the program-level goals, which is what a
  /// blockless program has always shown.
  bool appliesDuring(String? blockId) =>
      this.blockId == null || this.blockId == blockId;

  factory Goal.fromMap(Map<String, dynamic> map) => Goal(
    goalId: map['goal_id'] as String,
    userId: map['user_id'] as String,
    createdByUserId: map['created_by_user_id'] as String?,
    programId: map['program_id'] as String?,
    blockId: map['block_id'] as String?,
    programRunId: map['program_run_id'] as String?,
    text: map['goal_text'] as String?,
    description: map['goal_description'] as String?,
    exerciseId: map['custom_exercise_id'] as String?,
    variationId: map['custom_variation_id'] as String?,
    targetWeight: _toNum(map['target_weight']),
    targetReps: _toInt(map['target_reps']),
    targetDate: parseGoalDate(map['target_date']),
    targetDateHistory: decodeGoalTargetDateHistory(
      map['target_date_history_json'] as String?,
    ),
    createdDate: parseGoalDate(map['goal_created_date']),
  );

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return double.tryParse('$v');
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Map<String, dynamic> toMap() => {
    'goal_id': goalId,
    'user_id': userId,
    'created_by_user_id': createdByUserId,
    'program_id': programId,
    'block_id': blockId,
    'program_run_id': programRunId,
    'goal_text': text,
    'goal_description': description,
    'custom_exercise_id': exerciseId,
    'custom_variation_id': variationId,
    'target_weight': targetWeight,
    'target_reps': targetReps,
    'target_date': targetDate?.toIso8601String(),
    'target_date_history_json': encodeGoalTargetDateHistory(targetDateHistory),
    'goal_created_date': createdDate?.toIso8601String(),
  };

  /// Replaces the description, or clears it — `clearDescription` exists because
  /// "set this to null" and "leave this alone" cannot both be spelled with a
  /// nullable parameter. Everything else is carried as-is: the description is
  /// the only field anything rewrites in place — the target date is rewritten
  /// from a row the repository read back, so it arrives whole.
  Goal copyWith({
    String? description,
    bool clearDescription = false,
    DateTime? targetDate,
    bool clearTargetDate = false,
    List<GoalTargetDateChange>? targetDateHistory,
  }) => Goal(
    goalId: goalId,
    userId: userId,
    programId: programId,
    blockId: blockId,
    programRunId: programRunId,
    text: text,
    description: clearDescription ? null : (description ?? this.description),
    exerciseId: exerciseId,
    variationId: variationId,
    targetWeight: targetWeight,
    targetReps: targetReps,
    targets: targets,
    targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
    targetDateHistory: targetDateHistory ?? this.targetDateHistory,
    createdDate: createdDate,
  );
}

/// One requirement of a goal — "this set or better": a set at or above this
/// weight AND this reps count (2026-10-26).
///
/// A single-set goal has one of these, read off the parent's columns. A
/// multi-set goal has several, stored as `fact_goal_target` rows; [order] is
/// the 1-based `target_set_order` the list is kept and matched in, and null
/// on the one derived from a single-set goal (where there is no row and no
/// order to remember).
class GoalTargetSet {
  const GoalTargetSet({this.order, this.weight, this.reps});

  final int? order;
  final num? weight;
  final int? reps;

  Map<String, dynamic> toMap() => {
    'order': order,
    'weight': weight,
    'reps': reps,
  };

  factory GoalTargetSet.fromMap(Map<String, dynamic> map) => GoalTargetSet(
    order: Goal._toInt(map['order']),
    weight: Goal._toNum(map['weight']),
    reps: Goal._toInt(map['reps']),
  );

  /// Equality by value — the sheet's dirty check compares a draft's parsed
  /// rows against the stored ones, and a fresh object with the same numbers
  /// must read as the same requirement ([order] is position, not content).
  @override
  bool operator ==(Object other) =>
      other is GoalTargetSet && other.weight == weight && other.reps == reps;

  @override
  int get hashCode => Object.hash(weight, reps);
}

/// One adjustment of a goal's target date — what it was, what it became, and
/// when it moved.
///
/// Stored on the goal row as `target_date_history_json` (oldest first) rather
/// than in a table of its own: the history belongs to the one goal, nothing
/// ever queries across goals' adjustments, and a synced table would be a lot
/// of choreography for a record only ever read back with its goal. A NULL
/// side is "no deadline" — setting one for the first time has no [from], and
/// clearing it has no [to].
class GoalTargetDateChange {
  const GoalTargetDateChange({this.from, this.to, required this.changedAt});

  /// The deadline before the adjustment; null when there was none.
  final DateTime? from;

  /// The deadline after it; null when the goal's deadline was cleared.
  final DateTime? to;

  final DateTime changedAt;

  Map<String, dynamic> toMap() => {
    'from': from?.toIso8601String(),
    'to': to?.toIso8601String(),
    'changed_at': changedAt.toIso8601String(),
  };

  factory GoalTargetDateChange.fromMap(Map<String, dynamic> map) =>
      GoalTargetDateChange(
        from: parseGoalDate(map['from']),
        to: parseGoalDate(map['to']),
        changedAt: parseGoalDate(map['changed_at']) ?? DateTime.now(),
      );
}

/// A goal date, as the columns store it — an ISO-8601 string. Kept
/// time-of-day-free by callers ([dateOnly]), so "the 5th" is the same day on
/// every device regardless of the hour it was picked.
DateTime? parseGoalDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}

/// The day [date] falls on, with the clock zeroed — what a target date means.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// The history as the column stores it; null when there is none, so "never
/// adjusted" has one spelling on the row.
String? encodeGoalTargetDateHistory(List<GoalTargetDateChange> history) =>
    history.isEmpty
    ? null
    : jsonEncode([for (final change in history) change.toMap()]);

/// Decodes the column, tolerating anything unreadable as "no history" — a
/// document written by a newer build must not stop the goal from opening.
List<GoalTargetDateChange> decodeGoalTargetDateHistory(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          GoalTargetDateChange.fromMap(entry.cast<String, dynamic>()),
    ];
  } catch (_) {
    return const [];
  }
}
