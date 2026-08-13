class RestPeriod {
  const RestPeriod({
    required this.restId,
    required this.userId,
    required this.sessionId,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.createdDate,
    this.exerciseId,
  });

  final String restId;
  final String userId;
  final String sessionId;
  final String? exerciseId;
  final int plannedSeconds;
  final int actualSeconds;
  final DateTime createdDate;

  factory RestPeriod.fromMap(Map<String, dynamic> map) => RestPeriod(
        restId: map['rest_id'] as String,
        userId: map['user_id'] as String,
        sessionId: map['session_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        plannedSeconds: map['planned_seconds'] as int,
        actualSeconds: map['actual_seconds'] as int,
        createdDate: DateTime.parse(map['rest_created_date'] as String),
      );

  Map<String, dynamic> toMap() => {
        'rest_id': restId,
        'user_id': userId,
        'session_id': sessionId,
        'custom_exercise_id': exerciseId,
        'planned_seconds': plannedSeconds,
        'actual_seconds': actualSeconds,
        'rest_created_date': createdDate.toIso8601String(),
      };
}
