/// One thing a coach did to the athlete's training (2026-10-29), derived from
/// the audit columns and the name history — there is no separate activity
/// table.
enum CoachActivityKind { added, edited, renamed }

class CoachActivityEntry {
  const CoachActivityEntry({
    required this.kind,
    required this.label,
    required this.name,
    required this.at,
  });

  final CoachActivityKind kind;

  /// The kind of row: exercise, variation, workout, goal, note, session.
  final String label;

  /// The row's name (or a short excerpt for notes; "old → new" for a rename).
  final String name;

  final DateTime at;
}
