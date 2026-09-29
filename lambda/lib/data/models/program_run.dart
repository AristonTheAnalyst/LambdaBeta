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
    this.progressionMode,
    this.blockId,
  });

  final String programRunId;
  final String programId;
  final String userId;
  final DateTime startedDate;
  final DateTime? endedDate;
  final bool isCurrent;

  /// The block being run. NULL = a blockless run: the whole program is the
  /// unit, which is what every run was before blocks existed.
  ///
  /// A block run *is* a run — it has the same start/end, the same one-current
  /// rule, the same session attribution. Only the set of workouts it walks is
  /// narrowed, which is why nothing in the run layer branches on this beyond
  /// the link filter in `getNextPlannedSession`.
  final String? blockId;

  /// How this run progresses: 'frequency' (sessions assigned to days in the
  /// week/fortnight) or 'order' (sessions worked through in sequence).
  /// null (legacy runs) behaves as 'order'.
  final String? progressionMode;

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
        progressionMode: map['progression_mode'] as String?,
        blockId: map['block_id'] as String?,
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

  // No `effectiveEndDate` here. A block run's length lives on the BLOCK, so a
  // getter that can only see the run's own `targetWeeks` reports null for
  // exactly the runs that most need an end date. `ProgramProgress.endsAt` is
  // the same arithmetic with the block in view, and it is the only spelling.

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
        'progression_mode': progressionMode,
        'block_id': blockId,
      };
}
