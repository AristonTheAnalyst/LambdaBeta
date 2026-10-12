import 'session_exercise_set.dart';

/// exerciseId/variationId → most recent sessionCreatedDate seen for it.
/// Single source of truth for "most recently used" ordering everywhere.
Map<String, DateTime> lastUsedByEntity(List<PastSetRow> sets) {
  final last = <String, DateTime>{};
  for (final s in sets) {
    final d = s.sessionCreatedDate;
    final exId = s.exerciseId;
    if (exId != null) {
      final ex = last[exId];
      if (ex == null || d.isAfter(ex)) last[exId] = d;
    }
    final vid = s.variationId;
    if (vid != null) {
      final v = last[vid];
      if (v == null || d.isAfter(v)) last[vid] = d;
    }
  }
  return last;
}

/// Aggregate usage of an exercise or variation across the user's history —
/// computed from fact_workout_set (joined to fact_workout) so the exercise
/// library can show what's live vs. dead and sort by how often each is used.
class ExerciseUsage {
  const ExerciseUsage({
    this.sets = 0,
    this.workouts = 0,
    this.variationCount = 0,
    this.exerciseCount = 0,
    this.lastUsed,
  });

  final int sets;
  final int workouts;

  /// Exercises: distinct variations used across those sets.
  /// Variations: distinct exercises used with this variation.
  final int variationCount;
  final int exerciseCount;

  final DateTime? lastUsed;

  bool get hasUsage => sets > 0;

  /// Human "last used" label — e.g. "today", "2d ago", "3w ago", "5mo ago".
  String get lastUsedLabel => lastUsedLabelFor(lastUsed);
}

/// [ExerciseUsage.lastUsedLabel]'s wording: how old a usage is, in words —
/// "today", "2d ago", "3w ago", "5mo ago", "2y ago".
String lastUsedLabelFor(DateTime? at) {
  if (at == null) return 'never used';
  final days = DateTime.now().difference(at).inDays;
  if (days <= 0) return 'today';
  if (days < 7) return '${days}d ago';
  if (days < 30) return '${days ~/ 7}w ago';
  if (days < 365) return '${days ~/ 30}mo ago';
  return '${days ~/ 365}y ago';
}
