import 'planned_set.dart';

class PlannedWorkout {
  const PlannedWorkout({
    required this.plannedWorkoutId,
    required this.programId,
    required this.userId,
    required this.name,
    required this.sequenceOrder,
    required this.isActive,
    this.notes,
    this.dayOfWeek,
  });

  final String plannedWorkoutId;
  final String programId;
  final String userId;
  final String name;
  final String? notes;
  final int sequenceOrder;
  // 1=Monday..7=Sunday (ISO weekday). Only meaningful when the parent
  // program's progressionMode is 'calendar'.
  final int? dayOfWeek;
  final bool isActive;

  factory PlannedWorkout.fromMap(Map<String, dynamic> map) => PlannedWorkout(
        plannedWorkoutId: map['planned_workout_id'] as String,
        programId: map['program_id'] as String,
        userId: map['user_id'] as String,
        name: map['planned_workout_name'] as String,
        notes: map['planned_workout_notes'] as String?,
        sequenceOrder: _toInt(map['sequence_order']) ?? 0,
        dayOfWeek: _toInt(map['day_of_week']),
        isActive: _toBool(map['is_active']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Map<String, dynamic> toMap() => {
        'planned_workout_id': plannedWorkoutId,
        'program_id': programId,
        'user_id': userId,
        'planned_workout_name': name,
        'planned_workout_notes': notes,
        'sequence_order': sequenceOrder,
        'day_of_week': dayOfWeek,
        'is_active': isActive,
      };
}

class PlannedWorkoutWithSets {
  const PlannedWorkoutWithSets({required this.plannedWorkout, required this.plannedSets});
  final PlannedWorkout plannedWorkout;
  final List<PlannedSet> plannedSets;
}
