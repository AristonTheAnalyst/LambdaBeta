import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/session.dart';
import '../models/session_exercise.dart';
import '../models/session_exercise_set.dart';

const _uuid = Uuid();

class SessionRepository {
  Future<String> createSession(
    String userId, {
    String? preNotes,
    String? programRunId,
    String? plannedSessionId,
    String? plannedSessionName,
    int? preFeeling,
  }) async {
    final sessionId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, pre_notes, created_datetime,
         program_run_id, planned_session_id, planned_session_name, pre_feeling)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        sessionId,
        userId,
        preNotes?.isNotEmpty == true ? preNotes : null,
        DateTime.now().toUtc().toIso8601String(),
        programRunId,
        plannedSessionId,
        plannedSessionName,
        preFeeling,
      ],
    );
    return sessionId;
  }

  /// Stamps the end time only — the post-session questionnaire lands
  /// separately via [updatePostQuestionnaire] after the session ends.
  Future<void> endSession(String sessionId) async {
    await ps.db.execute(
      'UPDATE fact_session SET end_datetime = ? WHERE session_id = ?',
      [
        DateTime.now().toUtc().toIso8601String(),
        sessionId,
      ],
    );
  }

  /// Writes the post-session questionnaire AFTER [endSession] (wizard
  /// page 4) — the two steps are separate so the post answers never have
  /// to be present at the moment the session ends.
  Future<void> updatePostQuestionnaire(
    String sessionId, {
    int? feeling,
    String? notes,
  }) async {
    await ps.db.execute(
      'UPDATE fact_session SET post_notes = ?, post_feeling = ? WHERE session_id = ?',
      [
        notes?.isNotEmpty == true ? notes : null,
        feeling,
        sessionId,
      ],
    );
  }

  /// Updates a completed session's pre/post notes and feeling ratings
  /// without touching end_datetime — the past-session editor's save path
  /// (distinct from the live [endSession] flow). Empty strings clear the
  /// note; null feelings clear the rating (the editor always sends the full
  /// draft state).
  Future<void> updateSessionNotes(
    String sessionId, {
    String? preNotes,
    String? postNotes,
    int? preFeeling,
    int? postFeeling,
  }) async {
    await ps.db.execute(
      '''
      UPDATE fact_session
      SET pre_notes = ?, post_notes = ?, pre_feeling = ?, post_feeling = ?
      WHERE session_id = ?
      ''',
      [
        preNotes?.isNotEmpty == true ? preNotes : null,
        postNotes?.isNotEmpty == true ? postNotes : null,
        preFeeling,
        postFeeling,
        sessionId,
      ],
    );
  }

  /// Persists the exercise-tab order — the old JSON blob is gone; order is a
  /// real column on fact_session_exercise.
  Future<void> reorderSessionExercises(
    String sessionId,
    List<String> orderedSessionExerciseIds,
  ) async {
    for (var i = 0; i < orderedSessionExerciseIds.length; i++) {
      await ps.db.execute(
        'UPDATE fact_session_exercise SET exercise_order = ? WHERE session_exercise_id = ?',
        [i + 1, orderedSessionExerciseIds[i]],
      );
    }
  }

  /// Hard-deletes a logged session and everything under it — the Training
  /// Logs delete and the live session's Cancel are the same operation.
  ///
  /// Sessions are facts: they hard-delete (never soft-delete), and PRs are
  /// derived on read so there is nothing else to clean up. Children go
  /// first and the parent last — `fact_session_exercise.session_id` is a
  /// NO ACTION FK on the server, and the upload queue replays these in the
  /// order they were written. `dim_lesson.session_id` is ON DELETE SET
  /// NULL, so lessons logged during the session survive it.
  Future<void> deleteSession(String sessionId) async {
    await ps.db.execute(
      '''
      DELETE FROM fact_session_exercise_set
      WHERE session_exercise_id IN (
        SELECT session_exercise_id FROM fact_session_exercise WHERE session_id = ?
      )
      ''',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM fact_session_exercise WHERE session_id = ?',
      [sessionId],
    );
    await ps.db.execute('DELETE FROM fact_session WHERE session_id = ?', [
      sessionId,
    ]);
  }

  /// Discards an in-progress session — same cascade as [deleteSession].
  Future<void> cancelSession(String sessionId) => deleteSession(sessionId);

  Future<String?> getActiveSessionId(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT session_id FROM fact_session WHERE user_id = ? AND end_datetime IS NULL LIMIT 1',
      [userId],
    );
    if (rows.isEmpty) return null;
    return rows.first['session_id'] as String?;
  }

  // ── Session exercises (the tab layer) ──────────────────────────────────────

  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session_exercise
        (id, session_exercise_id, session_id, user_id, custom_exercise_id,
         exercise_order, planned_exercise_id)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        sessionId,
        userId,
        exerciseId,
        exerciseOrder,
        plannedExerciseId,
      ],
    );
    return SessionExercise(
      sessionExerciseId: id,
      sessionId: sessionId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseOrder: exerciseOrder,
      plannedExerciseId: plannedExerciseId,
    );
  }

  /// Updates a session exercise's assigned exercise (tab switching) — sets
  /// keep their own ids and hang off this row unchanged.
  Future<void> updateSessionExercise(
    String sessionExerciseId, {
    String? exerciseId,
    bool clearExercise = false,
  }) async {
    if (clearExercise) {
      await ps.db.execute(
        'UPDATE fact_session_exercise SET custom_exercise_id = NULL WHERE session_exercise_id = ?',
        [sessionExerciseId],
      );
      return;
    }
    if (exerciseId == null) return;
    await ps.db.execute(
      'UPDATE fact_session_exercise SET custom_exercise_id = ? WHERE session_exercise_id = ?',
      [exerciseId, sessionExerciseId],
    );
  }

  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM fact_session_exercise WHERE session_id = ? ORDER BY exercise_order',
      [sessionId],
    );
    return rows.map((r) => SessionExercise.fromMap(r)).toList();
  }

  Future<void> deleteSessionExercise(String sessionExerciseId) async {
    await ps.db.execute(
      'DELETE FROM fact_session_exercise_set WHERE session_exercise_id = ?',
      [sessionExerciseId],
    );
    await ps.db.execute(
      'DELETE FROM fact_session_exercise WHERE session_exercise_id = ?',
      [sessionExerciseId],
    );
  }

  // ── Sets ───────────────────────────────────────────────────────────────────

  Future<SessionExerciseSet> insertSet({
    required String sessionExerciseId,
    required String sessionId,
    required String userId,
    String? variationId,
    required int setNumber,
    double? weight,
    required List<num> reps,
    String? notes,
    String? plannedSetId,
  }) async {
    final setId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session_exercise_set
        (id, session_exercise_set_id, session_exercise_id, user_id, custom_variation_id,
         set_number, weight, reps, notes, planned_set_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        setId,
        setId,
        sessionExerciseId,
        userId,
        variationId,
        setNumber,
        weight,
        jsonEncode(reps),
        notes?.isNotEmpty == true ? notes : null,
        plannedSetId,
      ],
    );
    return SessionExerciseSet(
      sessionExerciseSetId: setId,
      sessionExerciseId: sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      variationId: variationId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      notes: notes?.isNotEmpty == true ? notes : null,
      plannedSetId: plannedSetId,
    );
  }

  Future<void> updateSet(
    String setId, {
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
    bool clearVariation = false,
    bool clearWeight = false,
    bool clearNotes = false,
  }) async {
    final setClauses = <String>[];
    final params = <Object?>[];

    if (clearVariation) {
      setClauses.add('custom_variation_id = ?');
      params.add(null);
    } else if (variationId != null) {
      setClauses.add('custom_variation_id = ?');
      params.add(variationId);
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
      'UPDATE fact_session_exercise_set SET ${setClauses.join(', ')} WHERE session_exercise_set_id = ?',
      params,
    );
  }

  Future<void> deleteSet(String setId) async {
    await ps.db.execute(
      'DELETE FROM fact_session_exercise_set WHERE session_exercise_set_id = ?',
      [setId],
    );
  }

  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*,
             fe.custom_exercise_id,
             fe.session_id,
             e.exercise_name,
             v.variation_name
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = fe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE fe.session_id = ?
      ORDER BY fe.exercise_order, s.set_number
      ''',
      [sessionId],
    );
    return rows.map((r) => SessionExerciseSet.fromMap(r)).toList();
  }

  Future<void> reorderSets(String sessionId, List<String> orderedSetIds) async {
    for (var i = 0; i < orderedSetIds.length; i++) {
      await ps.db.execute(
        'UPDATE fact_session_exercise_set SET set_number = ? WHERE session_exercise_set_id = ?',
        [i + 1, orderedSetIds[i]],
      );
    }
  }

  Future<List<SessionWithSets>> loadSessionsWithSets(String userId) async {
    final sessionRows = await ps.db.getAll(
      '''
      SELECT * FROM fact_session
      WHERE user_id = ? AND end_datetime IS NOT NULL
      ORDER BY created_datetime DESC
      ''',
      [userId],
    );
    if (sessionRows.isEmpty) return [];

    final sessions = sessionRows.map((r) => Session.fromMap(r)).toList();

    final setRows = await ps.db.getAll(
      '''
      SELECT s.*,
             fe.custom_exercise_id,
             fe.session_id,
             e.exercise_name,
             v.variation_name
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = fe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE fe.session_id IN (
        SELECT session_id FROM fact_session WHERE user_id = ? AND end_datetime IS NOT NULL
      )
      ORDER BY fe.session_id, fe.exercise_order, s.set_number
      ''',
      [userId],
    );

    final setsBySession = <String, List<SessionExerciseSet>>{};
    for (final row in setRows) {
      final s = SessionExerciseSet.fromMap(row);
      setsBySession.putIfAbsent(s.sessionId, () => []).add(s);
    }

    return sessions
        .map(
          (w) => SessionWithSets(
            session: w,
            sets: setsBySession[w.sessionId] ?? [],
          ),
        )
        .toList();
  }

  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, w.created_datetime,
             fe.custom_exercise_id,
             fe.session_id,
             e.exercise_name,
             v.variation_name
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      INNER JOIN fact_session w ON w.session_id = fe.session_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = fe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE w.user_id = ? AND w.end_datetime IS NOT NULL
      ORDER BY w.created_datetime DESC, fe.exercise_order, s.set_number
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
  Future<SessionExerciseSet?> findLastSetForExercise(
    String userId,
    String exerciseId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, fe.custom_exercise_id, fe.session_id
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      INNER JOIN fact_session w ON w.session_id = fe.session_id
      WHERE w.user_id = ? AND fe.custom_exercise_id = ?
      ORDER BY w.created_datetime DESC, s.set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId],
    );
    if (rows.isEmpty) return null;
    return SessionExerciseSet.fromMap(rows.first);
  }

  /// The most recently logged set for this exact exercise+variation pair
  /// (spanning all sessions, including the active one) — the
  /// progressive-overload reference shown in the Log Set composer. `IS ?`
  /// instead of `= ?` so a null variationId matches sets logged with no
  /// variation, rather than matching nothing.
  Future<SessionExerciseSet?> findLastSetForExerciseVariation(
    String userId,
    String exerciseId,
    String? variationId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*, fe.custom_exercise_id, fe.session_id
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      INNER JOIN fact_session w ON w.session_id = fe.session_id
      WHERE w.user_id = ? AND fe.custom_exercise_id = ? AND s.custom_variation_id IS ?
      ORDER BY w.created_datetime DESC, s.set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId, variationId],
    );
    if (rows.isEmpty) return null;
    return SessionExerciseSet.fromMap(rows.first);
  }
}
