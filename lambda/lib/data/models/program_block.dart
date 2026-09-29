/// An ordered, duration-bounded phase of a program.
///
/// A program either uses blocks or doesn't — never mixed. A block owns the
/// workouts assigned to it (via the join rows' `block_id`) and, later, goals.
///
/// [targetWeeks] with [targetDays] / [targetSessions] are the phase's length
/// and [startDate] / [endDate] its planned dates. The block **owns** that
/// length: a run of this block borrows it rather than carrying its own, which
/// is why beginning a block late pushes its end out instead of eating into the
/// phase. The dates a run actually started and ended live on
/// `fact_program_run`, never here: a block can be run more than once, and the
/// second run must not overwrite the first one's history.
class ProgramBlock {
  const ProgramBlock({
    required this.blockId,
    required this.userId,
    required this.programId,
    required this.name,
    this.notes,
    required this.blockOrder,
    this.targetWeeks,
    this.targetDays,
    this.targetSessions,
    this.startDate,
    this.endDate,
    this.archivedDate,
    this.createdDate,
    this.updatedDate,
  });

  final String blockId;
  final String userId;
  final String programId;
  final String name;
  final String? notes;

  /// 1-based position within the program.
  final int blockOrder;

  /// The phase's length, in whichever unit the user chose — **never both**.
  /// A database CHECK enforces it (`dim_program_block_length_check`), and the
  /// editor enforces it by construction, because two independent nullables is
  /// how a block ends up claiming two lengths and meaning neither.
  ///
  /// [targetDays] belongs to the weeks length rather than sitting beside it as a
  /// third unit: a calendar phase is whole weeks **plus a remainder** of days,
  /// so `targetWeeks: 8, targetDays: 3` is one length of 59 days, and null means
  /// "no remainder" rather than "zero days". Two CHECKs hold it in shape
  /// (`dim_program_block_days_range_check` for 0..6,
  /// `dim_program_block_days_need_weeks_check` for weeks-without-days).
  final int? targetWeeks;
  final int? targetDays;
  final int? targetSessions;

  /// When the block is meant to run. [startDate] anchors the weeks length —
  /// [targetWeeks] and [targetDays] together — to produce [endDate], which is
  /// stored, and is a projection rather than a second source of truth. A
  /// sessions block has no [endDate] at all
  /// (`dim_program_block_sessions_no_end_check`): the sessions are the end.
  final DateTime? startDate;
  final DateTime? endDate;

  /// NULL = active; a timestamp = archived (sortable, latest first).
  final DateTime? archivedDate;

  final DateTime? createdDate;
  final DateTime? updatedDate;

  bool get isArchived => archivedDate != null;

  factory ProgramBlock.fromMap(Map<String, dynamic> map) => ProgramBlock(
        blockId: map['block_id'] as String,
        userId: map['user_id'] as String,
        programId: map['program_id'] as String,
        name: map['name'] as String,
        notes: map['notes'] as String?,
        blockOrder: _toInt(map['block_order']) ?? 1,
        targetWeeks: _toInt(map['target_weeks']),
        targetDays: _toInt(map['target_days']),
        targetSessions: _toInt(map['target_sessions']),
        startDate: _toDate(map['start_date']),
        endDate: _toDate(map['end_date']),
        archivedDate: _toDate(map['date_archived']),
        createdDate: _toDate(map['created_date']),
        updatedDate: _toDate(map['updated_date']),
      );

  Map<String, dynamic> toMap() => {
        'block_id': blockId,
        'user_id': userId,
        'program_id': programId,
        'name': name,
        'notes': notes,
        'block_order': blockOrder,
        'target_weeks': targetWeeks,
        'target_days': targetDays,
        'target_sessions': targetSessions,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'date_archived': archivedDate?.toIso8601String(),
        'created_date': createdDate?.toIso8601String(),
        'updated_date': updatedDate?.toIso8601String(),
      };

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static DateTime? _toDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
