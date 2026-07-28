import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/workout.dart';
import '../models/workout_set.dart';

const _uuid = Uuid();

class WorkoutRepository {
  Future<String> createWorkout(
    String userId, {
    String? preNotes,
    String? programId,
    String? programRunId,
    String? plannedWorkoutId,
  }) async {
    final workoutId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_workout
        (id, user_workout_id, user_id, user_pre_workout_notes, user_workout_created_date,
         is_active, program_id, program_run_id, planned_workout_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        workoutId,
        workoutId,
        userId,
        preNotes?.isNotEmpty == true ? preNotes : null,
        DateTime.now().toIso8601String(),
        1,
        programId,
        programRunId,
        plannedWorkoutId,
      ],
    );
    return workoutId;
  }

  Future<void> endWorkout(String workoutId, {String? postNotes, int? feeling}) async {
    await ps.db.execute(
      'UPDATE fact_workout SET is_active = 0, user_post_workout_notes = ?, user_workout_feeling = ? WHERE user_workout_id = ?',
      [postNotes?.isNotEmpty == true ? postNotes : null, feeling, workoutId],
    );
  }

  Future<void> cancelWorkout(String workoutId) async {
    await ps.db.execute(
      'DELETE FROM fact_workout_set WHERE user_workout_id = ?',
      [workoutId],
    );
    await ps.db.execute(
      'DELETE FROM fact_workout WHERE user_workout_id = ?',
      [workoutId],
    );
  }

  Future<String?> getActiveWorkoutId(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT user_workout_id FROM fact_workout WHERE user_id = ? AND is_active = 1 LIMIT 1',
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
    String? programId,
    String? plannedSetId,
  }) async {
    final setId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_workout_set
        (id, workout_set_id, user_workout_id, custom_exercise_id, custom_variation_id,
         workout_set_number, workout_set_weight, workout_set_reps, workout_set_duration_seconds,
         workout_set_notes, program_id, planned_set_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        setId,
        setId,
        workoutId,
        exerciseId,
        variationId,
        setNumber,
        weight,
        jsonEncode(reps),
        jsonEncode(duration),
        notes?.isNotEmpty == true ? notes : null,
        programId,
        plannedSetId,
      ],
    );
    return WorkoutSet(
      setId: setId,
      workoutId: workoutId,
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      duration: duration,
      notes: notes?.isNotEmpty == true ? notes : null,
    );
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
    final setClauses = <String>[];
    final params = <Object?>[];

    if (exerciseId != null) {
      setClauses.add('custom_exercise_id = ?');
      params.add(exerciseId);
    }
    if (clearVariation) {
      setClauses.add('custom_variation_id = ?');
      params.add(null);
    } else if (variationId != null) {
      setClauses.add('custom_variation_id = ?');
      params.add(variationId);
    }
    if (clearWeight) {
      setClauses.add('workout_set_weight = ?');
      params.add(null);
    } else if (weight != null) {
      setClauses.add('workout_set_weight = ?');
      params.add(weight);
    }
    if (reps != null) {
      setClauses.add('workout_set_reps = ?');
      params.add(jsonEncode(reps));
    }
    if (duration != null) {
      setClauses.add('workout_set_duration_seconds = ?');
      params.add(jsonEncode(duration));
    }
    if (clearNotes) {
      setClauses.add('workout_set_notes = ?');
      params.add(null);
    } else if (notes != null) {
      setClauses.add('workout_set_notes = ?');
      params.add(notes.isNotEmpty ? notes : null);
    }
    if (setClauses.isEmpty) return;

    params.add(setId);
    await ps.db.execute(
      'UPDATE fact_workout_set SET ${setClauses.join(', ')} WHERE workout_set_id = ?',
      params,
    );
  }

  Future<void> deleteSet(String setId) async {
    await ps.db.execute(
      'DELETE FROM fact_workout_set WHERE workout_set_id = ?',
      [setId],
    );
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
      await ps.db.execute(
        'UPDATE fact_workout_set SET workout_set_number = ? WHERE workout_set_id = ?',
        [i + 1, orderedSetIds[i]],
      );
    }
  }

  Future<List<WorkoutWithSets>> loadWorkoutsWithSets(String userId) async {
    final workoutRows = await ps.db.getAll(
      'SELECT * FROM fact_workout WHERE user_id = ? AND is_active = 0 ORDER BY user_workout_created_date DESC',
      [userId],
    );
    if (workoutRows.isEmpty) return [];

    final workouts = workoutRows.map((r) => Workout.fromMap(r)).toList();

    final setRows = await ps.db.getAll(
      '''
      SELECT s.*, e.exercise_name, v.variation_name
      FROM fact_workout_set s
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.user_workout_id IN (
        SELECT user_workout_id FROM fact_workout WHERE user_id = ? AND is_active = 0
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
      INNER JOIN fact_workout w ON w.user_workout_id = s.user_workout_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE w.user_id = ? AND w.is_active = 0
      ORDER BY w.user_workout_created_date DESC, s.workout_set_number
      ''',
      [userId],
    );
    return rows.map((r) => PastSetRow.fromMap(r)).toList();
  }

  Future<Workout?> fetchWorkout(String workoutId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_workout WHERE user_workout_id = ?',
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
      INNER JOIN fact_workout w ON w.user_workout_id = s.user_workout_id
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
