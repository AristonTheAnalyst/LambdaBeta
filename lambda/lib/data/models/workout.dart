import 'workout_set.dart';

class Workout {
  const Workout({
    required this.workoutId,
    required this.userId,
    required this.createdDate,
    required this.isActive,
    this.preNotes,
    this.postNotes,
    this.preFeeling,
    this.programId,
    this.plannedWorkoutId,
    this.plannedWorkoutName,
    this.exerciseOrder,
  });

  final String workoutId;
  final String userId;
  final String? preNotes;
  final String? postNotes;
  final DateTime createdDate;
  final bool isActive;
  final int? preFeeling;
  final String? programId;
  final String? plannedWorkoutId;
  final String? plannedWorkoutName;

  /// JSON string of the session's exercise tab slots (order + superset
  /// grouping), so the tab bar survives a hot restart.
  final String? exerciseOrder;

  factory Workout.fromMap(Map<String, dynamic> map) => Workout(
        workoutId: map['user_workout_id'] as String,
        userId: map['user_id'] as String,
        preNotes: map['user_pre_workout_notes'] as String?,
        postNotes: map['user_post_workout_notes'] as String?,
        createdDate: DateTime.parse(map['user_workout_created_date'] as String),
        isActive: _toBool(map['is_active']),
        preFeeling: map['pre_workout_feeling'] as int?,
        programId: map['program_id'] as String?,
        plannedWorkoutId: map['planned_workout_id'] as String?,
        plannedWorkoutName: map['planned_workout_name'] as String?,
        exerciseOrder: map['exercise_order'] as String?,
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  Map<String, dynamic> toMap() => {
        'user_workout_id': workoutId,
        'user_id': userId,
        'user_pre_workout_notes': preNotes,
        'user_post_workout_notes': postNotes,
        'user_workout_created_date': createdDate.toIso8601String(),
        'is_active': isActive,
        'pre_workout_feeling': preFeeling,
      };
}

class WorkoutWithSets {
  const WorkoutWithSets({required this.workout, required this.sets});
  final Workout workout;
  final List<WorkoutSet> sets;
}
