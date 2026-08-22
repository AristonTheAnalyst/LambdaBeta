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
    this.targetReps,
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

  /// Raw planned weight text — "60" or a range like "60-70". Free text by
  /// design: a planned value is a hint, not a literal.
  final String? targetWeight;

  /// Raw planned reps text — "10" or a range like "8-15". Same semantics.
  final String? targetReps;

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
        targetWeight: _toTargetText(map['target_weight']),
        targetReps: _toTargetText(map['target_reps']),
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

  /// Normalizes a planned-target column to its raw text form. Handles the
  /// legacy formats: numeric weights written as "60.0", and reps stored as
  /// JSON arrays ("[3]" or "[8,10]" → "8,10").
  static String? _toTargetText(dynamic v) {
    if (v == null) return null;
    var s = '$v'.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('[')) {
      try {
        final list = (jsonDecode(s) as List).cast<dynamic>();
        if (list.isEmpty) return null;
        return list.join(',');
      } catch (_) {
        return s;
      }
    }
    // Legacy numeric writes came through as "60.0" — strip the trailing .0.
    if (s.contains('.') && num.tryParse(s) != null) {
      s = s.replaceFirst(RegExp(r'\.0+$'), '');
    }
    return s;
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
    'target_notes': targetNotes,
    'exercise_name': exerciseName,
    'variation_name': variationName,
    'is_archived': isArchived,
  };
}
