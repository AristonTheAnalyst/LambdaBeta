import 'planned_session.dart';

/// A program blueprint. Progression mode is not here — how the program is
/// RUN (frequency vs order) is a property of the run (fact_program_run).
class Program {
  const Program({
    required this.programId,
    required this.userId,
    required this.name,
    required this.createdDate,
    required this.updatedDate,
    this.description,
    this.archivedDate,
    this.usesBlocks = false,
    this.defaultTargetSessions,
  });

  final String programId;
  final String userId;
  final String name;
  final String? description;

  /// NULL = active; a timestamp = archived (sortable, latest first).
  final DateTime? archivedDate;

  bool get isArchived => archivedDate != null;

  final DateTime createdDate;
  final DateTime updatedDate;

  /// The program's shape, fixed when it was created: true = made of blocks
  /// (you run its blocks, one at a time), false = a list of workouts.
  ///
  /// Read from the column, never inferred from the block list — a blocked
  /// program with no blocks yet is a real state, and inferring "simple" from
  /// it would offer a whole-program run the shape rule forbids, and a Workouts
  /// tab where the shape says workouts live inside blocks.
  final bool usesBlocks;

  /// A simple program's own remembered length: the begin sheet prefills from
  /// it and writes the chosen count back, so a program remembers how long its
  /// runs are between attempts. NULL = no default set yet.
  final int? defaultTargetSessions;

  factory Program.fromMap(Map<String, dynamic> map) {
    final created = DateTime.parse(map['program_created_date'] as String);
    return Program(
      programId: map['program_id'] as String,
      userId: map['user_id'] as String,
      name: map['program_name'] as String,
      description: map['program_description'] as String?,
      archivedDate: map['date_archived'] != null
          ? DateTime.tryParse(map['date_archived'] as String)
          : null,
      createdDate: created,
      updatedDate: map['program_updated_date'] != null
          ? DateTime.parse(map['program_updated_date'] as String)
          : created,
      usesBlocks: _toBool(map['uses_blocks']),
      defaultTargetSessions: _toInt(map['default_target_sessions']),
    );
  }

  Map<String, dynamic> toMap() => {
        'program_id': programId,
        'user_id': userId,
        'program_name': name,
        'program_description': description,
        'date_archived': archivedDate?.toIso8601String(),
        'program_created_date': createdDate.toIso8601String(),
        'program_updated_date': updatedDate.toIso8601String(),
        'uses_blocks': usesBlocks ? 1 : 0,
        'default_target_sessions': defaultTargetSessions,
      };

  /// Note the opposite default from `ProgramRun._toBool`: NULL means false
  /// here, not true. A row the local mirror has not re-downloaded since the
  /// column was added reads as NULL until a sync lands, and the two ways to be
  /// wrong are not equal — a temporary "simple" costs a missing Blocks tab,
  /// while a temporary "blocked" would put block surfacing on every program,
  /// including ones with no block of any kind.
  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class ProgramWithSessions {
  const ProgramWithSessions({required this.program, required this.plannedSessions});
  final Program program;
  final List<PlannedSession> plannedSessions;
}
