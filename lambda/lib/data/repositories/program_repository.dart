import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_set.dart';
import '../models/planned_workout.dart';
import '../models/program.dart';
import '../models/program_goal.dart';

const _uuid = Uuid();

/// Turns a partial `{column: value}` update map into a `SET col = ?, ...`
/// clause plus its bound parameters, for the dynamic partial-update methods
/// below.
(String, List<Object?>) _buildSetClause(Map<String, dynamic> updates) {
  final clause = updates.keys.map((k) => '$k = ?').join(', ');
  return (clause, updates.values.toList());
}

/// Program library CRUD — creating/editing/browsing programs, their planned
/// workouts, and per-set targets.  Deletes ARE hard deletes because every
/// completed workout already denormalises `program_name` and
/// `planned_workout_name` into its own `fact_workout` row, so there are no
/// dangling references to protect.
class ProgramRepository {
  // ── Programs ─────────────────────────────────────────────────────────────

  /// Throws if another active program owned by `userId` already has [name].
  Future<void> _assertProgramNameUnique(
      String userId, String name, {String? excludeProgramId}) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM dim_program
      WHERE user_id = ? AND LOWER(program_name) = LOWER(?)
        ${excludeProgramId != null ? 'AND program_id != ?' : ''}
      LIMIT 1
      ''',
      [
        userId,
        name.trim(),
        ?excludeProgramId,
      ],
    );
    if (rows.isNotEmpty) {
      throw Exception('A program named "$name" already exists.');
    }
  }

  Future<List<Program>> fetchPrograms(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program WHERE user_id = ? AND is_active = 1 ORDER BY program_created_date DESC',
      [userId],
    );
    return rows.map((r) => Program.fromMap(r)).toList();
  }

  Future<Program?> fetchProgram(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program WHERE program_id = ?',
      [programId],
    );
    if (rows.isEmpty) return null;
    return Program.fromMap(rows.first);
  }

  Future<Program> createProgram(
    String userId, {
    required String name,
    String? description,
    int? lengthWeeks,
    String progressionMode = 'sequential',
  }) async {
    await _assertProgramNameUnique(userId, name);
    final id = _uuid.v4();
    // .toUtc() avoids a naive local-time string being reinterpreted as UTC
    // by Postgres's timestamptz column (see WorkoutRepository.createWorkout).
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO dim_program
        (id, program_id, user_id, program_name, program_description,
         program_length_weeks, progression_mode, is_active, program_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        name,
        description,
        lengthWeeks,
        progressionMode,
        1,
        createdDate.toIso8601String(),
      ],
    );
    return Program(
      programId: id,
      userId: userId,
      name: name,
      description: description,
      lengthWeeks: lengthWeeks,
      progressionMode: progressionMode,
      isActive: true,
      createdDate: createdDate,
    );
  }

  Future<void> updateProgram(
    String programId, {
    String? name,
    String? description,
    int? lengthWeeks,
    String? progressionMode,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertProgramNameUnique(userId, name, excludeProgramId: programId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['program_name'] = name;
    if (description != null) updates['program_description'] = description;
    if (lengthWeeks != null) updates['program_length_weeks'] = lengthWeeks;
    if (progressionMode != null) updates['progression_mode'] = progressionMode;
    if (updates.isEmpty) return;
    final (setClause, params) = _buildSetClause(updates);
    await ps.db.execute(
      'UPDATE dim_program SET $setClause WHERE program_id = ?',
      [...params, programId],
    );
  }

  Future<void> deleteProgram(String programId) async {
    // Delete planned sets for every planned workout under this program.
    await ps.db.execute(
      '''
      DELETE FROM dim_planned_set
      WHERE planned_workout_id IN (
        SELECT planned_workout_id FROM dim_planned_workout WHERE program_id = ?
      )
      ''',
      [programId],
    );
    // Delete the planned workouts themselves.
    await ps.db.execute(
      'DELETE FROM dim_planned_workout WHERE program_id = ?',
      [programId],
    );
    // Delete program goals.
    await ps.db.execute(
      'DELETE FROM dim_program_goal WHERE program_id = ?',
      [programId],
    );
    // Delete the program.
    await ps.db.execute(
      'DELETE FROM dim_program WHERE program_id = ?',
      [programId],
    );
  }

  // ── Planned workouts ─────────────────────────────────────────────────────

  Future<List<PlannedWorkout>> fetchPlannedWorkouts(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_planned_workout WHERE program_id = ? AND is_active = 1 ORDER BY sequence_order',
      [programId],
    );
    return rows.map((r) => PlannedWorkout.fromMap(r)).toList();
  }

  Future<PlannedWorkout> createPlannedWorkout(
    String userId,
    String programId, {
    required String name,
    String? notes,
    required int sequenceOrder,
    int? dayOfWeek,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_workout
        (id, planned_workout_id, program_id, user_id, planned_workout_name,
         planned_workout_notes, sequence_order, day_of_week, is_active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, programId, userId, name, notes, sequenceOrder, dayOfWeek, 1],
    );
    return PlannedWorkout(
      plannedWorkoutId: id,
      programId: programId,
      userId: userId,
      name: name,
      notes: notes,
      sequenceOrder: sequenceOrder,
      dayOfWeek: dayOfWeek,
      isActive: true,
    );
  }

  Future<void> updatePlannedWorkout(
    String plannedWorkoutId, {
    String? name,
    String? notes,
    int? sequenceOrder,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['planned_workout_name'] = name;
    if (notes != null) updates['planned_workout_notes'] = notes;
    if (sequenceOrder != null) updates['sequence_order'] = sequenceOrder;
    if (clearDayOfWeek) {
      updates['day_of_week'] = null;
    } else if (dayOfWeek != null) {
      updates['day_of_week'] = dayOfWeek;
    }
    if (updates.isEmpty) return;
    final (setClause, params) = _buildSetClause(updates);
    await ps.db.execute(
      'UPDATE dim_planned_workout SET $setClause WHERE planned_workout_id = ?',
      [...params, plannedWorkoutId],
    );
  }

  Future<void> deletePlannedWorkout(String plannedWorkoutId) async {
    await ps.db.execute(
      'DELETE FROM dim_planned_set WHERE planned_workout_id = ?',
      [plannedWorkoutId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_workout WHERE planned_workout_id = ?',
      [plannedWorkoutId],
    );
  }

  Future<void> reorderPlannedWorkouts(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await ps.db.execute(
        'UPDATE dim_planned_workout SET sequence_order = ? WHERE planned_workout_id = ?',
        [i + 1, orderedIds[i]],
      );
    }
  }

  // ── Planned sets ─────────────────────────────────────────────────────────

  Future<List<PlannedSet>> fetchPlannedSets(String plannedWorkoutId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*,
             COALESCE(s.exercise_name, e.exercise_name) AS exercise_name,
             COALESCE(s.variation_name, v.variation_name) AS variation_name
      FROM dim_planned_set s
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.planned_workout_id = ? AND s.is_active = 1
      ORDER BY s.exercise_sequence_order, s.planned_set_number
      ''',
      [plannedWorkoutId],
    );
    return rows.map((r) => PlannedSet.fromMap(r)).toList();
  }

  Future<PlannedSet> createPlannedSet(
    String userId,
    String plannedWorkoutId, {
    required String exerciseId,
    String? variationId,
    required int exerciseSequenceOrder,
    required int setNumber,
    double? targetWeight,
    List<num> targetReps = const [],
    List<num> targetDuration = const [],
    String? targetNotes,
    String? exerciseName,
    String? variationName,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_set
        (id, planned_set_id, planned_workout_id, user_id, custom_exercise_id, custom_variation_id,
         exercise_sequence_order, planned_set_number, target_weight, target_reps,
         target_duration_seconds, target_notes, is_active, exercise_name, variation_name)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        plannedWorkoutId,
        userId,
        exerciseId,
        variationId,
        exerciseSequenceOrder,
        setNumber,
        targetWeight,
        jsonEncode(targetReps),
        jsonEncode(targetDuration),
        targetNotes,
        1,
        exerciseName,
        variationName,
      ],
    );
    return PlannedSet(
      plannedSetId: id,
      plannedWorkoutId: plannedWorkoutId,
      userId: userId,
      exerciseId: exerciseId,
      variationId: variationId,
      exerciseSequenceOrder: exerciseSequenceOrder,
      setNumber: setNumber,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetDuration: targetDuration,
      targetNotes: targetNotes,
      isActive: true,
    );
  }

  Future<void> updatePlannedSet(
    String plannedSetId, {
    String? exerciseId,
    String? variationId,
    bool clearVariation = false,
    int? exerciseSequenceOrder,
    int? setNumber,
    double? targetWeight,
    bool clearTargetWeight = false,
    List<num>? targetReps,
    List<num>? targetDuration,
    String? targetNotes,
    bool clearTargetNotes = false,
    String? exerciseName,
    String? variationName,
  }) async {
    final updates = <String, dynamic>{};
    if (exerciseId != null) updates['custom_exercise_id'] = exerciseId;
    if (exerciseName != null) updates['exercise_name'] = exerciseName;
    if (clearVariation) {
      updates['custom_variation_id'] = null;
      updates['variation_name'] = null;
    } else if (variationId != null) {
      updates['custom_variation_id'] = variationId;
    }
    if (exerciseSequenceOrder != null) {
      updates['exercise_sequence_order'] = exerciseSequenceOrder;
    }
    if (setNumber != null) updates['planned_set_number'] = setNumber;
    if (clearTargetWeight) {
      updates['target_weight'] = null;
    } else if (targetWeight != null) {
      updates['target_weight'] = targetWeight;
    }
    if (targetReps != null) updates['target_reps'] = jsonEncode(targetReps);
    if (targetDuration != null) {
      updates['target_duration_seconds'] = jsonEncode(targetDuration);
    }
    if (clearTargetNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    final (setClause, params) = _buildSetClause(updates);
    await ps.db.execute(
      'UPDATE dim_planned_set SET $setClause WHERE planned_set_id = ?',
      [...params, plannedSetId],
    );
  }

  Future<void> deletePlannedSet(String plannedSetId) async {
    await ps.db.execute(
      'DELETE FROM dim_planned_set WHERE planned_set_id = ?',
      [plannedSetId],
    );
  }

  /// Swaps exerciseSequenceOrder for all planned sets between two exercises
  /// within the same workout, effectively reordering the exercise tabs.
  Future<void> swapPlannedExerciseOrders(
    String plannedWorkoutId,
    int orderA,
    int orderB,
  ) async {
    if (orderA == orderB) return;
    // Use a temp value to avoid collisions during the swap
    const temp = -9999;
    await ps.db.execute(
      'UPDATE dim_planned_set SET exercise_sequence_order = ? WHERE planned_workout_id = ? AND exercise_sequence_order = ?',
      [temp, plannedWorkoutId, orderA],
    );
    await ps.db.execute(
      'UPDATE dim_planned_set SET exercise_sequence_order = ? WHERE planned_workout_id = ? AND exercise_sequence_order = ?',
      [orderA, plannedWorkoutId, orderB],
    );
    await ps.db.execute(
      'UPDATE dim_planned_set SET exercise_sequence_order = ? WHERE planned_workout_id = ? AND exercise_sequence_order = ?',
      [orderB, plannedWorkoutId, temp],
    );
  }

  Future<void> reorderPlannedSets(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await ps.db.execute(
        'UPDATE dim_planned_set SET planned_set_number = ? WHERE planned_set_id = ?',
        [i + 1, orderedIds[i]],
      );
    }
  }

  /// Deep-copies one planned workout (and its sets) within the same program.
  /// The copy gets a fresh UUID, "(Copy)" suffix on the name, and is placed
  /// immediately after the source in sequence order.
  Future<String> duplicatePlannedWorkout(
      String userId, PlannedWorkout source) async {
    final sets = await fetchPlannedSets(source.plannedWorkoutId);

    final newId = _uuid.v4();
    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_planned_workout
          (id, planned_workout_id, program_id, user_id, planned_workout_name,
           planned_workout_notes, sequence_order, day_of_week, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newId, newId, source.programId, userId,
          '${source.name} (Copy)', source.notes,
          source.sequenceOrder + 1, source.dayOfWeek, 1,
        ],
      );

      // Bump later workouts' sequence_order so the copy doesn't clobber.
      await tx.execute(
        '''
        UPDATE dim_planned_workout
        SET sequence_order = sequence_order + 1
        WHERE program_id = ? AND sequence_order > ?
        ''',
        [source.programId, source.sequenceOrder],
      );

      for (final set in sets) {
        final newSetId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_set
            (id, planned_set_id, planned_workout_id, user_id, custom_exercise_id,
             custom_variation_id, exercise_sequence_order, planned_set_number,
             target_weight, target_reps, target_duration_seconds, target_notes,
             is_active, exercise_name, variation_name)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSetId, newSetId, newId, userId,
            set.exerciseId, set.variationId,
            set.exerciseSequenceOrder, set.setNumber,
            set.targetWeight, jsonEncode(set.targetReps),
            jsonEncode(set.targetDuration), set.targetNotes,
            1, set.exerciseName, set.variationName,
          ],
        );
      }
    });

    return newId;
  }

  /// Returns a unique copy name, e.g. "Push Day (Copy)" → "Push Day (Copy 2)"
  /// if "(Copy)" already exists.
  Future<String> _uniqueCopyName(
      String userId, String baseName, Future<bool> Function(String userId, String name) exists) async {
    final copy = '$baseName (Copy)';
    if (!await exists(userId, copy)) return copy;
    for (var i = 2;; i++) {
      final numbered = '$baseName (Copy $i)';
      if (!await exists(userId, numbered)) return numbered;
    }
  }

  // ── Composite reads / duplication ────────────────────────────────────────

  Future<ProgramWithWorkouts?> fetchProgramWithWorkouts(String programId) async {
    final program = await fetchProgram(programId);
    if (program == null) return null;
    final workouts = await fetchPlannedWorkouts(programId);
    return ProgramWithWorkouts(program: program, plannedWorkouts: workouts);
  }

  /// Deep-copies a program (and its planned workouts/sets) with fresh UUIDs.
  /// The copy is a brand-new program with no run history of its own. All
  /// inserts happen in a single local transaction so the copy either lands
  /// completely or not at all.
  Future<String> duplicateProgram(String userId, String programId) async {
    final source = await fetchProgramWithWorkouts(programId);
    if (source == null) throw StateError('Program not found: $programId');

    // Read every source workout's sets up front — querying ps.db from inside
    // a writeTransaction callback below could contend with the write lock
    // that transaction holds.
    final setsByWorkoutId = <String, List<PlannedSet>>{};
    for (final workout in source.plannedWorkouts) {
      setsByWorkoutId[workout.plannedWorkoutId] =
          await fetchPlannedSets(workout.plannedWorkoutId);
    }

    final name = await _uniqueCopyName(userId, source.program.name,
        (uid, n) async {
      final rows = await ps.db.getAll(
        'SELECT 1 FROM dim_program WHERE user_id = ? AND LOWER(program_name) = LOWER(?) LIMIT 1',
        [uid, n],
      );
      return rows.isNotEmpty;
    });

    final newProgramId = _uuid.v4();

    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_program
          (id, program_id, user_id, program_name, program_description,
           program_length_weeks, progression_mode, is_active, program_created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newProgramId,
          newProgramId,
          userId,
          name,
          source.program.description,
          source.program.lengthWeeks,
          source.program.progressionMode,
          1,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );

      for (final workout in source.plannedWorkouts) {
        final newWorkoutId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_workout
            (id, planned_workout_id, program_id, user_id, planned_workout_name,
             planned_workout_notes, sequence_order, day_of_week, is_active)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newWorkoutId,
            newWorkoutId,
            newProgramId,
            userId,
            workout.name,
            workout.notes,
            workout.sequenceOrder,
            workout.dayOfWeek,
            1,
          ],
        );

        final sets = setsByWorkoutId[workout.plannedWorkoutId] ?? const [];
        for (final set in sets) {
          final newSetId = _uuid.v4();
          await tx.execute(
            '''
            INSERT INTO dim_planned_set
              (id, planned_set_id, planned_workout_id, user_id, custom_exercise_id, custom_variation_id,
               exercise_sequence_order, planned_set_number, target_weight, target_reps,
               target_duration_seconds, target_notes, is_active, exercise_name, variation_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              newSetId,
              newSetId,
              newWorkoutId,
              userId,
              set.exerciseId,
              set.variationId,
              set.exerciseSequenceOrder,
              set.setNumber,
              set.targetWeight,
              jsonEncode(set.targetReps),
              jsonEncode(set.targetDuration),
              set.targetNotes,
              1,
              set.exerciseName,
              set.variationName,
            ],
          );
        }
      }
    });

    return newProgramId;
  }

  Future<void> createProgramGoal(String userId, String programId, ProgramGoal goal) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_program_goal
        (id, program_goal_id, program_id, user_id, goal_text, custom_exercise_id,
         target_weight, target_reps, goal_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id, id, programId, userId, goal.text, goal.exerciseId,
        goal.targetWeight, goal.targetReps, DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<List<ProgramGoal>> fetchProgramGoals(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program_goal WHERE program_id = ? ORDER BY goal_created_date DESC',
      [programId],
    );
    return rows.map((r) => ProgramGoal.fromMap(r)).toList();
  }
}
