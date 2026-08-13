import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/session.dart';
import '../models/session_set.dart';

const _uuid = Uuid();

class SessionRepository {
  Future<String> createSession(
    String userId, {
    String? preNotes,
    String? programId,
    String? programName,
    String? programRunId,
    String? parentSessionId,
    String? parentSessionName,
    int? preFeeling,
  }) async {
    final sessionId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, pre_notes, created_date,
         is_active, program_id, program_name, program_run_id, parent_session_id,
         parent_session_name, pre_feeling)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        sessionId,
        userId,
        preNotes?.isNotEmpty == true ? preNotes : null,
        DateTime.now().toUtc().toIso8601String(),
        1,
        programId,
        programName,
        programRunId,
        parentSessionId,
        parentSessionName,
        preFeeling,
      ],
    );
    return sessionId;
  }

  Future<void> endSession(String sessionId,
      {String? postNotes, int? feeling}) async {
    await ps.db.execute(
      'UPDATE fact_session SET is_active = 0, post_notes = ?, post_feeling = ? WHERE session_id = ?',
      [postNotes?.isNotEmpty == true ? postNotes : null, feeling, sessionId],
    );
  }

  Future<void> saveExerciseOrder(String sessionId, String orderJson) async {
    await ps.db.execute(
      'UPDATE fact_session SET exercise_order = ? WHERE session_id = ?',
      [orderJson, sessionId],
    );
  }

  Future<void> cancelSession(String sessionId) async {
    // PRs are derived from sets on read — nothing extra to clean up.
    await ps.db.execute(
      'DELETE FROM fact_session_set WHERE session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM fact_session WHERE session_id = ?',
      [sessionId],
    );
  }

  Future<String?> getActiveSessionId(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT session_id FROM fact_session WHERE user_id = ? AND is_active = 1 LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) return null;
    return rows.first['session_id'] as String?;
  }

  Future<SessionSet> insertSet({
    required String sessionId,
    required String userId,
    required String exerciseId,
    String? variationId,
    required int setNumber,
    double? weight,
    required List<num> reps,
    String? notes,
    String? parentSetId,
    int? supersetGroupNumber,
    String? exerciseName,
    String? variationName,
  }) async {
    final setId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session_set
        (id, session_set_id, session_id, user_id, custom_exercise_id, custom_variation_id,
         set_number, weight, reps,
         notes, program_id, parent_set_id, superset_group_number,
         exercise_name, variation_name)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        setId,
        setId,
        sessionId,
        userId,
        exerciseId,
        variationId,
        setNumber,
        weight,
        jsonEncode(reps),
        notes?.isNotEmpty == true ? notes : null,
        parentSetId,
        supersetGroupNumber,
        exerciseName,
        variationName,
      ],
    );
    return SessionSet(
      sessionSetId: setId,
      sessionId: sessionId,
      userId: userId,
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      notes: notes?.isNotEmpty == true ? notes : null,
      supersetGroupNumber: supersetGroupNumber,
      parentSetId: parentSetId,
    );
  }

  Future<void> updateSet(
    String setId, {
    String? exerciseId,
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
    bool clearVariation = false,
    bool clearWeight = false,
    bool clearNotes = false,
    String? exerciseName,
    String? variationName,
  }) async {
    final setClauses = <String>[];
    final params = <Object?>[];

    if (exerciseId != null) {
      setClauses.add('custom_exercise_id = ?');
      params.add(exerciseId);
    }
    if (exerciseName != null) {
      setClauses.add('exercise_name = ?');
      params.add(exerciseName);
    }
    if (clearVariation) {
      setClauses.add('custom_variation_id = ?');
      params.add(null);
    } else if (variationId != null) {
      setClauses.add('custom_variation_id = ?');
      params.add(variationId);
    }
    if (variationName != null) {
      setClauses.add('variation_name = ?');
      params.add(variationName);
    }
    if (clearWeight) {
      setClauses.add('weight = ?');
      params.add(null);
    } else if (weight != null) {
      setClauses.add('weight = ?');
      params.add(weight);
    }
    if (reps != null) {
      setClauses.add('reps = ?');
      params.add(jsonEncode(reps));
    }
    if (clearNotes) {
      setClauses.add('notes = ?');
      params.add(null);
    } else if (notes != null) {
      setClauses.add('notes = ?');
      params.add(notes.isNotEmpty ? notes : null);
    }
    if (setClauses.isEmpty) return;

    params.add(setId);
    await ps.db.execute(
      'UPDATE fact_session_set SET ${setClauses.join(', ')} WHERE session_set_id = ?',
      params,
    );
  }

  Future<void> deleteSet(String setId) async {
    await ps.db.execute(
      'DELETE FROM fact_session_set WHERE session_set_id = ?',
      [setId],
    );
  }

  Future<List<SessionSet>> loadSetsForSession(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_session_set WHERE session_id = ? ORDER BY set_number',
      [sessionId],
    );
    return rows.map((r) => SessionSet.fromMap(r)).toList();
  }

  Future<void> reorderSets(
      String sessionId, List<String> orderedSetIds) async {
    for (var i = 0; i < orderedSetIds.length; i++) {
      await ps.db.execute(
        'UPDATE fact_session_set SET set_number = ? WHERE session_set_id = ?',
        [i + 1, orderedSetIds[i]],
      );
    }
  }

  Future<List<SessionWithSets>> loadSessionsWithSets(String userId) async {
    final sessionRows = await ps.db.getAll(
      '''
      SELECT * FROM fact_session
      WHERE user_id = ? AND is_active = 0
      ORDER BY created_date DESC
      ''',
      [userId],
    );
    if (sessionRows.isEmpty) return [];

    final sessions = sessionRows.map((r) => Session.fromMap(r)).toList();

    final setRows = await ps.db.getAll(
      '''
      SELECT s.*,
             COALESCE(s.exercise_name, e.exercise_name) AS exercise_name,
             COALESCE(s.variation_name, v.variation_name) AS variation_name
      FROM fact_session_set s
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE s.session_id IN (
        SELECT session_id FROM fact_session WHERE user_id = ? AND is_active = 0
      )
      ORDER BY s.session_id, s.set_number
      ''',
      [userId],
    );

    final setsBySession = <String, List<SessionSet>>{};
    for (final row in setRows) {
      final s = SessionSet.fromMap(row);
      setsBySession.putIfAbsent(s.sessionId, () => []).add(s);
    }

    return sessions
        .map((w) => SessionWithSets(
              session: w,
              sets: setsBySession[w.sessionId] ?? [],
            ))
        .toList();
  }

  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, w.created_date,
             COALESCE(s.exercise_name, e.exercise_name) AS exercise_name,
             COALESCE(s.variation_name, v.variation_name) AS variation_name
      FROM fact_session_set s
      INNER JOIN fact_session w ON w.session_id = s.session_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE w.user_id = ? AND w.is_active = 0
      ORDER BY w.created_date DESC, s.set_number
      ''',
      [userId],
    );
    return rows.map((r) => PastSetRow.fromMap(r)).toList();
  }

  Future<Session?> fetchSession(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_session WHERE session_id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  /// The most recently logged set for this exercise (any session, any
  /// variation) — used to prefill weight/variation/volume-type defaults when
  /// the user selects an exercise while logging a new set.
  Future<SessionSet?> findLastSetForExercise(
      String userId, String exerciseId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*
      FROM fact_session_set s
      INNER JOIN fact_session w ON w.session_id = s.session_id
      WHERE w.user_id = ? AND s.custom_exercise_id = ?
      ORDER BY w.created_date DESC, s.set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId],
    );
    if (rows.isEmpty) return null;
    return SessionSet.fromMap(rows.first);
  }

  /// The most recently logged set for this exact exercise+variation pair
  /// (spanning all sessions, including the active one) — the
  /// progressive-overload reference shown in the Log Set composer. `IS ?`
  /// instead of `= ?` so a null variationId matches sets logged with no
  /// variation, rather than matching nothing.
  Future<SessionSet?> findLastSetForExerciseVariation(
      String userId, String exerciseId, String? variationId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*
      FROM fact_session_set s
      INNER JOIN fact_session w ON w.session_id = s.session_id
      WHERE w.user_id = ? AND s.custom_exercise_id = ? AND s.custom_variation_id IS ?
      ORDER BY w.created_date DESC, s.set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId, variationId],
    );
    if (rows.isEmpty) return null;
    return SessionSet.fromMap(rows.first);
  }
}
