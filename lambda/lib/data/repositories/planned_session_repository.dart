import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../shared/utils/unique_name.dart';
import '../models/planned_session.dart';
import '../models/planned_session_set.dart';

const _uuid = Uuid();

/// Owns planned sessions (session templates — standalone or program-attached)
/// and their planned sets. Dimensions are soft-deleted via is_archived so
/// logged history that references them never dangles.
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

  /// Fetches planned sessions — standalone (programId null) or attached to
  /// [programId].
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
  }) async {
    final rows = await ps.db.getAll(
      programId != null
          ? 'SELECT * FROM dim_planned_session WHERE user_id = ? AND program_id = ? AND is_archived = 0 ORDER BY sequence_order'
          : 'SELECT * FROM dim_planned_session WHERE user_id = ? AND program_id IS NULL AND is_archived = 0 ORDER BY created_date DESC',
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
    String? programId,
    int? sequenceOrder,
    int? dayOfWeek,
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
        (id, session_id, user_id, name, notes, is_archived, created_date,
         program_id, sequence_order, day_of_week)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        finalName,
        notes,
        0,
        createdDate.toIso8601String(),
        programId,
        sequenceOrder,
        dayOfWeek,
      ],
    );
    return PlannedSession(
      sessionId: id,
      userId: userId,
      name: finalName,
      notes: notes,
      isArchived: false,
      programId: programId,
      sequenceOrder: sequenceOrder,
      dayOfWeek: dayOfWeek,
      createdDate: createdDate,
    );
  }

  Future<void> updatePlannedSession(
    String sessionId, {
    String? name,
    String? notes,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertSessionNameUnique(userId, name, excludeSessionId: sessionId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (notes != null) updates['notes'] = notes;
    if (clearDayOfWeek) {
      updates['day_of_week'] = null;
    } else if (dayOfWeek != null) {
      updates['day_of_week'] = dayOfWeek;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session SET $setClause WHERE session_id = ?',
      [...updates.values, sessionId],
    );
  }

  /// Soft-deletes a planned session and its sets (is_archived = 1).
  Future<void> deletePlannedSession(String sessionId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_set SET is_archived = 1 WHERE session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session SET is_archived = 1 WHERE session_id = ?',
      [sessionId],
    );
  }

  Future<List<PlannedSessionSet>> fetchPlannedSets(String sessionId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*,
        COALESCE(e.exercise_name, s.exercise_name) AS exercise_name,
        COALESCE(v.variation_name, s.variation_name) AS variation_name
      FROM dim_planned_session_set s
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.session_id = ? AND s.is_archived = 0
      ORDER BY s.exercise_sequence_order, s.set_number
      ''',
      [sessionId],
    );
    return rows.map((r) => PlannedSessionSet.fromMap(r)).toList();
  }

  Future<PlannedSessionSet> createPlannedSet(
    String userId,
    String sessionId, {
    required String exerciseId,
    String? exerciseName,
    String? variationId,
    String? variationName,
    required int exerciseSequenceOrder,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_set
        (id, set_id, session_id, user_id, custom_exercise_id, custom_variation_id,
         exercise_sequence_order, set_number, target_weight, target_reps,
         target_notes, exercise_name, variation_name, is_archived)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        sessionId,
        userId,
        exerciseId,
        variationId,
        exerciseSequenceOrder,
        setNumber,
        targetWeight?.isNotEmpty == true ? targetWeight : null,
        targetReps?.isNotEmpty == true ? targetReps : null,
        targetNotes,
        exerciseName,
        variationName,
        0,
      ],
    );
    return PlannedSessionSet(
      setId: id,
      sessionId: sessionId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseSequenceOrder: exerciseSequenceOrder,
      setNumber: setNumber,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetNotes: targetNotes,
      exerciseName: exerciseName,
      variationName: variationName,
    );
  }

  Future<void> updatePlannedSet(
    String setId, {
    String? targetWeight,
    bool clearWeight = false,
    String? targetReps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? variationName,
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
      updates['variation_name'] = null;
    } else if (variationId != null) {
      updates['custom_variation_id'] = variationId;
      if (variationName != null) updates['variation_name'] = variationName;
    }
    if (clearNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_set SET $setClause WHERE set_id = ?',
      [...updates.values, setId],
    );
  }

  /// Soft-deletes a planned set.
  Future<void> deletePlannedSet(String setId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_set SET is_archived = 1 WHERE set_id = ?',
      [setId],
    );
  }

  /// Deep-copies a planned session with all its sets (standalone — no program
  /// linkage; callers re-attach program_id when duplicating within a program).
  Future<String> duplicatePlannedSession(
    String userId,
    PlannedSession source,
  ) async {
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

      for (final set in sets) {
        final newSetId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session_set
            (id, set_id, session_id, user_id, custom_exercise_id,
             custom_variation_id, exercise_sequence_order, set_number,
             target_weight, target_reps, target_notes,
             exercise_name, variation_name, is_archived)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSetId,
            newSetId,
            newId,
            userId,
            set.exerciseId,
            set.variationId,
            set.exerciseSequenceOrder,
            set.setNumber,
            set.targetWeight,
            jsonEncode(set.targetReps),
            set.targetNotes,
            set.exerciseName,
            set.variationName,
            0,
          ],
        );
      }
    });

    return newId;
  }

  /// Swaps the exercise sequence order between two exercises' sets in a
  /// planned session (for exercise-tab reordering).
  Future<void> swapSetExerciseOrders(
    String sessionId,
    int orderA,
    int orderB,
  ) async {
    await ps.db.execute(
      '''
      UPDATE dim_planned_session_set
        SET exercise_sequence_order = CASE exercise_sequence_order
          WHEN ? THEN ? ELSE ? END
      WHERE session_id = ? AND is_archived = 0
      ''',
      [orderA, orderB, orderA, sessionId],
    );
  }

  /// Renumbers every exercise's sequence order so each (old order → new
  /// index) entry in [orderToIndex] lands at index+1. Two-phase (shift to
  /// negatives, then assign) so intermediate collisions can't occur.
  Future<void> renumberSetExerciseOrders(
    String sessionId,
    List<(int, int)> orderToIndex,
  ) async {
    final n = orderToIndex.length;
    for (final (old, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_set SET exercise_sequence_order = ? '
        'WHERE session_id = ? AND exercise_sequence_order = ? AND is_archived = 0',
        [-n - index - 1, sessionId, old],
      );
    }
    for (final (_, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_set SET exercise_sequence_order = ? '
        'WHERE session_id = ? AND exercise_sequence_order = ? AND is_archived = 0',
        [index + 1, sessionId, -n - index - 1],
      );
    }
  }
}
