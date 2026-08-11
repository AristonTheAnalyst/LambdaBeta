/// A planned workout — either standalone (program_id = null) or attached to a
/// program. Lives in dim_workout; the program_id / sequence_order / day_of_week
/// columns link it to a program when present.
class WorkoutPlan {
  const WorkoutPlan({
    required this.workoutId,
    required this.userId,
    required this.name,
    required this.isActive,
    required this.createdDate,
    this.notes,
    this.programId,
    this.sequenceOrder,
    this.dayOfWeek,
  });

  final String workoutId;
  final String userId;
  final String name;
  final String? notes;
  final bool isActive;
  final DateTime createdDate;
  final String? programId;
  final int? sequenceOrder;
  final int? dayOfWeek;

  factory WorkoutPlan.fromMap(Map<String, dynamic> map) => WorkoutPlan(
        workoutId: map['workout_id'] as String,
        userId: map['user_id'] as String,
        name: map['workout_name'] as String,
        notes: map['workout_notes'] as String?,
        isActive: _toBool(map['is_active']),
        createdDate: DateTime.parse(map['workout_created_date'] as String),
        programId: map['program_id'] as String?,
        sequenceOrder: map['sequence_order'] as int?,
        dayOfWeek: map['day_of_week'] as int?,
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
        'program_id': programId,
        'sequence_order': sequenceOrder,
        'day_of_week': dayOfWeek,
      };
}
