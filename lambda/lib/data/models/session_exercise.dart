/// One exercise tab within a logged session (fact). The layer between
/// fact_session and fact_session_exercise_set — sets hang off this row, and
/// the exercise (nullable for a free tab) lives here instead of on every set.
class SessionExercise {
  const SessionExercise({
    required this.sessionExerciseId,
    required this.sessionId,
    required this.userId,
    required this.exerciseOrder,
    this.exerciseId,
    this.exerciseName,
    this.plannedExerciseId,
  });

  final String sessionExerciseId;
  final String sessionId;
  final String userId;
  final String? exerciseId;
  final int exerciseOrder;
  final String? exerciseName;
  final String? plannedExerciseId;

  factory SessionExercise.fromMap(Map<String, dynamic> map) => SessionExercise(
        sessionExerciseId: map['session_exercise_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        exerciseOrder: map['exercise_order'] as int,
        exerciseName: map['exercise_name'] as String?,
        plannedExerciseId: map['planned_exercise_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_exercise_id': sessionExerciseId,
        'session_id': sessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'exercise_order': exerciseOrder,
        'exercise_name': exerciseName,
        'planned_exercise_id': plannedExerciseId,
      };
}
