import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_set.dart';
import '../models/planned_workout.dart';
import '../models/program.dart';

const _uuid = Uuid();

/// Program library CRUD — creating/editing/browsing programs, their planned
/// workouts, and per-set targets. Nothing here is ever hard-deleted
/// (is_active soft-delete only) since fact_workout/fact_workout_set rows
/// can reference these indefinitely for analytics.
class ProgramRepository {
  final _client = Supabase.instance.client;

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
    final data = await _client
        .from('dim_program')
        .insert({
          'program_id': _uuid.v4(),
          'user_id': userId,
          'program_name': name,
          'program_description': description,
          'program_length_weeks': lengthWeeks,
          'progression_mode': progressionMode,
          'is_active': true,
        })
        .select()
        .single();
    return Program.fromMap(data);
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
    await _client.from('dim_program').update(updates).eq('program_id', programId);
  }

  Future<void> archiveProgram(String programId) async {
    await _client
        .from('dim_program')
        .update({'is_active': false}).eq('program_id', programId);
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
    final data = await _client
        .from('dim_planned_workout')
        .insert({
          'planned_workout_id': _uuid.v4(),
          'program_id': programId,
          'user_id': userId,
          'planned_workout_name': name,
          'planned_workout_notes': notes,
          'sequence_order': sequenceOrder,
          'day_of_week': dayOfWeek,
          'is_active': true,
        })
        .select()
        .single();
    return PlannedWorkout.fromMap(data);
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
    await _client
        .from('dim_planned_workout')
        .update(updates)
        .eq('planned_workout_id', plannedWorkoutId);
  }

  Future<void> archivePlannedWorkout(String plannedWorkoutId) async {
    await _client
        .from('dim_planned_workout')
        .update({'is_active': false}).eq('planned_workout_id', plannedWorkoutId);
  }

  Future<void> reorderPlannedWorkouts(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('dim_planned_workout')
          .update({'sequence_order': i + 1}).eq('planned_workout_id', orderedIds[i]);
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
    final data = await _client
        .from('dim_planned_set')
        .insert({
          'planned_set_id': _uuid.v4(),
          'planned_workout_id': plannedWorkoutId,
          'user_id': userId,
          'custom_exercise_id': exerciseId,
          'custom_variation_id': variationId,
          'exercise_sequence_order': exerciseSequenceOrder,
          'planned_set_number': setNumber,
          'target_weight': targetWeight,
          'target_reps': targetReps,
          'target_duration_seconds': targetDuration,
          'target_notes': targetNotes,
          'is_active': true,
        })
        .select()
        .single();
    return PlannedSet.fromMap(data);
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
    if (targetReps != null) updates['target_reps'] = targetReps;
    if (targetDuration != null) {
      updates['target_duration_seconds'] = targetDuration;
    }
    if (clearTargetNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    await _client
        .from('dim_planned_set')
        .update(updates)
        .eq('planned_set_id', plannedSetId);
  }

  Future<void> archivePlannedSet(String plannedSetId) async {
    await _client
        .from('dim_planned_set')
        .update({'is_active': false}).eq('planned_set_id', plannedSetId);
  }

  Future<void> reorderPlannedSets(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('dim_planned_set')
          .update({'planned_set_number': i + 1}).eq('planned_set_id', orderedIds[i]);
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
  /// The copy is a brand-new program with no run history of its own.
  Future<String> duplicateProgram(String userId, String programId) async {
    final source = await fetchProgramWithWorkouts(programId);
    if (source == null) throw StateError('Program not found: $programId');

    final newProgramId = _uuid.v4();
    await _client.from('dim_program').insert({
      'program_id': newProgramId,
      'user_id': userId,
      'program_name': '${source.program.name} (Copy)',
      'program_description': source.program.description,
      'program_length_weeks': source.program.lengthWeeks,
      'progression_mode': source.program.progressionMode,
      'is_active': true,
    });

    for (final workout in source.plannedWorkouts) {
      final newWorkoutId = _uuid.v4();
      await _client.from('dim_planned_workout').insert({
        'planned_workout_id': newWorkoutId,
        'program_id': newProgramId,
        'user_id': userId,
        'planned_workout_name': workout.name,
        'planned_workout_notes': workout.notes,
        'sequence_order': workout.sequenceOrder,
        'day_of_week': workout.dayOfWeek,
        'is_active': true,
      });

      final sets = await fetchPlannedSets(workout.plannedWorkoutId);
      for (final set in sets) {
        await _client.from('dim_planned_set').insert({
          'planned_set_id': _uuid.v4(),
          'planned_workout_id': newWorkoutId,
          'user_id': userId,
          'custom_exercise_id': set.exerciseId,
          'custom_variation_id': set.variationId,
          'exercise_sequence_order': set.exerciseSequenceOrder,
          'planned_set_number': set.setNumber,
          'target_weight': set.targetWeight,
          'target_reps': set.targetReps,
          'target_duration_seconds': set.targetDuration,
          'target_notes': set.targetNotes,
          'is_active': true,
        });
      }
    }

    return newProgramId;
  }
}
