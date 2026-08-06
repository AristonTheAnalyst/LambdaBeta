import 'dart:convert';

/// A planned set within a standalone workout — mirrors PlannedSet but keyed to
/// a dim_workout row.
class WorkoutPlanSet {
  const WorkoutPlanSet({
    required this.setId,
    required this.workoutId,
    required this.userId,
    required this.exerciseId,
    required this.exerciseSequenceOrder,
    required this.setNumber,
    this.variationId,
    this.targetWeight,
    this.targetReps = const [],
    this.targetDuration = const [],
    this.targetNotes,
    this.exerciseName,
    this.variationName,
    this.isActive = true,
  });

  final String setId;
  final String workoutId;
  final String userId;
  final String exerciseId;
  final int exerciseSequenceOrder;
  final int setNumber;
  final String? variationId;
  final num? targetWeight;
  final List<num> targetReps;
  final List<num> targetDuration;
  final String? targetNotes;
  final String? exerciseName;
  final String? variationName;
  final bool isActive;

  factory WorkoutPlanSet.fromMap(Map<String, dynamic> map) => WorkoutPlanSet(
        setId: map['workout_set_id'] as String,
        workoutId: map['workout_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        exerciseSequenceOrder: map['exercise_sequence_order'] as int,
        setNumber: map['workout_set_number'] as int,
        variationId: map['custom_variation_id'] as String?,
        targetWeight: _toNum(map['target_weight']),
        targetReps: _toNumList(map['target_reps']),
        targetDuration: _toNumList(map['target_duration_seconds']),
        targetNotes: map['target_notes'] as String?,
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        isActive: _toBool(map['is_active']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'workout_set_id': setId,
        'workout_id': workoutId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'exercise_sequence_order': exerciseSequenceOrder,
        'workout_set_number': setNumber,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_duration_seconds': targetDuration,
        'target_notes': targetNotes,
        'exercise_name': exerciseName,
        'variation_name': variationName,
        'is_active': isActive,
      };

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return double.tryParse('$v');
  }

  static List<num> _toNumList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => num.parse('$e')).toList();
    final s = '$v';
    if (s.isEmpty) return const [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) return decoded.map((e) => num.parse('$e')).toList();
    } catch (_) {}
    return const [];
  }
}
