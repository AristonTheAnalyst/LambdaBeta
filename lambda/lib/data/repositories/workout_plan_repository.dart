import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/workout_plan.dart';
import '../models/workout_plan_set.dart';

const _uuid = Uuid();

/// Owns standalone planned workouts (a single session not tied to a program)
/// and their planned sets — mirrors the program planned-workout/set CRUD.
class WorkoutPlanRepository {
  Future<List<WorkoutPlan>> fetchWorkouts(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_workout WHERE user_id = ? AND is_active = 1 ORDER BY workout_created_date DESC',
      [userId],
    );
    return rows.map((r) => WorkoutPlan.fromMap(r)).toList();
  }

  Future<WorkoutPlan> createWorkout(String userId, {required String name, String? notes}) async {
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO dim_workout
        (id, workout_id, user_id, workout_name, workout_notes, is_active, workout_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, name, notes, 1, createdDate.toIso8601String()],
    );
    return WorkoutPlan(
      workoutId: id,
      userId: userId,
      name: name,
      notes: notes,
      isActive: true,
      createdDate: createdDate,
    );
  }

  Future<void> updateWorkout(String workoutId, {String? name, String? notes}) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['workout_name'] = name;
    if (notes != null) updates['workout_notes'] = notes;
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_workout SET $setClause WHERE workout_id = ?',
      [...updates.values, workoutId],
    );
  }

  Future<void> archiveWorkout(String workoutId) async {
    await ps.db.execute(
      'UPDATE dim_workout SET is_active = 0 WHERE workout_id = ?',
      [workoutId],
    );
  }

  Future<List<WorkoutPlanSet>> fetchSets(String workoutId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, e.exercise_name, v.variation_name
      FROM dim_workout_set s
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.workout_id = ? AND s.is_active = 1
      ORDER BY s.exercise_sequence_order, s.workout_set_number
      ''',
      [workoutId],
    );
    return rows.map((r) => WorkoutPlanSet.fromMap(r)).toList();
  }

  Future<WorkoutPlanSet> createSet(
    String userId,
    String workoutId, {
    required String exerciseId,
    String? exerciseName,
    String? variationId,
    String? variationName,
    required int exerciseSequenceOrder,
    required int setNumber,
    num? targetWeight,
    List<num> targetReps = const [],
    List<num> targetDuration = const [],
    String? targetNotes,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_workout_set
        (id, workout_set_id, workout_id, user_id, custom_exercise_id, custom_variation_id,
         exercise_sequence_order, workout_set_number, target_weight, target_reps,
         target_duration_seconds, target_notes, exercise_name, variation_name, is_active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id, id, workoutId, userId, exerciseId, variationId,
        exerciseSequenceOrder, setNumber, targetWeight,
        jsonEncode(targetReps), jsonEncode(targetDuration),
        targetNotes, exerciseName, variationName, 1,
      ],
    );
    return WorkoutPlanSet(
      setId: id,
      workoutId: workoutId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseSequenceOrder: exerciseSequenceOrder,
      setNumber: setNumber,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetDuration: targetDuration,
      targetNotes: targetNotes,
      exerciseName: exerciseName,
      variationName: variationName,
    );
  }

  Future<void> updateSet(
    String setId, {
    num? targetWeight,
    bool clearWeight = false,
    List<num>? targetReps,
    List<num>? targetDuration,
    String? targetNotes,
    bool clearNotes = false,
  }) async {
    final updates = <String, dynamic>{};
    if (clearWeight) {
      updates['target_weight'] = null;
    } else if (targetWeight != null) {
      updates['target_weight'] = targetWeight;
    }
    if (targetReps != null) updates['target_reps'] = jsonEncode(targetReps);
    if (targetDuration != null) {
      updates['target_duration_seconds'] = jsonEncode(targetDuration);
    }
    if (clearNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_workout_set SET $setClause WHERE workout_set_id = ?',
      [...updates.values, setId],
    );
  }

  Future<void> archiveSet(String setId) async {
    await ps.db.execute(
      'UPDATE dim_workout_set SET is_active = 0 WHERE workout_set_id = ?',
      [setId],
    );
  }

  /// Swaps the exercise sequence order between two exercises' sets in a
  /// workout (for exercise-tab reordering).
  Future<void> swapSetExerciseOrders(String workoutId, int orderA, int orderB) async {
    await ps.db.execute(
      '''
      UPDATE dim_workout_set
        SET exercise_sequence_order = CASE exercise_sequence_order
          WHEN ? THEN ? ELSE ? END
      WHERE workout_id = ? AND is_active = 1
      ''',
      [orderA, orderB, orderA, workoutId],
    );
  }
}
