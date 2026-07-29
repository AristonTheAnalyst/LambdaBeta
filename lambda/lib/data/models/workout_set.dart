import 'dart:convert';

class WorkoutSet {
  const WorkoutSet({
    required this.setId,
    required this.workoutId,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.duration,
    this.variationId,
    this.weight,
    this.notes,
    this.exerciseName,
    this.variationName,
    this.supersetGroupNumber,
  });

  final String setId;
  final String workoutId;
  final String exerciseId;
  final String? variationId;
  final int setNumber;
  final double? weight;
  final List<num> reps;
  final List<num> duration;
  final String? notes;
  final String? exerciseName;
  final String? variationName;
  final int? supersetGroupNumber;

  factory WorkoutSet.fromMap(Map<String, dynamic> map) => WorkoutSet(
        setId: map['workout_set_id'] as String,
        workoutId: map['user_workout_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['workout_set_number'] as int,
        weight: _toDouble(map['workout_set_weight']),
        reps: _toNumList(map['workout_set_reps']),
        duration: _toNumList(map['workout_set_duration_seconds']),
        notes: map['workout_set_notes'] as String?,
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        supersetGroupNumber: map['superset_group_number'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'workout_set_id': setId,
        'user_workout_id': workoutId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'workout_set_number': setNumber,
        'workout_set_weight': weight,
        'workout_set_reps': reps,
        'workout_set_duration_seconds': duration,
        'workout_set_notes': notes,
        'superset_group_number': supersetGroupNumber,
      };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static List<num> _toNumList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<num>();
    if (value is String) {
      try {
        return (jsonDecode(value) as List).cast<num>();
      } catch (_) {
        return [];
      }
    }
    return [];
  }
}

class PastSetRow extends WorkoutSet {
  const PastSetRow({
    required super.setId,
    required super.workoutId,
    required super.exerciseId,
    required super.setNumber,
    required super.reps,
    required super.duration,
    required this.workoutCreatedDate,
    super.variationId,
    super.weight,
    super.notes,
    super.exerciseName,
    super.variationName,
    super.supersetGroupNumber,
  });

  final DateTime workoutCreatedDate;

  factory PastSetRow.fromMap(Map<String, dynamic> map) => PastSetRow(
        setId: map['workout_set_id'] as String,
        workoutId: map['user_workout_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['workout_set_number'] as int,
        weight: WorkoutSet._toDouble(map['workout_set_weight']),
        reps: WorkoutSet._toNumList(map['workout_set_reps']),
        duration: WorkoutSet._toNumList(map['workout_set_duration_seconds']),
        notes: map['workout_set_notes'] as String?,
        workoutCreatedDate: DateTime.parse(map['user_workout_created_date'] as String),
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        supersetGroupNumber: map['superset_group_number'] as int?,
      );
}
