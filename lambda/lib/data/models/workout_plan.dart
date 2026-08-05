/// A standalone planned workout — a single session not tied to a program.
/// Mirrors dim_planned_workout but lives in its own table.
class WorkoutPlan {
  const WorkoutPlan({
    required this.workoutId,
    required this.userId,
    required this.name,
    required this.isActive,
    required this.createdDate,
    this.notes,
  });

  final String workoutId;
  final String userId;
  final String name;
  final String? notes;
  final bool isActive;
  final DateTime createdDate;

  factory WorkoutPlan.fromMap(Map<String, dynamic> map) => WorkoutPlan(
        workoutId: map['workout_id'] as String,
        userId: map['user_id'] as String,
        name: map['workout_name'] as String,
        notes: map['workout_notes'] as String?,
        isActive: _toBool(map['is_active']),
        createdDate: DateTime.parse(map['workout_created_date'] as String),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'workout_id': workoutId,
        'user_id': userId,
        'workout_name': name,
        'workout_notes': notes,
        'is_active': isActive,
        'workout_created_date': createdDate.toIso8601String(),
      };
}
