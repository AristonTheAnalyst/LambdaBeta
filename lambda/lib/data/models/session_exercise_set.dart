import 'dart:convert';

/// One logged set within a session (fact_session_exercise_set). Its exercise
/// lives one level up on fact_session_exercise; [exerciseId] and
/// [exerciseName] are hydrated from the parent row by the repository JOINs so
/// consumers don't need to re-join.
class SessionExerciseSet {
  const SessionExerciseSet({
    required this.sessionExerciseSetId,
    required this.sessionExerciseId,
    required this.sessionId,
    required this.userId,
    required this.setNumber,
    required this.reps,
    this.exerciseId,
    this.variationId,
    this.weight,
    this.notes,
    this.exerciseName,
    this.variationName,
    this.plannedSetId,
  });

  final String sessionExerciseSetId;
  final String sessionExerciseId;
  final String sessionId;
  final String userId;
  final String? exerciseId;
  final String? variationId;
  final int setNumber;
  final double? weight;
  final List<num> reps;
  final String? notes;
  final String? exerciseName;
  final String? variationName;

  /// Plain ref to the template row (dim_planned_session_exercise_set) this
  /// set was materialized from — the ghost-hint anchor.
  final String? plannedSetId;

  /// The same set, renumbered. Everything but the row's position is
  /// untouched — a reorder moves sets, it never edits them.
  SessionExerciseSet copyWith({int? setNumber}) => SessionExerciseSet(
        sessionExerciseSetId: sessionExerciseSetId,
        sessionExerciseId: sessionExerciseId,
        sessionId: sessionId,
        userId: userId,
        setNumber: setNumber ?? this.setNumber,
        reps: reps,
        exerciseId: exerciseId,
        variationId: variationId,
        weight: weight,
        notes: notes,
        exerciseName: exerciseName,
        variationName: variationName,
        plannedSetId: plannedSetId,
      );

  factory SessionExerciseSet.fromMap(Map<String, dynamic> map) =>
      SessionExerciseSet(
        sessionExerciseSetId: map['session_exercise_set_id'] as String,
        sessionExerciseId: map['session_exercise_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['set_number'] as int,
        weight: _toDouble(map['weight']),
        reps: _toNumList(map['reps']),
        notes: map['notes'] as String?,
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        plannedSetId: map['planned_set_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_exercise_set_id': sessionExerciseSetId,
        'session_exercise_id': sessionExerciseId,
        'session_id': sessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
        'notes': notes,
        'exercise_name': exerciseName,
        'variation_name': variationName,
        'planned_set_id': plannedSetId,
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

/// A logged set joined with its session's created date, for the
/// per-exercise history timeline.
class PastSetRow extends SessionExerciseSet {
  const PastSetRow({
    required super.sessionExerciseSetId,
    required super.sessionExerciseId,
    required super.sessionId,
    required super.userId,
    required super.setNumber,
    required super.reps,
    required this.sessionCreatedDate,
    super.exerciseId,
    super.variationId,
    super.weight,
    super.notes,
    super.exerciseName,
    super.variationName,
    super.plannedSetId,
  });

  final DateTime sessionCreatedDate;

  factory PastSetRow.fromMap(Map<String, dynamic> map) => PastSetRow(
        sessionExerciseSetId: map['session_exercise_set_id'] as String,
        sessionExerciseId: map['session_exercise_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['set_number'] as int,
        weight: SessionExerciseSet._toDouble(map['weight']),
        reps: SessionExerciseSet._toNumList(map['reps']),
        notes: map['notes'] as String?,
        sessionCreatedDate: DateTime.parse(map['created_datetime'] as String),
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        plannedSetId: map['planned_set_id'] as String?,
      );
}
