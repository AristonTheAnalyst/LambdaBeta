import 'workout_set.dart';

class Workout {
  const Workout({
    required this.workoutId,
    required this.userId,
    required this.createdDate,
    required this.isActive,
    this.preNotes,
    this.postNotes,
  });

  final String workoutId;
  final String userId;
  final String? preNotes;
  final String? postNotes;
  final DateTime createdDate;
  final bool isActive;

  factory Workout.fromMap(Map<String, dynamic> map) => Workout(
        workoutId: map['user_workout_id'] as String,
        userId: map['user_id'] as String,
        preNotes: map['user_pre_workout_notes'] as String?,
        postNotes: map['user_post_workout_notes'] as String?,
        createdDate: DateTime.parse(map['user_workout_created_date'] as String),
        isActive: _toBool(map['is_active']),
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
      };
}

class WorkoutWithSets {
  const WorkoutWithSets({required this.workout, required this.sets});
  final Workout workout;
  final List<WorkoutSet> sets;
}
