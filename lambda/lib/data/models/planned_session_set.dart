import 'dart:convert';

/// A planned set within a planned session (template target row).
class PlannedSessionSet {
  const PlannedSessionSet({
    required this.setId,
    required this.sessionId,
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
    this.isArchived = false,
  });

  final String setId;
  final String sessionId;
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
  final bool isArchived;

  factory PlannedSessionSet.fromMap(Map<String, dynamic> map) =>
      PlannedSessionSet(
        setId: map['set_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        exerciseSequenceOrder: _toInt(map['exercise_sequence_order']) ?? 0,
        setNumber: _toInt(map['set_number']) ?? 1,
        variationId: map['custom_variation_id'] as String?,
        targetWeight: _toNum(map['target_weight']),
        targetReps: _toNumList(map['target_reps']),
        targetDuration: _toNumList(map['target_duration_seconds']),
        targetNotes: map['target_notes'] as String?,
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        isArchived: _toBool(map['is_archived']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse('$v');
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

  Map<String, dynamic> toMap() => {
        'set_id': setId,
        'session_id': sessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'exercise_sequence_order': exerciseSequenceOrder,
        'set_number': setNumber,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_duration_seconds': targetDuration,
        'target_notes': targetNotes,
        'exercise_name': exerciseName,
        'variation_name': variationName,
        'is_archived': isArchived,
      };
}
