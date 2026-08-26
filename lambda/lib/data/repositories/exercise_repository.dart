import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/custom_exercise.dart';
import '../models/custom_variation.dart';
import '../models/exercise_detail.dart';
import '../models/exercise_usage.dart';
import 'session_repository.dart';

// lastUsedByEntity is used by fetchExerciseDetailMap below.

const _uuid = Uuid();

class ExerciseRepository {
  final _sessionRepo = SessionRepository();

  /// Aggregate per-exercise and per-variation usage across the user's history
  /// (sets, workouts, last used, and the distinct other-entity count). Derived
  /// from the past-sets timeline so it stays consistent with what the library
  /// and analytics show. Every exercise/variation gets an entry (zeros if
  /// unused) so callers can sort the full list.
  Future<Map<String, ExerciseUsage>> fetchUsage(String userId) async {
    final timeline = await _sessionRepo.loadPastSetsTimeline(userId);
    final exSets = <String, int>{};
    final exWorkouts = <String, Set<String>>{};
    final exVariations = <String, Set<String>>{};
    final exLast = <String, DateTime>{};
    final varSets = <String, int>{};
    final varWorkouts = <String, Set<String>>{};
    final varExercises = <String, Set<String>>{};
    final varLast = <String, DateTime>{};

    for (final s in timeline) {
      final d = s.sessionCreatedDate;
      // Exercise (sets with no exercise are free rows — nothing to aggregate)
      final exerciseId = s.exerciseId;
      if (exerciseId != null) {
        exSets[exerciseId] = (exSets[exerciseId] ?? 0) + 1;
        exWorkouts.putIfAbsent(exerciseId, () => {}).add(s.sessionId);
        if (s.variationId != null) {
          exVariations.putIfAbsent(exerciseId, () => {}).add(s.variationId!);
        }
        if (d.isAfter(
            exLast[exerciseId] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          exLast[exerciseId] = d;
        }
      }
      // Variation
      if (s.variationId != null) {
        final vid = s.variationId!;
        varSets[vid] = (varSets[vid] ?? 0) + 1;
        varWorkouts.putIfAbsent(vid, () => {}).add(s.sessionId);
        if (exerciseId != null) {
          varExercises.putIfAbsent(vid, () => {}).add(exerciseId);
        }
        if (d.isAfter(varLast[vid] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          varLast[vid] = d;
        }
      }
    }

    final usage = <String, ExerciseUsage>{};
    for (final e in await fetchExercises(userId)) {
      usage[e.exerciseId] = ExerciseUsage(
        sets: exSets[e.exerciseId] ?? 0,
        workouts: exWorkouts[e.exerciseId]?.length ?? 0,
        variationCount: exVariations[e.exerciseId]?.length ?? 0,
        lastUsed: exLast[e.exerciseId],
      );
    }
    for (final v in await fetchVariations(userId)) {
      usage[v.variationId] = ExerciseUsage(
        sets: varSets[v.variationId] ?? 0,
        workouts: varWorkouts[v.variationId]?.length ?? 0,
        exerciseCount: varExercises[v.variationId]?.length ?? 0,
        lastUsed: varLast[v.variationId],
      );
    }
    return usage;
  }

  Future<List<CustomExercise>> fetchExercises(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND is_archived = 0 ORDER BY exercise_name',
      [userId],
    );
    return rows.map((r) => CustomExercise.fromMap(r)).toList();
  }

  Future<List<CustomVariation>> fetchVariations(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND is_archived = 0 ORDER BY variation_name',
      [userId],
    );
    return rows.map((r) => CustomVariation.fromMap(r)).toList();
  }

  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
      String userId) async {
    final exercises = await fetchExercises(userId);

    // Exercises and variations are independent since schema v2 (no bridge) —
    // variation assignment is gone, so each detail is just its exercise.
    return {
      for (final ex in exercises)
        ex.exerciseId: ExerciseDetail(
          exercise: ex,
        ),
    };
  }

  Future<CustomExercise?> findExerciseByName(
      String userId, String name) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND LOWER(exercise_name) = LOWER(?)',
      [userId, name],
    );
    if (rows.isEmpty) return null;
    return CustomExercise.fromMap(rows.first);
  }

  Future<CustomVariation?> findVariationByName(
      String userId, String name) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND LOWER(variation_name) = LOWER(?)',
      [userId, name],
    );
    if (rows.isEmpty) return null;
    return CustomVariation.fromMap(rows.first);
  }

  Future<CustomExercise> createExercise(String userId, String name) async {
    final id = _uuid.v4();
    await ps.db.execute(
      'INSERT INTO dim_exercise (id, custom_exercise_id, user_id, exercise_name, is_archived) VALUES (?, ?, ?, ?, ?)',
      [id, id, userId, name, 0],
    );
    return CustomExercise(
        exerciseId: id, userId: userId, name: name, isArchived: false);
  }

  Future<void> reactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET is_archived = 0 WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<CustomVariation> createVariation(String userId, String name) async {
    final id = _uuid.v4();
    await ps.db.execute(
      'INSERT INTO dim_variation (id, custom_variation_id, user_id, variation_name, is_archived) VALUES (?, ?, ?, ?, ?)',
      [id, id, userId, name, 0],
    );
    return CustomVariation(
        variationId: id, userId: userId, name: name, isArchived: false);
  }

  Future<void> reactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET is_archived = 0 WHERE custom_variation_id = ?',
      [variationId],
    );
  }

  Future<void> deactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET is_archived = 1 WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<void> deactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET is_archived = 1 WHERE custom_variation_id = ?',
      [variationId],
    );
  }

  Future<void> updateExercise(String exerciseId, String name) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET exercise_name = ? WHERE custom_exercise_id = ?',
      [name, exerciseId],
    );
  }

  Future<void> updateVariation(String variationId, String name) async {
    await ps.db.execute(
      'UPDATE dim_variation SET variation_name = ? WHERE custom_variation_id = ?',
      [name, variationId],
    );
  }
}
