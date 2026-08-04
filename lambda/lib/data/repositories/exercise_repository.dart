import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/custom_exercise.dart';
import '../models/custom_variation.dart';
import '../models/exercise_detail.dart';
import '../models/exercise_usage.dart';
import 'workout_repository.dart';

// lastUsedByEntity is used by fetchExerciseDetailMap below.

const _uuid = Uuid();

class ExerciseRepository {
  final _workoutRepo = WorkoutRepository();

  /// Aggregate per-exercise and per-variation usage across the user's history
  /// (sets, workouts, last used, and the distinct other-entity count). Derived
  /// from the past-sets timeline so it stays consistent with what the library
  /// and analytics show. Every exercise/variation gets an entry (zeros if
  /// unused) so callers can sort the full list.
  Future<Map<String, ExerciseUsage>> fetchUsage(String userId) async {
    final timeline = await _workoutRepo.loadPastSetsTimeline(userId);
    final exSets = <String, int>{};
    final exWorkouts = <String, Set<String>>{};
    final exVariations = <String, Set<String>>{};
    final exLast = <String, DateTime>{};
    final varSets = <String, int>{};
    final varWorkouts = <String, Set<String>>{};
    final varExercises = <String, Set<String>>{};
    final varLast = <String, DateTime>{};

    for (final s in timeline) {
      final d = s.workoutCreatedDate;
      // Exercise
      exSets[s.exerciseId] = (exSets[s.exerciseId] ?? 0) + 1;
      exWorkouts.putIfAbsent(s.exerciseId, () => {}).add(s.workoutId);
      if (s.variationId != null) {
        exVariations.putIfAbsent(s.exerciseId, () => {}).add(s.variationId!);
      }
      if (d.isAfter(exLast[s.exerciseId] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
        exLast[s.exerciseId] = d;
      }
      // Variation
      if (s.variationId != null) {
        final vid = s.variationId!;
        varSets[vid] = (varSets[vid] ?? 0) + 1;
        varWorkouts.putIfAbsent(vid, () => {}).add(s.workoutId);
        varExercises.putIfAbsent(vid, () => {}).add(s.exerciseId);
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
      'SELECT * FROM dim_exercise WHERE user_id = ? AND is_active = 1 ORDER BY exercise_name',
      [userId],
    );
    return rows.map((r) => CustomExercise.fromMap(r)).toList();
  }

  Future<List<CustomVariation>> fetchVariations(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND is_active = 1 ORDER BY variation_name',
      [userId],
    );
    return rows.map((r) => CustomVariation.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBridges(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT custom_exercise_id, custom_variation_id FROM dim_exercise_variation_bridge WHERE user_id = ? AND (deleted_locally IS NULL OR deleted_locally = 0)',
      [userId],
    );
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
      String userId) async {
    final exercises = await fetchExercises(userId);
    final variations = await fetchVariations(userId);
    final bridges = await fetchBridges(userId);

    // Stamp each variation with its most-recent-use date so any surface
    // rendering assigned variations can order them by recency.
    final lastUsed = lastUsedByEntity(
        await _workoutRepo.loadPastSetsTimeline(userId));
    final varMap = {
      for (final v in variations) v.variationId: v.copyWith(lastUsed: lastUsed[v.variationId]),
    };
    final assignedMap = <String, List<CustomVariation>>{};
    for (final b in bridges) {
      final exId = b['custom_exercise_id'] as String;
      final varId = b['custom_variation_id'] as String;
      final variation = varMap[varId];
      if (variation != null) {
        assignedMap.putIfAbsent(exId, () => []).add(variation);
      }
    }

    return {
      for (final ex in exercises)
        ex.exerciseId: ExerciseDetail(
          exercise: ex,
          assignedVariations: assignedMap[ex.exerciseId] ?? [],
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
      'INSERT INTO dim_exercise (id, custom_exercise_id, user_id, exercise_name, is_active) VALUES (?, ?, ?, ?, ?)',
      [id, id, userId, name, 1],
    );
    return CustomExercise(
        exerciseId: id, userId: userId, name: name, isActive: true);
  }

  Future<void> reactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET is_active = 1 WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<CustomVariation> createVariation(String userId, String name) async {
    final id = _uuid.v4();
    await ps.db.execute(
      'INSERT INTO dim_variation (id, custom_variation_id, user_id, variation_name, is_active) VALUES (?, ?, ?, ?, ?)',
      [id, id, userId, name, 1],
    );
    return CustomVariation(
        variationId: id, userId: userId, name: name, isActive: true);
  }

  Future<void> reactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET is_active = 1 WHERE custom_variation_id = ?',
      [variationId],
    );
  }

  /// No unique index backs (custom_exercise_id, custom_variation_id) locally,
  /// so this is a manual check-then-write instead of a real SQL upsert. The
  /// row's id is the '-'-joined composite key — matching exactly how the
  /// PowerSync sync-rules compute id for this table
  /// (custom_exercise_id || '-' || custom_variation_id) — so a locally
  /// created row and its eventual downloaded copy resolve to the same local
  /// row instead of duplicating.
  Future<void> addBridge(
      String userId, String exerciseId, String variationId) async {
    final id = '$exerciseId-$variationId';
    final existing = await ps.db.getAll(
      'SELECT id FROM dim_exercise_variation_bridge WHERE custom_exercise_id = ? AND custom_variation_id = ?',
      [exerciseId, variationId],
    );
    if (existing.isNotEmpty) {
      await ps.db.execute(
        'UPDATE dim_exercise_variation_bridge SET deleted_locally = 0 WHERE id = ?',
        [existing.first['id']],
      );
      return;
    }
    await ps.db.execute(
      'INSERT INTO dim_exercise_variation_bridge (id, custom_exercise_id, custom_variation_id, user_id, deleted_locally) VALUES (?, ?, ?, ?, ?)',
      [id, exerciseId, variationId, userId, 0],
    );
  }

  Future<void> deactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET is_active = 0 WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<void> deactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET is_active = 0 WHERE custom_variation_id = ?',
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

  /// Soft-delete via deleted_locally rather than a hard DELETE — this table
  /// has no single-column primary key (its real PK is the composite
  /// (custom_exercise_id, custom_variation_id)), which the generic
  /// id-based upload path in SupabaseConnector.uploadData() can't target
  /// for a DELETE. PATCHing deleted_locally instead sidesteps that entirely.
  Future<void> removeBridge(String exerciseId, String variationId) async {
    await ps.db.execute(
      'UPDATE dim_exercise_variation_bridge SET deleted_locally = 1 WHERE custom_exercise_id = ? AND custom_variation_id = ?',
      [exerciseId, variationId],
    );
  }

}
