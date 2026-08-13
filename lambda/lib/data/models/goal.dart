/// A goal — either free text, or an exercise-specific target
/// (e.g. "bench 100kg × 1"). Independent of programs; optionally
/// linked to a program run.
class Goal {
  const Goal({
    required this.goalId,
    required this.userId,
    this.programRunId,
    this.text,
    this.exerciseId,
    this.targetWeight,
    this.targetReps,
    this.achievedDate,
  });

  final String goalId;
  final String userId;

  /// Optional link to the run this goal was created for.
  final String? programRunId;

  /// Free-text goal. Set when there's no exercise target.
  final String? text;

  /// Exercise-specific target — which exercise, at what weight × reps.
  final String? exerciseId;
  final num? targetWeight;
  final int? targetReps;

  /// When the goal was achieved (null = still chasing).
  final DateTime? achievedDate;

  bool get isExerciseGoal =>
      exerciseId != null || targetWeight != null || targetReps != null;

  bool get isAchieved => achievedDate != null;

  factory Goal.fromMap(Map<String, dynamic> map) => Goal(
        goalId: map['goal_id'] as String,
        userId: map['user_id'] as String,
        programRunId: map['program_run_id'] as String?,
        text: map['goal_text'] as String?,
        exerciseId: map['custom_exercise_id'] as String?,
        targetWeight: _toNum(map['target_weight']),
        targetReps: _toInt(map['target_reps']),
        achievedDate: map['achieved_date'] != null
            ? DateTime.tryParse(map['achieved_date'] as String)
            : null,
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
        'program_run_id': programRunId,
        'goal_text': text,
        'custom_exercise_id': exerciseId,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'achieved_date': achievedDate?.toIso8601String(),
      };
}
