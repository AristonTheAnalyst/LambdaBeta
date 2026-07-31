import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../features/session/model/pr_engine.dart';

const _uuid = Uuid();

/// Persists PR snapshots to `fact_pr`. Rows are self-contained achievement
/// records — they copy their values at write time and never depend on the
/// source set row to render, so a deleted/edited set doesn't erase the PR.
class PrRepository {
  Future<void> insertPrs(String userId, List<PrRecord> records) async {
    for (final pr in records) {
      final id = _uuid.v4();
      await ps.db.execute(
        '''
        INSERT INTO fact_pr
          (id, pr_id, user_id, workout_set_id, custom_exercise_id,
           custom_variation_id, weight, reps, achieved_date, pr_type,
           target_reps, target_weight, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          id,
          userId,
          pr.setId,
          pr.exerciseId,
          pr.variationId,
          '${pr.weight}',
          pr.reps,
          pr.achievedDate.toUtc().toIso8601String(),
          pr.type.name,
          pr.targetReps,
          pr.targetWeight != null ? '${pr.targetWeight}' : null,
          1,
        ],
      );
    }
  }

  Future<List<PrRecord>> loadAll(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name, fws.user_workout_id
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      LEFT JOIN fact_workout_set fws ON fws.workout_set_id = p.workout_set_id
      WHERE p.user_id = ? AND p.is_active = 1
      ORDER BY p.achieved_date
      ''',
      [userId],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  Future<List<PrRecord>> loadForWorkout(String userId, String workoutId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      WHERE p.user_id = ? AND p.is_active = 1 AND p.workout_set_id IN (
        SELECT workout_set_id FROM fact_workout_set WHERE user_workout_id = ?
      )
      ORDER BY p.achieved_date
      ''',
      [userId, workoutId],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  Future<List<PrRecord>> loadForSets(String userId, List<String> setIds) async {
    if (setIds.isEmpty) return [];
    final placeholders = List.filled(setIds.length, '?').join(',');
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      WHERE p.user_id = ? AND p.is_active = 1 AND p.workout_set_id IN ($placeholders)
      ''',
      [userId, ...setIds],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  Future<void> deleteForSets(String userId, List<String> setIds) async {
    if (setIds.isEmpty) return;
    final placeholders = List.filled(setIds.length, '?').join(',');
    await ps.db.execute(
      'UPDATE fact_pr SET is_active = 0 WHERE user_id = ? AND workout_set_id IN ($placeholders)',
      [userId, ...setIds],
    );
  }

  Future<void> deleteForExercise(String userId, String exerciseId) async {
    await ps.db.execute(
      'UPDATE fact_pr SET is_active = 0 WHERE user_id = ? AND custom_exercise_id = ?',
      [userId, exerciseId],
    );
  }

  Future<int> count(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT COUNT(*) AS c FROM fact_pr WHERE user_id = ? AND is_active = 1',
      [userId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as num).toInt();
  }
}
