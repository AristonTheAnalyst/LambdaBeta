import 'dart:convert';

/// A coach assigning one of their workouts to an accepted athlete
/// (2026-10-26, #24).
///
/// The row is the whole hand-off: a frozen [snapshotContent] document of the
/// workout plus the [namesJson] map the athlete cannot build for themselves
/// (`dim_exercise` / `dim_variation` rows are per-user, and the snapshot is
/// id-only). Nothing about the coach's template rows ever reaches the
/// athlete's device — the accept copies the document into the athlete's own
/// library instead.
///
/// Status is two nullable stamps, the app's usual shape:
/// [acceptedDate] set = the athlete took it (and [athletePlannedSessionId]
/// names their copy); [declinedDate] set = they passed; both null = waiting.
/// A declined row stays as history but grants nothing.
class CoachAssignment {
  const CoachAssignment({
    required this.assignmentId,
    required this.coachUserId,
    required this.athleteUserId,
    required this.plannedSessionId,
    required this.name,
    this.note,
    required this.snapshotContent,
    this.namesJson,
    this.createdDate,
    this.acceptedDate,
    this.declinedDate,
    this.athletePlannedSessionId,
  });

  final String assignmentId;
  final String coachUserId;
  final String athleteUserId;

  /// The coach's source template — informational only; the copy is built from
  /// the snapshot.
  final String plannedSessionId;

  /// The workout's name, frozen at assignment time; the athlete's copy keeps it.
  final String name;

  /// The coach's message with the assignment (prose, optional).
  final String? note;

  /// The ProgramContent document (schema 2) for the one workout.
  final String snapshotContent;

  /// `{"exercises": {id: name}, "variations": {id: name}}` — every id the
  /// snapshot references, named as the coach saw it.
  final String? namesJson;

  final DateTime? createdDate;
  final DateTime? acceptedDate;
  final DateTime? declinedDate;

  /// The athlete's copy once accepted.
  final String? athletePlannedSessionId;

  bool get isPending => acceptedDate == null && declinedDate == null;
  bool get isAccepted => acceptedDate != null;
  bool get isDeclined => declinedDate != null;

  /// The exercise names in [namesJson]; empty when the map was not written
  /// (an old row — nothing to resolve, and the accept skips what it cannot
  /// name).
  Map<String, String> get exerciseNames => _names('exercises');

  Map<String, String> get variationNames => _names('variations');

  Map<String, String> _names(String key) {
    final raw = namesJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final section = decoded[key];
      if (section is! Map) return const {};
      return {
        for (final entry in section.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      };
    } catch (_) {
      // A malformed map costs the copy its names, never the accept itself.
      return const {};
    }
  }

  factory CoachAssignment.fromMap(Map<String, dynamic> map) => CoachAssignment(
    assignmentId: map['assignment_id'] as String,
    coachUserId: map['coach_user_id'] as String,
    athleteUserId: map['athlete_user_id'] as String,
    plannedSessionId: map['planned_session_id'] as String,
    name: (map['name'] as String?) ?? '',
    note: map['note'] as String?,
    snapshotContent: (map['snapshot_content'] as String?) ?? '',
    namesJson: map['names_json'] as String?,
    createdDate: _date(map['created_date']),
    acceptedDate: _date(map['accepted_date']),
    declinedDate: _date(map['declined_date']),
    athletePlannedSessionId: map['athlete_planned_session_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'assignment_id': assignmentId,
    'coach_user_id': coachUserId,
    'athlete_user_id': athleteUserId,
    'planned_session_id': plannedSessionId,
    'name': name,
    'note': note,
    'snapshot_content': snapshotContent,
    'names_json': namesJson,
    'created_date': createdDate?.toUtc().toIso8601String(),
    'accepted_date': acceptedDate?.toUtc().toIso8601String(),
    'declined_date': declinedDate?.toUtc().toIso8601String(),
    'athlete_planned_session_id': athletePlannedSessionId,
  };

  CoachAssignment copyWith({
    DateTime? acceptedDate,
    DateTime? declinedDate,
    String? athletePlannedSessionId,
  }) => CoachAssignment(
    assignmentId: assignmentId,
    coachUserId: coachUserId,
    athleteUserId: athleteUserId,
    plannedSessionId: plannedSessionId,
    name: name,
    note: note,
    snapshotContent: snapshotContent,
    namesJson: namesJson,
    createdDate: createdDate,
    acceptedDate: acceptedDate ?? this.acceptedDate,
    declinedDate: declinedDate ?? this.declinedDate,
    athletePlannedSessionId:
        athletePlannedSessionId ?? this.athletePlannedSessionId,
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
