import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../cache/past_sets_timeline_cache.dart';
import '../models/session.dart';
import '../models/session_exercise.dart';
import '../models/session_exercise_set.dart';

const _uuid = Uuid();

class SessionRepository {
  /// Every fact write invalidates the shared timeline cache — this class is
  /// the single funnel for fact_session* rows, so a forgotten call here is
  /// the only way a screen could read a stale timeline (2026-10-13).
  void _invalidateTimeline() => PastSetsTimelineCache.instance.invalidate();

  Future<String> createSession(
    String userId, {
    String? preNotes,
    String? programRunId,
    String? plannedSessionId,
    String? plannedSessionName,
    int? preFeeling,
    String? deviceId,
  }) async {
    _invalidateTimeline();
    final sessionId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, pre_notes, created_datetime,
         program_run_id, planned_session_id, planned_session_name, pre_feeling,
         device_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        // Which device made it (2026-10-15) — what the foreign-session watch
        // compares against. Null (a caller that didn't resolve it) reads as
        // "another device", the safe reading.
        deviceId,
      ],
    );
    return sessionId;
  }

  /// Stamps the end time only — the questionnaire answers land separately
  /// via [updateSessionNotes] after the session ends (the post-questionnaire
  /// page's Done writes both bookends in one go, 2026-10-22).
  Future<void> endSession(String sessionId) async {
    _invalidateTimeline();
    await ps.db.execute(
      'UPDATE fact_session SET end_datetime = ? WHERE session_id = ?',
      [DateTime.now().toUtc().toIso8601String(), sessionId],
    );
  }

  /// Updates a completed session's pre/post notes and feeling ratings
  /// without touching end_datetime — the past-session editor's save path,
  /// and (since 2026-10-22) the live post-questionnaire Done, which writes
  /// both bookends at once. Empty strings clear the note; null feelings
  /// clear the rating (the editor always sends the full draft state).
  Future<void> updateSessionNotes(
    String sessionId, {
    String? preNotes,
    String? postNotes,
    int? preFeeling,
    int? postFeeling,
  }) async {
    _invalidateTimeline();
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
    _invalidateTimeline();
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
    _invalidateTimeline();
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

  /// The ACTIVE session THIS device owns (2026-10-15) — what the app
  /// resumes at launch. [deviceId] filters to this install's own rows, so a
  /// session running on another device (which syncs down like any other row)
  /// is never silently adopted; a null [deviceId] (prefs unavailable) falls
  /// back to the old any-active pick, because crash recovery matters more
  /// than the distinction there.
  Future<String?> getActiveSessionId(String userId, {String? deviceId}) async {
    final rows = await ps.db.getAll(
      deviceId == null
          ? 'SELECT session_id FROM fact_session WHERE user_id = ? AND end_datetime IS NULL LIMIT 1'
          : 'SELECT session_id FROM fact_session WHERE user_id = ? AND end_datetime IS NULL AND device_id = ? LIMIT 1',
      deviceId == null ? [userId] : [userId, deviceId],
    );
    if (rows.isEmpty) return null;
    return rows.first['session_id'] as String?;
  }

  /// Every active session for the user, live (2026-10-15). The VM filters
  /// this to the ones that are NOT its own — the foreign-session notice.
  Stream<List<Session>> watchActiveSessions(String userId) => ps.db
      .watch(
        'SELECT * FROM fact_session WHERE user_id = ? AND end_datetime IS NULL',
        parameters: [userId],
      )
      .map((rows) => rows.map(Session.fromMap).toList());

  /// Claims an active session for this device (2026-10-15) — the switch's
  /// last move: the row this device now logs into must carry THIS device's
  /// id, or the next launch would read its own session as foreign.
  Future<void> claimSession(String sessionId, String deviceId) async {
    _invalidateTimeline();
    await ps.db.execute(
      'UPDATE fact_session SET device_id = ? WHERE session_id = ?',
      [deviceId, sessionId],
    );
  }

  // ── Session exercises (the tab layer) ──────────────────────────────────────

  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    _invalidateTimeline();
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session_exercise
        (id, session_exercise_id, session_id, user_id, custom_exercise_id,
         exercise_order, planned_exercise_id)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, sessionId, userId, exerciseId, exerciseOrder, plannedExerciseId],
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
      _invalidateTimeline();
      await ps.db.execute(
        'UPDATE fact_session_exercise SET custom_exercise_id = NULL WHERE session_exercise_id = ?',
        [sessionExerciseId],
      );
      return;
    }
    if (exerciseId == null) return;
    _invalidateTimeline();
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
    _invalidateTimeline();
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
    _invalidateTimeline();
    final setId = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_session_exercise_set
        (id, session_exercise_set_id, session_exercise_id, user_id, custom_variation_id,
         set_number, weight, reps, notes, planned_set_id, is_deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
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

  /// The soft-delete API's write half (2026-10-13). [isDeleted]/[clearIsDeleted]
  /// flip the `is_deleted` flag — deleting a planned set flags it instead of
  /// removing it, so the exercise can be restored and wear the minus mark.
  /// Flagged rows live on in COMPLETED sessions too (they survive
  /// endSession's prune since 2026-10-14), so the derived reads — the
  /// timeline ([loadPastSetsTimeline]) and the all-sessions list
  /// ([loadSessionsWithSets]) — filter them out at the SQL level, while
  /// [loadSetsForSession] deliberately returns them so a viewer can show and
  /// restore them. [deleteSet] stays a hard delete for rows that were never
  /// part of a plan.
  Future<void> updateSet(
    String setId, {
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
    bool clearVariation = false,
    bool clearWeight = false,
    bool clearReps = false,
    bool clearNotes = false,
    bool isDeleted = false,
    bool clearIsDeleted = false,
  }) async {
    _invalidateTimeline();
    final setClauses = <String>[];
    final params = <Object?>[];

    if (clearIsDeleted) {
      setClauses.add('is_deleted = ?');
      params.add(0);
    } else if (isDeleted) {
      setClauses.add('is_deleted = ?');
      params.add(1);
    }
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
    if (clearReps) {
      // `[]`, not NULL: the one empty-reps value (the draft path writes the
      // same), so every never-filled row reads identically.
      setClauses.add('reps = ?');
      params.add(jsonEncode(const []));
    } else if (reps != null) {
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
    _invalidateTimeline();
    await ps.db.execute(
      'DELETE FROM fact_session_exercise_set WHERE session_exercise_set_id = ?',
      [setId],
    );
  }

  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async {
    final rows = await ps.db.getAll(_sessionSetsQuery, [sessionId]);
    return rows.map((r) => SessionExerciseSet.fromMap(r)).toList();
  }

  /// The one session-sets read, shared by the pull and the watch — the join
  /// hydrates exercise/variation names, so any consumer of this stream sees
  /// exactly what [loadSetsForSession] would return.
  static const _sessionSetsQuery = '''
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
      ''';

  /// The session's sets as a live stream — re-emits the authoritative rows
  /// whenever the tables behind them change, locally or from sync. The live
  /// session subscribes instead of pulling per edit: a debounced write lands
  /// and the stream delivers what the DB actually holds (2026-10-13).
  Stream<List<SessionExerciseSet>> watchSetsForSession(String sessionId) => ps
      .db
      .watch(
        _sessionSetsQuery,
        parameters: [sessionId],
        triggerOnTables: const [
          'fact_session_exercise_set',
          'fact_session_exercise',
          'dim_exercise',
          'dim_variation',
        ],
      )
      .map((rs) => rs.map(SessionExerciseSet.fromMap).toList());

  /// The session's exercise rows as a live stream — same contract as
  /// [watchSetsForSession], for the tab-layer rows.
  Stream<List<SessionExercise>> watchSessionExercises(String sessionId) => ps.db
      .watch(
        'SELECT * FROM fact_session_exercise WHERE session_id = ? ORDER BY exercise_order',
        parameters: [sessionId],
        triggerOnTables: const ['fact_session_exercise'],
      )
      .map((rs) => rs.map(SessionExercise.fromMap).toList());

  Future<void> reorderSets(String sessionId, List<String> orderedSetIds) async {
    _invalidateTimeline();
    for (var i = 0; i < orderedSetIds.length; i++) {
      await ps.db.execute(
        'UPDATE fact_session_exercise_set SET set_number = ? WHERE session_exercise_set_id = ?',
        [i + 1, orderedSetIds[i]],
      );
    }
  }

  /// Completed sessions with their sets, for the logs list and the
  /// all-sessions picker. Soft-deleted (flagged) rows are filtered out — a
  /// deleted set is not performed work and must not inflate the list's
  /// counts or filters (2026-10-14). The session VIEWER reads
  /// [loadSetsForSession] instead, which returns them.
  ///
  /// A session with no performed work has no card either (2026-10-25): it
  /// carries no set, so it holds nothing to show and nothing to open — the
  /// logs list skips it by construction (its filter tests the sets), and the
  /// all-sessions picker drew a row that could not be selected. The row
  /// stays; [loadCompletedSessionStamps] applies the same rule to the date
  /// bar's walk.
  Future<List<SessionWithSets>> loadSessionsWithSets(String userId) async {
    final sessionRows = await ps.db.getAll(
      '''
      SELECT w.* FROM fact_session w
      WHERE w.user_id = ? AND w.end_datetime IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM fact_session_exercise fe
          JOIN fact_session_exercise_set s
            ON s.session_exercise_id = fe.session_exercise_id
          WHERE fe.session_id = w.session_id
            AND COALESCE(s.is_deleted, 0) = 0
        )
      ORDER BY w.created_datetime DESC
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
        AND COALESCE(s.is_deleted, 0) = 0
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

  /// The user's completed sessions — id and start time only, newest first —
  /// the date bar's walk (2026-10-22). Two columns and no joins: stepping the
  /// floor's arrows needs neighbours, not rows; the logs list's whole-row
  /// read is [loadSessionsWithSets]. Ordered exactly as that list orders, so
  /// the bar and the list walk the same sequence.
  ///
  /// A completed session with no performed work is not part of that sequence
  /// (2026-10-25). The list only draws a card for a session carrying at least
  /// one non-flagged set, so an empty record must not be a neighbour either:
  /// the live floor's older step would land on a record the list refuses to
  /// show, and the viewer's arrows would point at a page that cannot exist —
  /// then dead-end, because nothing else is newer. The row stays in the
  /// database — restoring a flagged set brings it back onto both reads —
  /// and only the walk skips it.
  Future<List<({String sessionId, DateTime createdDatetime})>>
  loadCompletedSessionStamps(String userId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT w.session_id, w.created_datetime FROM fact_session w
      WHERE w.user_id = ? AND w.end_datetime IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM fact_session_exercise fe
          JOIN fact_session_exercise_set s
            ON s.session_exercise_id = fe.session_exercise_id
          WHERE fe.session_id = w.session_id
            AND COALESCE(s.is_deleted, 0) = 0
        )
      ORDER BY w.created_datetime DESC
      ''',
      [userId],
    );
    return [
      for (final r in rows)
        (
          sessionId: r['session_id'] as String,
          createdDatetime: DateTime.parse(r['created_datetime'] as String),
        ),
    ];
  }

  /// Every completed set, oldest of the derivation reads. This is the single
  /// choke point behind PRs, goals, achievements, usage counts and history
  /// pickers, so the soft-delete filter lives here: a flagged row is not a
  /// performed set and never earns a PR (2026-10-14).
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
        AND COALESCE(s.is_deleted, 0) = 0
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
        AND COALESCE(s.is_deleted, 0) = 0
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
        AND COALESCE(s.is_deleted, 0) = 0
      ORDER BY w.created_datetime DESC, s.set_number DESC
      LIMIT 1
      ''',
      [userId, exerciseId, variationId],
    );
    if (rows.isEmpty) return null;
    return SessionExerciseSet.fromMap(rows.first);
  }
}
