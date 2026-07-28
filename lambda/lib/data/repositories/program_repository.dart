import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_set.dart';
import '../models/planned_workout.dart';
import '../models/program.dart';

const _uuid = Uuid();

/// Turns a partial `{column: value}` update map into a `SET col = ?, ...`
/// clause plus its bound parameters, for the dynamic partial-update methods
/// below.
(String, List<Object?>) _buildSetClause(Map<String, dynamic> updates) {
  final clause = updates.keys.map((k) => '$k = ?').join(', ');
  return (clause, updates.values.toList());
}

/// Program library CRUD — creating/editing/browsing programs, their planned
/// workouts, and per-set targets. Nothing here is ever hard-deleted
/// (is_active soft-delete only) since fact_workout/fact_workout_set rows
/// can reference these indefinitely for analytics.
class ProgramRepository {
  // ── Programs ─────────────────────────────────────────────────────────────

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
    final id = _uuid.v4();
    final createdDate = DateTime.now();
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
  }) async {
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

  Future<void> archiveProgram(String programId) async {
    await ps.db.execute(
      'UPDATE dim_program SET is_active = 0 WHERE program_id = ?',
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

  Future<void> archivePlannedWorkout(String plannedWorkoutId) async {
    await ps.db.execute(
      'UPDATE dim_planned_workout SET is_active = 0 WHERE planned_workout_id = ?',
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
      SELECT s.*, e.exercise_name, v.variation_name
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
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_set
        (id, planned_set_id, planned_workout_id, user_id, custom_exercise_id, custom_variation_id,
         exercise_sequence_order, planned_set_number, target_weight, target_reps,
         target_duration_seconds, target_notes, is_active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
  }) async {
    final updates = <String, dynamic>{};
    if (exerciseId != null) updates['custom_exercise_id'] = exerciseId;
    if (clearVariation) {
      updates['custom_variation_id'] = null;
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

  Future<void> archivePlannedSet(String plannedSetId) async {
    await ps.db.execute(
      'UPDATE dim_planned_set SET is_active = 0 WHERE planned_set_id = ?',
      [plannedSetId],
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
          '${source.program.name} (Copy)',
          source.program.description,
          source.program.lengthWeeks,
          source.program.progressionMode,
          1,
          DateTime.now().toIso8601String(),
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
               target_duration_seconds, target_notes, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            ],
          );
        }
      }
    });

    return newProgramId;
  }
}
