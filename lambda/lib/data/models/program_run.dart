class ProgramRun {
  const ProgramRun({
    required this.programRunId,
    required this.programId,
    required this.userId,
    required this.startedDate,
    required this.isCurrent,
    this.endedDate,
  });

  final String programRunId;
  final String programId;
  final String userId;
  final DateTime startedDate;
  final DateTime? endedDate;
  final bool isCurrent;

  factory ProgramRun.fromMap(Map<String, dynamic> map) => ProgramRun(
        programRunId: map['program_run_id'] as String,
        programId: map['program_id'] as String,
        userId: map['user_id'] as String,
        startedDate: DateTime.parse(map['started_date'] as String),
        endedDate: map['ended_date'] != null
            ? DateTime.parse(map['ended_date'] as String)
            : null,
        isCurrent: _toBool(map['is_current']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'program_run_id': programRunId,
        'program_id': programId,
        'user_id': userId,
        'started_date': startedDate.toIso8601String(),
        'ended_date': endedDate?.toIso8601String(),
        'is_current': isCurrent,
      };
}
