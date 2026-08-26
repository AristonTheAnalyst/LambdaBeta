import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../shared/utils/unique_name.dart';
import '../models/planned_session.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session_program.dart';

const _uuid = Uuid();

/// Owns planned sessions (session templates — standalone or program-attached
/// via the join table) and their exercise groups + planned sets. Dimensions
/// are soft-deleted via is_archived so logged history that references them
/// never dangles; join-table rows hard-delete (nothing references them).
class PlannedSessionRepository {
  /// Planned session names for [userId], used to bump auto-generated defaults.
  Future<Set<String>> _sessionNames(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT name FROM dim_planned_session WHERE user_id = ? AND is_archived = 0',
      [userId],
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  Future<bool> _nameExists(
    String userId,
    String name, {
    String? excludeSessionId,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM dim_planned_session
      WHERE user_id = ? AND is_archived = 0 AND LOWER(name) = LOWER(?)
        ${excludeSessionId != null ? 'AND session_id != ?' : ''}
      LIMIT 1
      ''',
      [userId, name.trim(), ?excludeSessionId],
    );
    return rows.isNotEmpty;
  }

  Future<void> _assertSessionNameUnique(
    String userId,
    String name, {
    String? excludeSessionId,
  }) async {
    if (await _nameExists(userId, name, excludeSessionId: excludeSessionId)) {
      throw Exception('A session named "$name" already exists.');
    }
  }

  /// Fetches planned sessions — standalone (no program link) or attached to
  /// [programId] via the join table.
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
  }) async {
    final rows = await ps.db.getAll(
      programId != null
          ? '''
            SELECT dps.*, psp.sequence_order, psp.day_of_week, psp.week_offset
            FROM dim_planned_session dps
            JOIN dim_planned_session_program psp
              ON psp.planned_session_id = dps.session_id
            WHERE dps.user_id = ? AND psp.program_id = ? AND dps.is_archived = 0
            ORDER BY psp.sequence_order NULLS LAST, dps.created_date
            '''
          : '''
            SELECT * FROM dim_planned_session dps
            WHERE dps.user_id = ? AND dps.is_archived = 0
              AND NOT EXISTS (
                SELECT 1 FROM dim_planned_session_program psp
                WHERE psp.planned_session_id = dps.session_id
              )
            ORDER BY dps.created_date DESC
            ''',
      programId != null ? [userId, programId] : [userId],
    );
    return rows.map((r) => PlannedSession.fromMap(r)).toList();
  }

  /// Creates a planned session. When [name] is null the app auto-generates one
  /// ("New Session", "New Session 2", …) bumped against the local mirror so it
  /// never throws; when a user-typed [name] is given, it must be unique.
  ///
  /// Like all name-uniqueness in this app, the check is client-side against
  /// the device's local PowerSync mirror — names are NOT unique at the
  /// database level, so two offline devices can still independently create
  /// (or rename to) the same string and the server accepts a cosmetic
  /// duplicate after sync. Records are keyed by UUID, never by name.
  Future<PlannedSession> createPlannedSession(
    String userId, {
    String? name,
    String? notes,
  }) async {
    var finalName = name;
    if (finalName == null) {
      final names = await _sessionNames(userId);
      finalName = uniqueName('New Session', names);
    } else {
      await _assertSessionNameUnique(userId, finalName);
    }
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session
        (id, session_id, user_id, name, notes, is_archived, created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        finalName,
        notes,
        0,
        createdDate.toIso8601String(),
      ],
    );
    return PlannedSession(
      sessionId: id,
      userId: userId,
      name: finalName,
      notes: notes,
      isArchived: false,
      createdDate: createdDate,
    );
  }

  Future<void> updatePlannedSession(
    String sessionId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertSessionNameUnique(userId, name, excludeSessionId: sessionId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (clearNotes) {
      updates['notes'] = null;
    } else if (notes != null) {
      updates['notes'] = notes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session SET $setClause WHERE session_id = ?',
      [...updates.values, sessionId],
    );
  }

  /// Soft-deletes a planned session, its exercise groups and sets
  /// (is_archived = 1), and hard-deletes its program links.
  Future<void> deletePlannedSession(String sessionId) async {
    await ps.db.execute(
      '''
      UPDATE dim_planned_session_exercise_set SET is_archived = 1
      WHERE planned_exercise_id IN (
        SELECT planned_exercise_id FROM dim_planned_session_exercise
        WHERE planned_session_id = ?
      )
      ''',
      [sessionId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise SET is_archived = 1 WHERE planned_session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session SET is_archived = 1 WHERE session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_session_program WHERE planned_session_id = ?',
      [sessionId],
    );
  }

  /// One template by id — used to restore a session's planned context from
  /// its persisted `planned_session_id` (the template may be standalone or
  /// program-attached; both live in the same table).
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_planned_session WHERE session_id = ? AND is_archived = 0',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return PlannedSession.fromMap(rows.first);
  }

  // ── Exercise groups ────────────────────────────────────────────────────────

  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT pe.*, e.exercise_name AS exercise_name
      FROM dim_planned_session_exercise pe
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = pe.custom_exercise_id
      WHERE pe.planned_session_id = ? AND pe.is_archived = 0
      ORDER BY pe.exercise_order
      ''',
      [plannedSessionId],
    );
    return rows.map((r) => PlannedSessionExercise.fromMap(r)).toList();
  }

  Future<PlannedSessionExercise> createPlannedExercise(
    String userId,
    String plannedSessionId, {
    String? exerciseId,
    required int exerciseOrder,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_exercise
        (id, planned_exercise_id, planned_session_id, user_id, custom_exercise_id,
         exercise_order, is_archived)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        plannedSessionId,
        userId,
        exerciseId,
        exerciseOrder,
        0,
      ],
    );
    return PlannedSessionExercise(
      plannedExerciseId: id,
      plannedSessionId: plannedSessionId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseOrder: exerciseOrder,
    );
  }

