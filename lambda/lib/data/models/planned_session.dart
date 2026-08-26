/// A planned session — a session template. Standalone when no
/// dim_planned_session_program row references it; program membership and
/// schedule slots (sequence/day) live on the join table.
class PlannedSession {
  const PlannedSession({
    required this.sessionId,
    required this.userId,
    required this.name,
    required this.isArchived,
    this.notes,
    this.createdDate,
  });

  final String sessionId;
  final String userId;
  final String name;
  final String? notes;
  final bool isArchived;
  final DateTime? createdDate;

  factory PlannedSession.fromMap(Map<String, dynamic> map) => PlannedSession(
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        notes: map['notes'] as String?,
        isArchived: _toBool(map['is_archived']),
        createdDate: map['created_date'] != null
            ? DateTime.tryParse(map['created_date'] as String)
            : null,
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'name': name,
        'notes': notes,
        'is_archived': isArchived,
        'created_date': createdDate?.toIso8601String(),
      };
}
