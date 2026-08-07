import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../shared/utils/unique_name.dart';
import '../models/workout_plan.dart';
import '../models/workout_plan_set.dart';

const _uuid = Uuid();

/// Owns standalone planned workouts (a single session not tied to a program)
/// and their planned sets — mirrors the program planned-workout/set CRUD.
class WorkoutPlanRepository {
  /// Standalone workout names for [userId], used to bump auto-generated
  /// defaults.
  Future<Set<String>> _workoutNames(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT workout_name FROM dim_workout WHERE user_id = ?',
      [userId],
    );
    return rows.map((r) => r['workout_name'] as String).toSet();
  }

  Future<bool> _nameExists(String userId, String name,
      {String? excludeWorkoutId}) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM dim_workout
      WHERE user_id = ? AND LOWER(workout_name) = LOWER(?)
        ${excludeWorkoutId != null ? 'AND workout_id != ?' : ''}
      LIMIT 1
      ''',
      [
        userId,
        name.trim(),
        ?excludeWorkoutId,
      ],
    );
    return rows.isNotEmpty;
  }

  Future<void> _assertWorkoutNameUnique(String userId, String name,
      {String? excludeWorkoutId}) async {
    if (await _nameExists(userId, name, excludeWorkoutId: excludeWorkoutId)) {
      throw Exception('A workout named "$name" already exists.');
    }
  }

  Future<List<WorkoutPlan>> fetchWorkouts(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_workout WHERE user_id = ? ORDER BY workout_created_date DESC',
      [userId],
    );
    return rows.map((r) => WorkoutPlan.fromMap(r)).toList();
  }

  /// Creates a standalone workout. When [name] is null the app auto-generates
  /// one ("New Workout", "New Workout 2", …) bumped against the local mirror
  /// so it never throws; when a user-typed [name] is given, it must be unique.
  ///
  /// Like all name-uniqueness in this app, the check is client-side against
  /// the device's local PowerSync mirror — names are NOT unique at the
  /// database level, so two offline devices can still independently create
  /// (or rename to) the same string and the server accepts a cosmetic
  /// duplicate after sync. Records are keyed by UUID, never by name.
  Future<WorkoutPlan> createWorkout(String userId,
      {String? name, String? notes}) async {
    var finalName = name;
    if (finalName == null) {
      final names = await _workoutNames(userId);
      finalName = uniqueName('New Workout', names);
    } else {
      await _assertWorkoutNameUnique(userId, finalName);
    }
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO dim_workout
        (id, workout_id, user_id, workout_name, workout_notes, is_active, workout_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, finalName, notes, 1, createdDate.toIso8601String()],
    );
    return WorkoutPlan(
      workoutId: id,
      userId: userId,
      name: finalName,
      notes: notes,
      isActive: true,
      createdDate: createdDate,
    );
  }

  Future<void> updateWorkout(String workoutId,
      {String? name, String? notes, String userId = ''}) async {
    if (name != null) {
      await _assertWorkoutNameUnique(userId, name, excludeWorkoutId: workoutId);
    }
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

  Future<void> deleteWorkout(String workoutId) async {
    await ps.db.execute(
      'DELETE FROM dim_workout_set WHERE workout_id = ?',
      [workoutId],
    );
    await ps.db.execute(
      'DELETE FROM dim_workout WHERE workout_id = ?',
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

  Future<void> deleteSet(String setId) async {
    await ps.db.execute(
      'DELETE FROM dim_workout_set WHERE workout_set_id = ?',
      [setId],
    );
  }

  /// Deep-copies a standalone workout with all its sets.
  Future<String> duplicateWorkout(String userId, WorkoutPlan source) async {
    final sets = await fetchSets(source.workoutId);

    final names = await _workoutNames(userId);
    final copyName = uniqueName('${source.name} (Copy)', names,
        numbered: (n) => '${source.name} (Copy $n)');

    final newId = _uuid.v4();
    final createdDate = DateTime.now().toUtc();

    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_workout
          (id, workout_id, user_id, workout_name, workout_notes, is_active, workout_created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        [newId, newId, userId, copyName, source.notes, 1, createdDate.toIso8601String()],
      );

      for (final set in sets) {
        final newSetId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_workout_set
            (id, workout_set_id, workout_id, user_id, custom_exercise_id,
             custom_variation_id, exercise_sequence_order, workout_set_number,
             target_weight, target_reps, target_duration_seconds, target_notes,
             exercise_name, variation_name, is_active)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSetId, newSetId, newId, userId,
            set.exerciseId, set.variationId,
            set.exerciseSequenceOrder, set.setNumber,
            set.targetWeight, jsonEncode(set.targetReps),
            jsonEncode(set.targetDuration), set.targetNotes,
            set.exerciseName, set.variationName, 1,
          ],
        );
      }
    });

    return newId;
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
