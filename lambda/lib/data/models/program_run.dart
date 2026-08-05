class ProgramRun {
  const ProgramRun({
    required this.programRunId,
    required this.programId,
    required this.userId,
    required this.startedDate,
    required this.isCurrent,
    this.endedDate,
    this.targetSessions,
    this.targetWeeks,
    this.endDate,
  });

  final String programRunId;
  final String programId;
  final String userId;
  final DateTime startedDate;
  final DateTime? endedDate;
  final bool isCurrent;

  /// Sequential: how many sessions (workouts) to log for this run.
  final int? targetSessions;

  /// Calendar: duration in weeks (alternative to [endDate]).
  final int? targetWeeks;

  /// Calendar: explicit end date (alternative to [targetWeeks]).
  final DateTime? endDate;

  factory ProgramRun.fromMap(Map<String, dynamic> map) => ProgramRun(
        programRunId: map['program_run_id'] as String,
        programId: map['program_id'] as String,
        userId: map['user_id'] as String,
        startedDate: DateTime.parse(map['started_date'] as String),
        endedDate: map['ended_date'] != null
            ? DateTime.parse(map['ended_date'] as String)
            : null,
        isCurrent: _toBool(map['is_current']),
        targetSessions: _toInt(map['target_sessions']),
        targetWeeks: _toInt(map['target_weeks']),
        endDate: map['end_date'] != null
            ? DateTime.parse(map['end_date'] as String)
            : null,
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  /// The effective calendar end date: explicit [endDate], else the run start
  /// plus [targetWeeks].
  DateTime? get effectiveEndDate {
    if (endDate != null) return endDate;
    final w = targetWeeks;
    if (w != null) return startedDate.add(Duration(days: 7 * w));
    return null;
  }

  Map<String, dynamic> toMap() => {
        'program_run_id': programRunId,
        'program_id': programId,
        'user_id': userId,
        'started_date': startedDate.toIso8601String(),
        'ended_date': endedDate?.toIso8601String(),
        'is_current': isCurrent,
        'target_sessions': targetSessions,
        'target_weeks': targetWeeks,
        'end_date': endDate?.toIso8601String(),
      };
}