  /// Archives an exercise group and its sets.
  Future<void> deletePlannedExercise(String plannedExerciseId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET is_archived = 1 WHERE planned_exercise_id = ?',
      [plannedExerciseId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise SET is_archived = 1 WHERE planned_exercise_id = ?',
      [plannedExerciseId],
    );
  }

  // ── Planned sets ───────────────────────────────────────────────────────────

  /// Fetches a template's active target sets, hydrated with the exercise from
  /// their parent group so consumers don't need to re-join.
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*,
             pe.custom_exercise_id,
             pe.planned_session_id,
             e.exercise_name,
             v.variation_name
      FROM dim_planned_session_exercise_set s
      JOIN dim_planned_session_exercise pe
        ON pe.planned_exercise_id = s.planned_exercise_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = pe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE pe.planned_session_id = ? AND s.is_archived = 0
      ORDER BY pe.exercise_order, s.set_number
      ''',
      [plannedSessionId],
    );
    return rows.map((r) => PlannedSessionExerciseSet.fromMap(r)).toList();
  }

  Future<PlannedSessionExerciseSet> createPlannedSet(
    String userId,
    String plannedExerciseId, {
    required String plannedSessionId,
    String? exerciseId,
    String? variationId,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_exercise_set
        (id, planned_set_id, planned_exercise_id, user_id, custom_variation_id,
         set_number, target_weight, target_reps, target_notes, is_archived)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        plannedExerciseId,
        userId,
        variationId,
        setNumber,
        targetWeight?.isNotEmpty == true ? targetWeight : null,
        targetReps?.isNotEmpty == true ? targetReps : null,
        targetNotes,
        0,
      ],
    );
    return PlannedSessionExerciseSet(
      plannedSetId: id,
      plannedExerciseId: plannedExerciseId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetNotes: targetNotes,
    );
  }

  Future<void> updatePlannedSet(
    String plannedSetId, {
    String? targetWeight,
    bool clearWeight = false,
    String? targetReps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? targetNotes,
    bool clearNotes = false,
  }) async {
    final updates = <String, dynamic>{};
    if (clearWeight) {
      updates['target_weight'] = null;
    } else if (targetWeight != null && targetWeight.isNotEmpty) {
      updates['target_weight'] = targetWeight;
    }
    if (clearReps) {
      updates['target_reps'] = null;
    } else if (targetReps != null && targetReps.isNotEmpty) {
      updates['target_reps'] = targetReps;
    }
    if (clearVariation) {
      updates['custom_variation_id'] = null;
    } else if (variationId != null) {
      updates['custom_variation_id'] = variationId;
    }
    if (clearNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET $setClause WHERE planned_set_id = ?',
      [...updates.values, plannedSetId],
    );
  }

  /// Soft-deletes a planned set.
  Future<void> deletePlannedSet(String plannedSetId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET is_archived = 1 WHERE planned_set_id = ?',
      [plannedSetId],
    );
  }

  /// Consolidates a template to the "exercises are unique per session" rule:
  /// archives no-target rows (the old keep-alive stubs from group creation,
  /// which carry no information), then renumbers exercise_order per group and
  /// set_number within groups by first appearance so the planner's counts
  /// agree with the session preview. Rows with target data are never deleted,
  /// so the user can prune unwanted ones in one place afterwards. Idempotent.
  Future<List<PlannedSessionExerciseSet>> consolidateDuplicateExerciseGroups(
    String plannedSessionId,
  ) async {
    final exercises = await fetchPlannedExercises(plannedSessionId);
    final sets = await fetchPlannedSets(plannedSessionId);
    for (final s in sets) {
      final noTargetData = s.targetWeight == null &&
          s.targetReps == null &&
          (s.targetNotes?.isEmpty ?? true) &&
          s.variationId == null;
      if (noTargetData) {
        await deletePlannedSet(s.plannedSetId);
      }
    }
    final remaining = await fetchPlannedSets(plannedSessionId);
    final orderByExercise = <String, int>{};
    final nextSetNumber = <String, int>{};
    var nextOrder = 0;
    for (final s in remaining) {
      final key = s.plannedExerciseId;
      orderByExercise.putIfAbsent(key, () => ++nextOrder);
      final number = nextSetNumber.putIfAbsent(key, () => 1);
      nextSetNumber[key] = number + 1;
      if (number != s.setNumber) {
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise_set SET set_number = ? WHERE planned_set_id = ?',
          [number, s.plannedSetId],
        );
      }
    }
    for (final e in exercises) {
      final order = orderByExercise[e.plannedExerciseId];
      if (order == null) {
        // Every set of the group was pruned — archive the group itself.
        await deletePlannedExercise(e.plannedExerciseId);
      } else if (order != e.exerciseOrder) {
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise SET exercise_order = ? WHERE planned_exercise_id = ?',
          [order, e.plannedExerciseId],
        );
      }
    }
    return fetchPlannedSets(plannedSessionId);
  }

  /// Deep-copies a planned session with all its exercise groups and sets
  /// (standalone). When [sourceLink] is given, the copy is also linked into
  /// the same program right after the source's slot (sequence bump included).
  Future<String> duplicatePlannedSession(
    String userId,
    PlannedSession source, {
    PlannedSessionProgram? sourceLink,
  }) async {
    final exercises = await fetchPlannedExercises(source.sessionId);
    final sets = await fetchPlannedSets(source.sessionId);

    final names = await _sessionNames(userId);
    final copyName = uniqueName(
      '${source.name} (Copy)',
      names,
      numbered: (n) => '${source.name} (Copy $n)',
    );

    final newId = _uuid.v4();
    final createdDate = DateTime.now().toUtc();

    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_planned_session
          (id, session_id, user_id, name, notes, is_archived, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newId,
          newId,
          userId,
          copyName,
          source.notes,
          0,
          createdDate.toIso8601String(),
        ],
      );

      for (final exercise in exercises) {
        final newExerciseId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session_exercise
            (id, planned_exercise_id, planned_session_id, user_id,
             custom_exercise_id, exercise_order, is_archived)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newExerciseId,
            newExerciseId,
            newId,
            userId,
            exercise.exerciseId,
            exercise.exerciseOrder,
            0,
          ],
        );

        final exerciseSets = sets
            .where((s) => s.plannedExerciseId == exercise.plannedExerciseId)
            .toList();
        for (final set in exerciseSets) {
          final newSetId = _uuid.v4();
          await tx.execute(
            '''
            INSERT INTO dim_planned_session_exercise_set
              (id, planned_set_id, planned_exercise_id, user_id,
               custom_variation_id, set_number, target_weight, target_reps,
               target_notes, is_archived)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              newSetId,
              newSetId,
              newExerciseId,
              userId,
              set.variationId,
              set.setNumber,
              set.targetWeight,
              set.targetReps,
              set.targetNotes,
              0,
            ],
          );
        }
      }

      if (sourceLink != null) {
        // Bump later slots so the copy doesn't clobber sequence order.
        await tx.execute(
          '''
          UPDATE dim_planned_session_program
          SET sequence_order = sequence_order + 1
          WHERE program_id = ? AND sequence_order > ?
          ''',
          [sourceLink.programId, sourceLink.sequenceOrder ?? 0],
        );
        final newLinkId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session_program
            (id, planned_session_program_id, program_id, planned_session_id,
             user_id, sequence_order, day_of_week, week_offset)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newLinkId,
            newLinkId,
            sourceLink.programId,
            newId,
            userId,
            (sourceLink.sequenceOrder ?? 0) + 1,
            sourceLink.dayOfWeek,
            sourceLink.weekOffset,
          ],
        );
      }
    });

    return newId;
  }

  /// Swaps the exercise_order between two exercise groups in a planned
  /// session (for exercise-tab reordering).
  Future<void> swapExerciseOrders(
    String plannedSessionId,
    int orderA,
    int orderB,
  ) async {
    await ps.db.execute(
      '''
      UPDATE dim_planned_session_exercise
        SET exercise_order = CASE exercise_order
          WHEN ? THEN ? ELSE ? END
      WHERE planned_session_id = ? AND is_archived = 0
      ''',
      [orderA, orderB, orderA, plannedSessionId],
    );
  }

  /// Renumbers every exercise group's order so each (old order → new index)
  /// entry in [orderToIndex] lands at index+1. Two-phase (shift to
  /// negatives, then assign) so intermediate collisions can't occur.
  Future<void> renumberExerciseOrders(
    String plannedSessionId,
    List<(int, int)> orderToIndex,
  ) async {
    final n = orderToIndex.length;
    for (final (old, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_exercise SET exercise_order = ? '
        'WHERE planned_session_id = ? AND exercise_order = ? AND is_archived = 0',
        [-n - index - 1, plannedSessionId, old],
      );
    }
    for (final (_, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_exercise SET exercise_order = ? '
        'WHERE planned_session_id = ? AND exercise_order = ? AND is_archived = 0',
        [index + 1, plannedSessionId, -n - index - 1],
      );
    }
  }

  // ── Program links (join table) ─────────────────────────────────────────────

  Future<List<PlannedSessionProgram>> fetchProgramLinks(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_planned_session_program WHERE program_id = ? ORDER BY sequence_order NULLS LAST',
      [programId],
    );
    return rows.map((r) => PlannedSessionProgram.fromMap(r)).toList();
  }

  Future<PlannedSessionProgram> createProgramLink(
    String userId, {
    required String programId,
    required String plannedSessionId,
    int? sequenceOrder,
    int? dayOfWeek,
    int? weekOffset,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_program
        (id, planned_session_program_id, program_id, planned_session_id,
         user_id, sequence_order, day_of_week, week_offset)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        programId,
        plannedSessionId,
        userId,
        sequenceOrder,
        dayOfWeek,
        weekOffset,
      ],
    );
    return PlannedSessionProgram(
      plannedSessionProgramId: id,
      programId: programId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      sequenceOrder: sequenceOrder,
      dayOfWeek: dayOfWeek,
      weekOffset: weekOffset,
    );
  }

  Future<void> updateProgramLink(
    String plannedSessionProgramId, {
    int? sequenceOrder,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    int? weekOffset,
    bool clearWeekOffset = false,
  }) async {
    final updates = <String, dynamic>{};
    if (sequenceOrder != null) updates['sequence_order'] = sequenceOrder;
    if (clearDayOfWeek) {
      updates['day_of_week'] = null;
      updates['week_offset'] = null;
    } else {
      if (dayOfWeek != null) updates['day_of_week'] = dayOfWeek;
      if (clearWeekOffset) {
        updates['week_offset'] = null;
      } else if (weekOffset != null) {
        updates['week_offset'] = weekOffset;
      }
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_program SET $setClause WHERE planned_session_program_id = ?',
      [...updates.values, plannedSessionProgramId],
    );
  }

  Future<void> deleteProgramLink(String plannedSessionProgramId) async {
    await ps.db.execute(
      'DELETE FROM dim_planned_session_program WHERE planned_session_program_id = ?',
      [plannedSessionProgramId],
    );
  }
}
