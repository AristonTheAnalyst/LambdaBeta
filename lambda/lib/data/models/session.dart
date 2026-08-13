import 'session_set.dart';

/// A logged session — the fact record of one workout. When started from a
/// planned session, [parentSessionId] links back to the template; the name
/// snapshots on this row survive later template edits.
class Session {
  const Session({
    required this.sessionId,
    required this.userId,
    required this.createdDate,
    required this.isActive,
    this.preNotes,
    this.postNotes,
    this.preFeeling,
    this.feeling,
    this.programId,
    this.programName,
    this.programRunId,
    this.parentSessionId,
    this.parentSessionName,
    this.exerciseOrder,
  });

  final String sessionId;
  final String userId;
  final String? preNotes;
  final String? postNotes;
  final DateTime createdDate;
  final bool isActive;
  final int? preFeeling;
  final int? feeling;
  final String? programId;
  final String? programName;
  final String? programRunId;
  final String? parentSessionId;
  final String? parentSessionName;

  /// JSON string of the session's exercise tab slots (order + superset
  /// grouping), so the tab bar survives a hot restart.
  final String? exerciseOrder;

  factory Session.fromMap(Map<String, dynamic> map) => Session(
        sessionId: map['session_id'] as String,
        userId: map['user_id'] as String,
        preNotes: map['pre_notes'] as String?,
        postNotes: map['post_notes'] as String?,
        createdDate: DateTime.parse(map['created_date'] as String),
        isActive: _toBool(map['is_active']),
        preFeeling: map['pre_feeling'] as int?,
        feeling: map['post_feeling'] as int?,
        programId: map['program_id'] as String?,
        programName: map['program_name'] as String?,
        programRunId: map['program_run_id'] as String?,
        parentSessionId: map['parent_session_id'] as String?,
        parentSessionName: map['parent_session_name'] as String?,
        exerciseOrder: map['exercise_order'] as String?,
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'pre_notes': preNotes,
        'post_notes': postNotes,
        'created_date': createdDate.toIso8601String(),
        'is_active': isActive,
        'pre_feeling': preFeeling,
        'post_feeling': feeling,
        'program_id': programId,
        'program_name': programName,
        'program_run_id': programRunId,
        'parent_session_id': parentSessionId,
        'parent_session_name': parentSessionName,
        'exercise_order': exerciseOrder,
      };
}

class SessionWithSets {
  const SessionWithSets({required this.session, required this.sets});
  final Session session;
  final List<SessionSet> sets;
}
