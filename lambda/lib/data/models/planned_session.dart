/// A planned session — a session template. Standalone when no
/// dim_planned_session_program row references it; program membership and
/// schedule slots (sequence/day) live on the join table.
class PlannedSession {
  const PlannedSession({
    required this.sessionId,
    required this.userId,
    required this.name,
    this.notes,
    this.archivedDate,
    this.createdDate,
  });

  final String sessionId;
  final String userId;
  final String name;
  final String? notes;

  /// NULL = active; a timestamp = archived (sortable, latest first).
  final DateTime? archivedDate;

  bool get isArchived => archivedDate != null;

  final DateTime? createdDate;

  factory PlannedSession.fromMap(Map<String, dynamic> map) => PlannedSession(
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        notes: map['notes'] as String?,
        archivedDate: map['date_archived'] != null
            ? DateTime.tryParse(map['date_archived'] as String)
            : null,
        createdDate: map['created_date'] != null
            ? DateTime.tryParse(map['created_date'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'name': name,
        'notes': notes,
        'date_archived': archivedDate?.toIso8601String(),
        'created_date': createdDate?.toIso8601String(),
      };
}
