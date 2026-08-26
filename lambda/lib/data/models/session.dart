import 'session_exercise_set.dart';

/// A logged session — the fact record of one workout. When started from a
/// planned session, [plannedSessionId] links back to the template; the name
/// snapshot on this row survives later template edits. [endDatetime] NULL
/// means the session is still in progress.
class Session {
  const Session({
    required this.sessionId,
    required this.userId,
    required this.createdDatetime,
    this.endDatetime,
    this.preNotes,
    this.postNotes,
    this.preFeeling,
    this.feeling,
    this.programRunId,
    this.plannedSessionId,
    this.plannedSessionName,
  });

  final String sessionId;
  final String userId;
  final String? preNotes;
  final String? postNotes;
  final DateTime createdDatetime;
  final DateTime? endDatetime;
  final int? preFeeling;
  final int? feeling;
  final String? programRunId;
  final String? plannedSessionId;
  final String? plannedSessionName;

  /// A session with no end time is still being logged.
  bool get isActive => endDatetime == null;

  factory Session.fromMap(Map<String, dynamic> map) => Session(
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        preNotes: map['pre_notes'] as String?,
        postNotes: map['post_notes'] as String?,
        createdDatetime: DateTime.parse(map['created_datetime'] as String),
        endDatetime: map['end_datetime'] != null
            ? DateTime.parse(map['end_datetime'] as String)
            : null,
        preFeeling: map['pre_feeling'] as int?,
        feeling: map['post_feeling'] as int?,
        programRunId: map['program_run_id'] as String?,
        plannedSessionId: map['planned_session_id'] as String?,
        plannedSessionName: map['planned_session_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'pre_notes': preNotes,
        'post_notes': postNotes,
        'created_datetime': createdDatetime.toIso8601String(),
        'end_datetime': endDatetime?.toIso8601String(),
        'pre_feeling': preFeeling,
        'post_feeling': feeling,
        'program_run_id': programRunId,
        'planned_session_id': plannedSessionId,
        'planned_session_name': plannedSessionName,
      };
}

class SessionWithSets {
  const SessionWithSets({required this.session, required this.sets});
  final Session session;
  final List<SessionExerciseSet> sets;
}
