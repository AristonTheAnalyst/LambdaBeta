import 'dart:convert';

class PlannedSet {
  const PlannedSet({
    required this.plannedSetId,
    required this.plannedWorkoutId,
    required this.userId,
    required this.exerciseId,
    required this.exerciseSequenceOrder,
    required this.setNumber,
    required this.targetReps,
    required this.targetDuration,
    required this.isActive,
    this.variationId,
    this.targetWeight,
    this.targetNotes,
    this.exerciseName,
    this.variationName,
  });

  final String plannedSetId;
  final String plannedWorkoutId;
  final String userId;
  final String exerciseId;
  final String? variationId;
  final int exerciseSequenceOrder;
  final int setNumber;
  final double? targetWeight;
  final List<num> targetReps;
  final List<num> targetDuration;
  final String? targetNotes;
  final bool isActive;
  final String? exerciseName;
  final String? variationName;

  factory PlannedSet.fromMap(Map<String, dynamic> map) => PlannedSet(
        plannedSetId: map['planned_set_id'] as String,
        plannedWorkoutId: map['planned_workout_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        exerciseSequenceOrder: _toInt(map['exercise_sequence_order']) ?? 0,
        setNumber: _toInt(map['planned_set_number']) ?? 1,
        targetWeight: _toDouble(map['target_weight']),
        targetReps: _toNumList(map['target_reps']),
        targetDuration: _toNumList(map['target_duration_seconds']),
        targetNotes: map['target_notes'] as String?,
        isActive: _toBool(map['is_active']),
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'planned_set_id': plannedSetId,
        'planned_workout_id': plannedWorkoutId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'exercise_sequence_order': exerciseSequenceOrder,
        'planned_set_number': setNumber,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_duration_seconds': targetDuration,
        'target_notes': targetNotes,
        'is_active': isActive,
      };

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
