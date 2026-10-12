import 'dart:convert';

/// A planned target set within a planned session exercise group. The exercise
/// lives one level up; [exerciseId] and [exerciseName] are hydrated from the
/// parent row by the repository JOINs.
class PlannedSessionExerciseSet {
  const PlannedSessionExerciseSet({
    required this.plannedSetId,
    required this.plannedExerciseId,
    required this.plannedSessionId,
    required this.userId,
    required this.setNumber,
    this.exerciseId,
    this.variationId,
    this.targetWeight,
    this.targetReps,
    this.targetNotes,
    this.exerciseName,
    this.variationName,
    this.isArchived = false,
  });

  final String plannedSetId;
  final String plannedExerciseId;
  final String plannedSessionId;
  final String userId;
  final String? exerciseId;
  final String? variationId;
  final int setNumber;

  /// Raw planned weight text — "60" or a range like "60-70". Free text by
  /// design: a planned value is a hint, not a literal.
  final String? targetWeight;

  /// Raw planned reps text — "10" or a range like "8-15". Same semantics.
  final String? targetReps;

  final String? targetNotes;
  final String? exerciseName;
  final String? variationName;
  final bool isArchived;

  /// The same target row, renumbered. Everything but the row's position is
  /// untouched — a reorder moves sets, it never edits them.
  PlannedSessionExerciseSet copyWith({int? setNumber}) =>
      PlannedSessionExerciseSet(
        plannedSetId: plannedSetId,
        plannedExerciseId: plannedExerciseId,
        plannedSessionId: plannedSessionId,
        userId: userId,
        setNumber: setNumber ?? this.setNumber,
        exerciseId: exerciseId,
        variationId: variationId,
        targetWeight: targetWeight,
        targetReps: targetReps,
        targetNotes: targetNotes,
        exerciseName: exerciseName,
        variationName: variationName,
        isArchived: isArchived,
      );

  factory PlannedSessionExerciseSet.fromMap(Map<String, dynamic> map) =>
      PlannedSessionExerciseSet(
        plannedSetId: map['planned_set_id'] as String,
        plannedExerciseId: map['planned_exercise_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
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
        'planned_set_id': plannedSetId,
        'planned_exercise_id': plannedExerciseId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'set_number': setNumber,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_notes': targetNotes,
        'exercise_name': exerciseName,
        'variation_name': variationName,
        'is_archived': isArchived,
      };
}
