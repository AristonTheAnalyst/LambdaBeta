/// A planned session's membership in a program (dim_planned_session_program
/// join row). One planned session can belong to several programs; the
/// schedule slots live here per (program, planned session) pair.
class PlannedSessionProgram {
  const PlannedSessionProgram({
    required this.plannedSessionProgramId,
    required this.programId,
    required this.plannedSessionId,
    required this.userId,
    this.sequenceOrder,
    this.dayOfWeek,
    this.weekOffset,
    this.blockId,
  });

  final String plannedSessionProgramId;
  final String programId;
  final String plannedSessionId;
  final String userId;

  /// Position within the program — the cursor for 'order' runs.
  final int? sequenceOrder;

  /// 1–7 assignment for 'frequency' runs.
  final int? dayOfWeek;

  /// Fortnight week: 0 = week 1, 1 = week 2, null = every week.
  final int? weekOffset;

  /// The block this workout belongs to; null = a blockless program. The server
  /// holds (program_id, block_id) as a composite FK, so the pair always names a
  /// real block of THIS program.
  final String? blockId;

  factory PlannedSessionProgram.fromMap(Map<String, dynamic> map) =>
      PlannedSessionProgram(
        plannedSessionProgramId: map['planned_session_program_id'] as String,
        programId: map['program_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        sequenceOrder: _toInt(map['sequence_order']),
        dayOfWeek: _toInt(map['day_of_week']),
        weekOffset: _toInt(map['week_offset']),
        blockId: map['block_id'] as String?,
      );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Map<String, dynamic> toMap() => {
        'planned_session_program_id': plannedSessionProgramId,
        'program_id': programId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'sequence_order': sequenceOrder,
        'day_of_week': dayOfWeek,
        'week_offset': weekOffset,
        'block_id': blockId,
      };
}
