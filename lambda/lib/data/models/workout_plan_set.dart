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
      );

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
