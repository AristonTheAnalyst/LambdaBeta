/// A goal — either free text, or an exercise-specific target
/// (e.g. "bench 100kg × 1"), scoped to a program or to a block of one.
///
/// Scope, not ownership: a program-level goal is chased through every run of
/// that program, and a block-level goal through every run of that block. That
/// is the point of the split — "8 weeks of accumulation" is a phase you might
/// run twice, and the target belongs to the phase, not to one attempt at it.
///
/// There is no `achievedDate`. Achievement is a per-run fact, so a single
/// column could not express "achieved in Block 1, missed in Block 3"; the
/// outcome is frozen per run into the close review instead. While a run is
/// open it is derived — see [evaluateGoals].
class Goal {
  const Goal({
    required this.goalId,
    required this.userId,
    this.programId,
    this.blockId,
    this.programRunId,
    this.text,
    this.exerciseId,
    this.variationId,
    this.targetWeight,
    this.targetReps,
  });

  final String goalId;
  final String userId;

  /// The program this goal belongs to. NULL = standalone (no program scope).
  final String? programId;

  /// The block this goal belongs to. NULL = the whole program.
  final String? blockId;

  /// The run it was created under, for goals that predate scoping. Goals are
  /// not bound to a run — a scope outlives every attempt at it.
  final String? programRunId;

  /// Free-text goal. Set when there's no exercise target.
  final String? text;

  /// Exercise-specific target — which exercise, at what weight × reps.
  final String? exerciseId;

  /// The one variation this target is scoped to. NULL = the exercise
  /// performed with no variation — a scope of its own, not a wildcard.
  final String? variationId;

  final num? targetWeight;
  final int? targetReps;

  bool get isExerciseGoal =>
      exerciseId != null || targetWeight != null || targetReps != null;

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
        programId: map['program_id'] as String?,
        blockId: map['block_id'] as String?,
        programRunId: map['program_run_id'] as String?,
        text: map['goal_text'] as String?,
        exerciseId: map['custom_exercise_id'] as String?,
        variationId: map['custom_variation_id'] as String?,
        targetWeight: _toNum(map['target_weight']),
        targetReps: _toInt(map['target_reps']),
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
        'program_id': programId,
        'block_id': blockId,
        'program_run_id': programRunId,
        'goal_text': text,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'target_weight': targetWeight,
        'target_reps': targetReps,
      };
}
