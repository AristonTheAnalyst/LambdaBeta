/// One exercise group within a planned session (dim). Target sets hang off
/// this row via dim_planned_session_exercise_set.
class PlannedSessionExercise {
  const PlannedSessionExercise({
    required this.plannedExerciseId,
    required this.plannedSessionId,
    required this.userId,
    required this.exerciseOrder,
    this.exerciseId,
    this.exerciseName,
    this.isArchived = false,
  });

  final String plannedExerciseId;
  final String plannedSessionId;
  final String userId;
  final String? exerciseId;
  final int exerciseOrder;
  final String? exerciseName;
  final bool isArchived;

  factory PlannedSessionExercise.fromMap(Map<String, dynamic> map) =>
      PlannedSessionExercise(
        plannedExerciseId: map['planned_exercise_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        exerciseOrder: _toInt(map['exercise_order']) ?? 0,
        exerciseName: map['exercise_name'] as String?,
        isArchived: _toBool(map['is_archived']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Map<String, dynamic> toMap() => {
        'planned_exercise_id': plannedExerciseId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'exercise_order': exerciseOrder,
        'exercise_name': exerciseName,
        'is_archived': isArchived,
      };
}
