import 'dart:convert';

/// One logged set within a session (fact).
class SessionSet {
  const SessionSet({
    required this.sessionSetId,
    required this.sessionId,
    required this.userId,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    this.variationId,
    this.weight,
    this.notes,
    this.exerciseName,
    this.variationName,
    this.supersetGroupNumber,
    this.parentSetId,
  });

  final String sessionSetId;
  final String sessionId;
  final String userId;
  final String exerciseId;
  final String? variationId;
  final int setNumber;
  final double? weight;
  final List<num> reps;
  final String? notes;
  final String? exerciseName;
  final String? variationName;
  final int? supersetGroupNumber;
  final String? parentSetId;

  factory SessionSet.fromMap(Map<String, dynamic> map) => SessionSet(
        sessionSetId: map['session_set_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['set_number'] as int,
        weight: _toDouble(map['weight']),
        reps: _toNumList(map['reps']),
        notes: map['notes'] as String?,
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        supersetGroupNumber: map['superset_group_number'] as int?,
        parentSetId: map['parent_set_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_set_id': sessionSetId,
        'session_id': sessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
        'notes': notes,
        'superset_group_number': supersetGroupNumber,
        'exercise_name': exerciseName,
        'variation_name': variationName,
        'parent_set_id': parentSetId,
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
class PastSetRow extends SessionSet {
  const PastSetRow({
    required super.sessionSetId,
    required super.sessionId,
    required super.userId,
    required super.exerciseId,
    required super.setNumber,
    required super.reps,
    required this.sessionCreatedDate,
    super.variationId,
    super.weight,
    super.notes,
    super.exerciseName,
    super.variationName,
    super.supersetGroupNumber,
    super.parentSetId,
  });

  final DateTime sessionCreatedDate;

  factory PastSetRow.fromMap(Map<String, dynamic> map) => PastSetRow(
        sessionSetId: map['session_set_id'] as String,
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        setNumber: map['set_number'] as int,
        weight: SessionSet._toDouble(map['weight']),
        reps: SessionSet._toNumList(map['reps']),
        notes: map['notes'] as String?,
        sessionCreatedDate: DateTime.parse(map['created_date'] as String),
        exerciseName: map['exercise_name'] as String?,
        variationName: map['variation_name'] as String?,
        supersetGroupNumber: map['superset_group_number'] as int?,
        parentSetId: map['parent_set_id'] as String?,
      );
}
