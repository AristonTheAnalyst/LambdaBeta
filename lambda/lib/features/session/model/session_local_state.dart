import '../../../data/models/session_exercise_set.dart';

/// Pure local/in-memory state for the session screen — never persisted.
/// A history "session" is a display-only grouping of already-persisted
/// [PastSetRow]s. (Lessons used to live here too, before they got a real
/// backing table — see data/models/lesson.dart.)

class ExerciseHistorySession {
  const ExerciseHistorySession({required this.date, required this.sets});

  final DateTime date;
  final List<PastSetRow> sets;
}

/// Groups a user's full past-sets timeline into one [ExerciseHistorySession]
/// per exercise per workout, newest first.
Map<String, List<ExerciseHistorySession>> groupHistoryByExercise(
    List<PastSetRow> pastSets) {
  final byExercise = <String, Map<String, List<PastSetRow>>>{};
  for (final s in pastSets) {
    final exId = s.exerciseId;
    if (exId == null) continue; // free rows without an exercise
    final byWorkout = byExercise.putIfAbsent(exId, () => {});
    byWorkout.putIfAbsent(s.sessionId, () => []).add(s);
  }
  return byExercise.map((exerciseId, byWorkout) {
    final sessions = byWorkout.values
        .map((sets) => ExerciseHistorySession(
              date: sets.first.sessionCreatedDate,
              sets: sets,
            ))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return MapEntry(exerciseId, sessions);
  });
}

/// Classic edit-distance — used to flag "did you mean?" near-duplicate
/// variation names (e.g. "Paused" vs "Pause") without a fuzzy-matching
/// dependency.
int levenshteinDistance(String a, String b) {
  final la = a.length, lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (j) => j);
  for (var i = 1; i <= la; i++) {
    final cur = List<int>.filled(lb + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final deletion = prev[j] + 1;
      final insertion = cur[j - 1] + 1;
      final substitution = prev[j - 1] + cost;
      cur[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[lb];
}

/// Whether [a] and [b] are close enough to be the same variation typed
/// slightly differently — not identical (that's an exact match, handled
/// separately), but within a length-scaled edit-distance budget.
bool isSimilarVariationName(String a, String b) {
  final an = a.trim().toLowerCase();
  final bn = b.trim().toLowerCase();
  if (an.isEmpty || bn.isEmpty || an == bn) return false;
  final dist = levenshteinDistance(an, bn);
  final maxLen = an.length > bn.length ? an.length : bn.length;
  final threshold = maxLen <= 6 ? 2 : (maxLen * 0.3).ceil();
  return dist <= threshold;
}

enum SessionSlotType { single, superset }

/// One tab in the exercise tab bar — a single exercise, or a superset
/// cycling through several on repeated taps.
class SessionExerciseSlot {
  SessionExerciseSlot({
    required this.id,
    required this.type,
    required this.exerciseIds,
    this.activeIndex = 0,
    this.planned = false,
  });

  final int id;
  final SessionSlotType type;
  final List<String> exerciseIds;
  int activeIndex;
  final bool planned;

  String get activeExerciseId =>
      exerciseIds[activeIndex.clamp(0, exerciseIds.length - 1)];

  void cycle() {
    if (exerciseIds.length <= 1) return;
    activeIndex = (activeIndex + 1) % exerciseIds.length;
  }
}
