import 'planned_session.dart';

class Program {
  const Program({
    required this.programId,
    required this.userId,
    required this.name,
    required this.progressionMode,
    required this.isArchived,
    required this.createdDate,
    this.description,
    this.lengthWeeks,
  });

  final String programId;
  final String userId;
  final String name;
  final String? description;
  final int? lengthWeeks;
  final String progressionMode; // 'sequential' | 'calendar'
  final bool isArchived;
  final DateTime createdDate;

  factory Program.fromMap(Map<String, dynamic> map) => Program(
        programId: map['program_id'] as String,
        userId: map['user_id'] as String,
        name: map['program_name'] as String,
        description: map['program_description'] as String?,
        lengthWeeks: _toInt(map['program_length_weeks']),
        progressionMode: map['progression_mode'] as String? ?? 'sequential',
        isArchived: _toBool(map['is_archived']),
        createdDate: DateTime.parse(map['program_created_date'] as String),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Map<String, dynamic> toMap() => {
        'program_id': programId,
        'user_id': userId,
        'program_name': name,
        'program_description': description,
        'program_length_weeks': lengthWeeks,
        'progression_mode': progressionMode,
        'is_archived': isArchived,
        'program_created_date': createdDate.toIso8601String(),
      };
}

class ProgramWithSessions {
  const ProgramWithSessions({required this.program, required this.plannedSessions});
  final Program program;
  final List<PlannedSession> plannedSessions;
}
