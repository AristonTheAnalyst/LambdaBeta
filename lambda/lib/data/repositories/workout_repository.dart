import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/workout.dart';
import '../models/workout_set.dart';

const _uuid = Uuid();

class WorkoutRepository {
  final _client = Supabase.instance.client;

  Future<String> createWorkout(String userId, {String? preNotes}) async {
    final workoutId = _uuid.v4();
    await _client.from('fact_user_workout').insert({
      'user_workout_id': workoutId,
      'user_id': userId,
      'user_pre_workout_notes': preNotes?.isNotEmpty == true ? preNotes : null,
      'is_active': true,
    });
    return workoutId;
  }

  Future<void> endWorkout(String workoutId, {String? postNotes}) async {
    await _client.from('fact_user_workout').update({
      'is_active': false,
      'user_post_workout_notes': postNotes?.isNotEmpty == true ? postNotes : null,
    }).eq('user_workout_id', workoutId);
  }

  Future<void> cancelWorkout(String workoutId) async {
    await _client
        .from('fact_workout_set')
        .delete()
        .eq('user_workout_id', workoutId);
    await _client
        .from('fact_user_workout')
        .delete()
        .eq('user_workout_id', workoutId);
  }

  Future<String?> getActiveWorkoutId(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT user_workout_id FROM fact_user_workout WHERE user_id = ? AND is_active = 1 LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) return null;
    return rows.first['user_workout_id'] as String?;
  }

  Future<WorkoutSet> insertSet({
    required String workoutId,
    required String exerciseId,
    String? variationId,
    required int setNumber,
    double? weight,
    required List<num> reps,
    required List<num> duration,
    String? notes,
  }) async {
    final setId = _uuid.v4();
    final data = await _client
        .from('fact_workout_set')
        .insert({
          'workout_set_id': setId,
          'user_workout_id': workoutId,
          'custom_exercise_id': exerciseId,
          'custom_variation_id': variationId,
          'workout_set_number': setNumber,
          'workout_set_weight': weight,
          'workout_set_reps': reps,
          'workout_set_duration_seconds': duration,
          'workout_set_notes': notes?.isNotEmpty == true ? notes : null,
        })
        .select()
        .single();
    return WorkoutSet.fromMap(data);
  }

  Future<void> updateSet(
    String setId, {
    String? exerciseId,
    String? variationId,
    double? weight,
    List<num>? reps,
    List<num>? duration,
    String? notes,
    bool clearVariation = false,
    bool clearWeight = false,
    bool clearNotes = false,
  }) async {
    final updates = <String, dynamic>{};
    if (exerciseId != null) updates['custom_exercise_id'] = exerciseId;
    if (clearVariation) {
      updates['custom_variation_id'] = null;
    } else if (variationId != null) {
      updates['custom_variation_id'] = variationId;
    }
    if (clearWeight) {
      updates['workout_set_weight'] = null;
    } else if (weight != null) {
      updates['workout_set_weight'] = weight;
    }
    if (reps != null) updates['workout_set_reps'] = reps;
    if (duration != null) updates['workout_set_duration_seconds'] = duration;
    if (clearNotes) {
      updates['workout_set_notes'] = null;
    } else if (notes != null) {
      updates['workout_set_notes'] = notes.isNotEmpty ? notes : null;
    }
    if (updates.isEmpty) return;
    await _client
        .from('fact_workout_set')
        .update(updates)
        .eq('workout_set_id', setId);
  }

  Future<void> deleteSet(String setId) async {
    await _client
        .from('fact_workout_set')
        .delete()
        .eq('workout_set_id', setId);
  }

  Future<List<WorkoutSet>> loadSetsForWorkout(String workoutId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_workout_set WHERE user_workout_id = ? ORDER BY workout_set_number',
      [workoutId],
    );
    return rows.map((r) => WorkoutSet.fromMap(r)).toList();
  }

  Future<void> reorderSets(
      String workoutId, List<String> orderedSetIds) async {
    for (var i = 0; i < orderedSetIds.length; i++) {
      await _client
          .from('fact_workout_set')
          .update({'workout_set_number': i + 1}).eq(
              'workout_set_id', orderedSetIds[i]);
    }
  }

  Future<List<WorkoutWithSets>> loadWorkoutsWithSets(String userId) async {
    final workoutRows = await ps.db.getAll(
      'SELECT * FROM fact_user_workout WHERE user_id = ? AND is_active = 0 ORDER BY user_workout_created_date DESC',
      [userId],
    );
    if (workoutRows.isEmpty) return [];

    final workouts = workoutRows.map((r) => Workout.fromMap(r)).toList();

    final setRows = await ps.db.getAll(
      '''
      SELECT s.*, e.exercise_name, v.variation_name
      FROM fact_workout_set s
      LEFT JOIN user_custom_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN user_custom_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.user_workout_id IN (
        SELECT user_workout_id FROM fact_user_workout WHERE user_id = ? AND is_active = 0
      )
      ORDER BY s.user_workout_id, s.workout_set_number
      ''',
      [userId],
    );

    final setsByWorkout = <String, List<WorkoutSet>>{};
    for (final row in setRows) {
      final s = WorkoutSet.fromMap(row);
      setsByWorkout.putIfAbsent(s.workoutId, () => []).add(s);
    }

    return workouts
        .map((w) => WorkoutWithSets(
              workout: w,
              sets: setsByWorkout[w.workoutId] ?? [],
            ))
        .toList();
  }

  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, w.user_workout_created_date, e.exercise_name, v.variation_name
      FROM fact_workout_set s
      INNER JOIN fact_user_workout w ON w.user_workout_id = s.user_workout_id
      LEFT JOIN user_custom_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN user_custom_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE w.user_id = ? AND w.is_active = 0
      ORDER BY w.user_workout_created_date DESC, s.workout_set_number
      ''',
      [userId],
    );
    return rows.map((r) => PastSetRow.fromMap(r)).toList();
  }

  Future<Workout?> fetchWorkout(String workoutId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_user_workout WHERE user_workout_id = ?',
      [workoutId],
    );
    if (rows.isEmpty) return null;
    return Workout.fromMap(rows.first);
  }

  /// The most recently logged set for this exercise (any workout, any
  /// variation) — used to prefill weight/variation/volume-type defaults when
  /// the user selects an exercise while logging a new set.
  Future<WorkoutSet?> findLastSetForExercise(
      String userId, String exerciseId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*
      FROM fact_workout_set s
      INNER JOIN fact_user_workout w ON w.user_workout_id = s.user_workout_id
      WHERE w.user_id = ? AND s.custom_exercise_id = ?
      ORDER BY w.user_workout_created_date DESC, s.workout_set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId],
    );
    if (rows.isEmpty) return null;
    return WorkoutSet.fromMap(rows.first);
  }
}
