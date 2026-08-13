/// A planned session — a session template. Either standalone
/// (program_id = null) or attached to a program via the
/// program_id / sequence_order / day_of_week columns.
class PlannedSession {
  const PlannedSession({
    required this.sessionId,
    required this.userId,
    required this.name,
    required this.isArchived,
    this.notes,
    this.programId,
    this.sequenceOrder,
    this.dayOfWeek,
    this.createdDate,
  });

  final String sessionId;
  final String userId;
  final String name;
  final String? notes;
  final bool isArchived;
  final String? programId;
  final int? sequenceOrder;
  final int? dayOfWeek;
  final DateTime? createdDate;

  factory PlannedSession.fromMap(Map<String, dynamic> map) => PlannedSession(
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        notes: map['notes'] as String?,
        isArchived: _toBool(map['is_archived']),
        programId: map['program_id'] as String?,
        sequenceOrder: _toInt(map['sequence_order']),
        dayOfWeek: _toInt(map['day_of_week']),
        createdDate: map['created_date'] != null
            ? DateTime.tryParse(map['created_date'] as String)
            : null,
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

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'name': name,
        'notes': notes,
        'is_archived': isArchived,
        'program_id': programId,
        'sequence_order': sequenceOrder,
        'day_of_week': dayOfWeek,
        'created_date': createdDate?.toIso8601String(),
      };
}
