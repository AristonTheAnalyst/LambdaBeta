import 'planned_session.dart';

/// A program blueprint. Progression mode is not here — how the program is
/// RUN (frequency vs order) is a property of the run (fact_program_run).
class Program {
  const Program({
    required this.programId,
    required this.userId,
    required this.name,
    required this.isArchived,
    required this.createdDate,
    required this.updatedDate,
    this.description,
  });

  final String programId;
  final String userId;
  final String name;
  final String? description;
  final bool isArchived;
  final DateTime createdDate;
  final DateTime updatedDate;

  factory Program.fromMap(Map<String, dynamic> map) {
    final created = DateTime.parse(map['program_created_date'] as String);
    return Program(
      programId: map['program_id'] as String,
      userId: map['user_id'] as String,
      name: map['program_name'] as String,
      description: map['program_description'] as String?,
      isArchived: _toBool(map['is_archived']),
      createdDate: created,
      updatedDate: map['program_updated_date'] != null
          ? DateTime.parse(map['program_updated_date'] as String)
          : created,
    );
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'program_id': programId,
        'user_id': userId,
        'program_name': name,
        'program_description': description,
        'is_archived': isArchived,
        'program_created_date': createdDate.toIso8601String(),
        'program_updated_date': updatedDate.toIso8601String(),
      };
}

class ProgramWithSessions {
  const ProgramWithSessions({required this.program, required this.plannedSessions});
  final Program program;
  final List<PlannedSession> plannedSessions;
}
