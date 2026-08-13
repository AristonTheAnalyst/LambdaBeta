import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/session_set.dart';
import '../../features/session/model/pr_engine.dart';

const _uuid = Uuid();

/// Persists PR snapshots to `fact_pr`. Rows are self-contained achievement
/// records — they copy their values at write time and never depend on the
/// source set row to render, so a deleted/edited set doesn't erase the PR.
class PrRepository {
  /// Loads all PRs, backfilling from full set history the first time if
  /// fact_pr is empty (existing users whose workouts predate PR tracking).
  /// Callers pass a way to load the full past-sets timeline so this repo
  /// doesn't take a hard dependency on SessionRepository.
  Future<List<PrRecord>> loadAllWithBackfill(
    String userId,
    Future<List<PastSetRow>> Function() loadSets,
  ) async {
    var prs = await loadAll(userId);
    if (prs.isEmpty) {
      final sets = await loadSets();
      final timeline = fullPrTimeline(sets);
      if (timeline.isNotEmpty) {
        await insertPrs(userId, timeline);
        prs = await loadAll(userId);
      }
    }
    return prs;
  }

  Future<void> insertPrs(String userId, List<PrRecord> records) async {
    for (final pr in records) {
      final id = _uuid.v4();
      await ps.db.execute(
        '''
        INSERT INTO fact_pr
          (id, pr_id, user_id, session_set_id, custom_exercise_id,
           custom_variation_id, weight, reps, achieved_date, pr_type,
           target_reps, target_weight, is_propagated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          id,
          userId,
          pr.setId,
          pr.exerciseId,
          pr.variationId,
          pr.weight,
          pr.reps,
          pr.achievedDate.toUtc().toIso8601String(),
          pr.type.name,
          pr.targetReps,
          pr.targetWeight,
          pr.isPropagated ? 1 : 0,
          1,
        ],
      );
    }
  }

  Future<List<PrRecord>> loadAll(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name, fws.session_id
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      LEFT JOIN fact_session_set fws ON fws.session_set_id = p.session_set_id
      WHERE p.user_id = ?
      ORDER BY p.achieved_date
      ''',
      [userId],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  /// Scoped to one exercise — used by the per-exercise detail screen so it
  /// only fetches the records it needs (faster, and a bad row elsewhere can't
  /// break one exercise's view).
  Future<List<PrRecord>> loadForExercise(String userId, String exerciseId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name, fws.session_id
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      LEFT JOIN fact_session_set fws ON fws.session_set_id = p.session_set_id
      WHERE p.user_id = ? AND p.custom_exercise_id = ?
      ORDER BY p.achieved_date
      ''',
      [userId, exerciseId],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  Future<List<PrRecord>> loadForWorkout(String userId, String sessionId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT p.*, e.exercise_name, v.variation_name
      FROM fact_pr p
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = p.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = p.custom_variation_id
      WHERE p.user_id = ? AND p.session_set_id IN (
        SELECT session_set_id FROM fact_session_set WHERE session_id = ?
      )
      ORDER BY p.achieved_date
      ''',
      [userId, sessionId],
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
      WHERE p.user_id = ? AND p.session_set_id IN ($placeholders)
      ''',
      [userId, ...setIds],
    );
    return rows.map((r) => PrRecord.fromMap(r)).toList();
  }

  Future<void> deleteForSets(String userId, List<String> setIds) async {
    if (setIds.isEmpty) return;
    final placeholders = List.filled(setIds.length, '?').join(',');
    await ps.db.execute(
      'DELETE FROM fact_pr WHERE user_id = ? AND session_set_id IN ($placeholders)',
      [userId, ...setIds],
    );
  }

  Future<void> deleteForExercise(String userId, String exerciseId) async {
    await ps.db.execute(
      'DELETE FROM fact_pr WHERE user_id = ? AND custom_exercise_id = ?',
      [userId, exerciseId],
    );
  }

  Future<int> count(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT COUNT(*) AS c FROM fact_pr WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as num).toInt();
  }
}
