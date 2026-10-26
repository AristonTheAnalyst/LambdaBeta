/// A coach's note on one of an athlete's completed sessions (2026-10-26, #24).
///
/// One row per (coach, session). Both parties read it — the coach when they
/// open the athlete's record, the athlete on their own — and only its author
/// writes it. [editedDate] is stamped when the coach rewrites [body].
class CoachFeedback {
  const CoachFeedback({
    required this.feedbackId,
    required this.coachUserId,
    required this.athleteUserId,
    required this.sessionId,
    required this.body,
    this.createdDate,
    this.editedDate,
  });

  final String feedbackId;
  final String coachUserId;
  final String athleteUserId;
  final String sessionId;
  final String body;
  final DateTime? createdDate;
  final DateTime? editedDate;

  /// The date to draw: the rewrite when there is one, else the first write.
  DateTime? get displayDate => editedDate ?? createdDate;

  bool get isEdited => editedDate != null;

  factory CoachFeedback.fromMap(Map<String, dynamic> map) => CoachFeedback(
    feedbackId: map['feedback_id'] as String,
    coachUserId: map['coach_user_id'] as String,
    athleteUserId: map['athlete_user_id'] as String,
    sessionId: map['session_id'] as String,
    body: (map['body'] as String?) ?? '',
    createdDate: _date(map['created_date']),
    editedDate: _date(map['edited_date']),
  );

  Map<String, dynamic> toMap() => {
    'feedback_id': feedbackId,
    'coach_user_id': coachUserId,
    'athlete_user_id': athleteUserId,
    'session_id': sessionId,
    'body': body,
    'created_date': createdDate?.toUtc().toIso8601String(),
    'edited_date': editedDate?.toUtc().toIso8601String(),
  };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
