/// A planned session — a session template. Standalone when no
/// dim_planned_session_program row references it; program membership and
/// schedule slots (sequence/day) live on the join table.
class PlannedSession {
  const PlannedSession({
    required this.sessionId,
    required this.userId,
    this.createdByUserId,
    required this.name,
    this.notes,
    this.archivedDate,
    this.createdDate,
    this.baseSessionId,
    this.coachAssignmentId,
  });

  final String sessionId;
  final String userId;
  final String? createdByUserId;
  final String name;
  final String? notes;

  /// NULL = active; a timestamp = archived (sortable, latest first).
  final DateTime? archivedDate;

  bool get isArchived => archivedDate != null;

  final DateTime? createdDate;

  /// Copy-on-add provenance: the library workout this is a copy of.
  ///
  /// NULL means the workout originated where it is — a library workout, or one
  /// authored inside a program. Set means this is a program-local copy, and
  /// names the original it came from. Copies never track the base (no
  /// "your copy is behind" state) — it exists so a program edit can push back
  /// to the original on request, and so duplication can inherit lineage rather
  /// than inventing a new root.
  final String? baseSessionId;

  /// Whether this workout is a program copy rather than a library original.
  bool get isCopy => baseSessionId != null;

  /// The coach assignment this workout was copied from on accept (2026-10-26,
  /// #24). NULL = the athlete's own; set = a coach authored it and the athlete
  /// accepted it into their library.
  final String? coachAssignmentId;

  bool get isCoachAssigned => coachAssignmentId != null;

  factory PlannedSession.fromMap(Map<String, dynamic> map) => PlannedSession(
    sessionId: map['session_id'] as String,
    userId: map['user_id'] as String,
    createdByUserId: map['created_by_user_id'] as String?,
    name: map['name'] as String,
    notes: map['notes'] as String?,
    archivedDate: map['date_archived'] != null
        ? DateTime.tryParse(map['date_archived'] as String)
        : null,
    createdDate: map['created_date'] != null
        ? DateTime.tryParse(map['created_date'] as String)
        : null,
    baseSessionId: map['base_session_id'] as String?,
    coachAssignmentId: map['coach_assignment_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'user_id': userId,
    'created_by_user_id': createdByUserId,
    'name': name,
    'notes': notes,
    'date_archived': archivedDate?.toIso8601String(),
    'created_date': createdDate?.toIso8601String(),
    'base_session_id': baseSessionId,
    'coach_assignment_id': coachAssignmentId,
  };
}
