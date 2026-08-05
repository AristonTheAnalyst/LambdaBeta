/// A program goal — either free text, or an exercise-specific target
/// (e.g. "bench 100kg × 1").
class ProgramGoal {
  const ProgramGoal({
    required this.goalId,
    required this.programId,
    required this.userId,
    this.text,
    this.exerciseId,
    this.targetWeight,
    this.targetReps,
  });

  final String goalId;
  final String programId;
  final String userId;

  /// Free-text goal. Set when there's no exercise target.
  final String? text;

  /// Exercise-specific target — which exercise, at what weight × reps.
  final String? exerciseId;
  final num? targetWeight;
  final int? targetReps;

  bool get isExerciseGoal =>
      exerciseId != null || targetWeight != null || targetReps != null;

  factory ProgramGoal.fromMap(Map<String, dynamic> map) => ProgramGoal(
        goalId: map['program_goal_id'] as String,
        programId: map['program_id'] as String,
        userId: map['user_id'] as String,
        text: map['goal_text'] as String?,
        exerciseId: map['custom_exercise_id'] as String?,
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
        'program_goal_id': goalId,
        'program_id': programId,
        'user_id': userId,
        'goal_text': text,
        'custom_exercise_id': exerciseId,
        'target_weight': targetWeight,
        'target_reps': targetReps,
      };
}
