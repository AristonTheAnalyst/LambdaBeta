class ExerciseNote {
  const ExerciseNote({
    required this.exerciseNoteId,
    required this.userId,
    this.createdByUserId,
    required this.exerciseId,
    required this.text,
    required this.pinned,
    required this.createdDate,
    this.sessionId,
  });

  final String exerciseNoteId;
  final String userId;
  final String? createdByUserId;
  final String exerciseId;
  final String text;
  final bool pinned;
  final DateTime createdDate;

  /// The logged session this note was created in (null when created
  /// while planning a session template).
  final String? sessionId;

  factory ExerciseNote.fromMap(Map<String, dynamic> map) => ExerciseNote(
    exerciseNoteId: map['exercise_note_id'] as String,
    userId: map['user_id'] as String,
    createdByUserId: map['created_by_user_id'] as String?,
    exerciseId: map['custom_exercise_id'] as String,
    text: map['note_text'] as String,
    pinned: _toBool(map['pinned']),
    createdDate: DateTime.parse(map['note_created_date'] as String),
    sessionId: map['session_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'exercise_note_id': exerciseNoteId,
    'user_id': userId,
    'created_by_user_id': createdByUserId,
    'custom_exercise_id': exerciseId,
    'note_text': text,
    'pinned': pinned,
    'note_created_date': createdDate.toIso8601String(),
    'session_id': sessionId,
  };

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }
}
