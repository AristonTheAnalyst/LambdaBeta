import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/powersync/database.dart' as ps;
import '../../core/utils/lambda_exception.dart';
import '../cache/past_sets_timeline_cache.dart';
import '../models/coach_assignment.dart';
import '../models/coach_feedback.dart';
import '../models/coach_relationship.dart';
import '../models/planned_session.dart';
import '../models/program_content.dart';
import 'exercise_repository.dart';
import 'planned_session_repository.dart';
import 'program_history_repository.dart';

const _uuid = Uuid();

/// What an ask RPC reports back (2026-10-30): the edge's two ids and whether
/// it is new ([created] false = the row was already there, so nothing is
/// mirrored).
class CoachingRequest {
  const CoachingRequest({
    required this.coachUserId,
    required this.athleteUserId,
    required this.created,
  });

  final String coachUserId;
  final String athleteUserId;
  final bool created;
}

/// The network half of [CoachRepository] (2026-10-26) — the calls that must
/// reach the server, in the [FriendRemote] seam's shape: host tests cannot
/// construct `Supabase.instance`, so the RPC contract is only testable through
/// an injected object.
abstract class CoachRemote {
  /// The caller asks [coachUserId] — a friend — to coach them (2026-10-30).
  Future<CoachingRequest> requestCoaching(String coachUserId);

  /// The caller offers to coach [athleteUserId] — a friend (2026-10-30).
  Future<CoachingRequest> offerCoaching(String athleteUserId);

  /// The caller accepts the pending edge the OTHER side asked for, either
  /// direction (2026-10-30).
  Future<void> acceptRequest(String otherUserId);

  /// Ends the relationship, from either side (decline, revoke or withdrawal).
  Future<void> remove(String otherUserId);
}

/// The real remote: the SECURITY DEFINER RPCs. The SQL enforces the consent
/// rules; the messages below translate its `raise exception` keys.
class SupabaseCoachRemote implements CoachRemote {
  const SupabaseCoachRemote();

  SupabaseClient get _client => Supabase.instance.client;

  /// The three ask/accept RPCs share one shape: one jsonb object back, or a
  /// PostgREST refusal mapped to a sentence.
  Future<CoachingRequest> _ask(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      final data = await _client
          .rpc(function, params: params)
          .timeout(const Duration(seconds: 8));
      final map = (data as Map).cast<String, dynamic>();
      return CoachingRequest(
        coachUserId: map['coach_user_id'] as String,
        athleteUserId: map['athlete_user_id'] as String,
        created: map['created'] as bool? ?? true,
      );
    } on PostgrestException catch (e) {
      throw LambdaException(
        _errorMessage(
          e.message,
          fallback: 'Could not send that request. Try again in a moment.',
        ),
      );
    }
  }

  @override
  Future<CoachingRequest> requestCoaching(String coachUserId) =>
      _ask('request_coaching', {'p_coach_user_id': coachUserId});

  @override
  Future<CoachingRequest> offerCoaching(String athleteUserId) =>
      _ask('offer_coaching', {'p_athlete_user_id': athleteUserId});

  @override
  Future<void> acceptRequest(String otherUserId) async {
    try {
      await _client
          .rpc(
            'accept_coaching_request',
            params: {'p_other_user_id': otherUserId},
          )
          .timeout(const Duration(seconds: 8));
    } on PostgrestException catch (e) {
      throw LambdaException(
        _errorMessage(
          e.message,
          fallback: 'Could not accept that. Try again in a moment.',
        ),
      );
    }
  }

  @override
  Future<void> remove(String otherUserId) async {
    try {
      await _client
          .rpc(
            'remove_coaching_relationship',
            params: {'p_other_user_id': otherUserId},
          )
          .timeout(const Duration(seconds: 8));
    } on PostgrestException catch (e) {
      throw LambdaException(
        _errorMessage(
          e.message,
          fallback: 'Could not remove that. Try again in a moment.',
        ),
      );
    }
  }

  /// The RPC's `raise exception` text is the key; one sentence per outcome.
  static String _errorMessage(String message, {required String fallback}) {
    final m = message.toLowerCase();
    if (m.contains('cannot_coach_self')) {
      return "That's your own friend code — enter your athlete's.";
    }
    if (m.contains('not_friends')) {
      return 'You can only coach a friend.';
    }
    if (m.contains('invitation_not_found')) {
      return 'That request is no longer there.';
    }
    if (m.contains('not_authenticated')) {
      return 'Your session has expired — sign in again.';
    }
    return fallback;
  }
}

/// Coaching relationships, read from the local mirror and changed through the
/// RPCs (2026-10-26, #22).
///
/// Reads are local-only: the caller's own `coaching_relationship` rows ride
/// user_data in both directions, and the coaching_data stream delivers each
/// accepted athlete's history plus the name slices (the athlete's once
/// accepted, the coach's from the invitation on). Writes are RPC-first, then
/// mirrored locally so the list repaints in the same beat.
///
/// * The mirror only ever touches the ROW THE RPC WROTE: the invite mirror
///   inserts the caller's own coach→athlete row under the synthetic
///   `'<coachId>-<athleteId>'` id the stream uses, and only when the RPC says
///   the row is new (a re-invite queues nothing); the accept mirror stamps
///   `accepted_date` on the caller's own athlete row; the remove mirror
///   deletes the pair locally, which also makes the queued DELETE resolve to
///   nothing and be skipped — the RPC has already deleted it server-side.
/// * The server's policies are shaped for exactly these mirrors: a coach may
///   insert only an unaccepted row, and the athlete may update only their own
///   row.
class CoachRepository {
  CoachRepository({
    CoachRemote? remote,
    ProgramHistoryRepository? historyRepository,
    ExerciseRepository? exerciseRepository,
    PlannedSessionRepository? plannedSessionRepository,
  }) : _remote = remote ?? const SupabaseCoachRemote(),
       _historyRepo = historyRepository ?? ProgramHistoryRepository(),
       _exerciseRepo = exerciseRepository ?? ExerciseRepository(),
       _plannedRepo = plannedSessionRepository ?? PlannedSessionRepository();

  final CoachRemote _remote;

  /// The snapshot builder (#24): the same `ProgramContent` document reviews
  /// store, narrowed to the one workout being assigned.
  final ProgramHistoryRepository _historyRepo;

  /// The dims the accept resolves names against — a coach's exercise ids are
  /// not the athlete's (`dim_exercise` rows are per-user).
  final ExerciseRepository _exerciseRepo;

  /// The workouts the assign sheet lists.
  final PlannedSessionRepository _plannedRepo;

  /// Every relationship the caller is a party to, both directions, each side
  /// named where its slice has synced. The ViewModel splits and orders.
  Stream<List<CoachRelationship>> watchRelationships(String userId) => ps.db
      .watch(
        'SELECT cr.coach_user_id, cr.athlete_user_id, cr.created_date, '
        'cr.accepted_date, cr.requested_by_user_id, '
        'cu.user_name AS coach_first_name, '
        'cu.user_lastname AS coach_last_name, '
        'au.user_name AS athlete_first_name, '
        'au.user_lastname AS athlete_last_name '
        'FROM coaching_relationship cr '
        'LEFT JOIN dim_user cu ON cu.user_id = cr.coach_user_id '
        'LEFT JOIN dim_user au ON au.user_id = cr.athlete_user_id '
        'WHERE cr.coach_user_id = ? OR cr.athlete_user_id = ? '
        'ORDER BY cr.created_date',
        parameters: [userId, userId],
      )
      .map((rows) => rows.map(CoachRelationship.fromMap).toList());

  /// The athlete's ask (2026-10-30): [userId] asks [coachId] — a friend — to
  /// coach them. The coach accepts with [acceptRequest].
  Future<CoachingRequest> requestCoaching(
    String userId,
    String coachId,
  ) async {
    final request = await _remote.requestCoaching(coachId);
    if (request.created) {
      await _mirrorAsk(request.coachUserId, request.athleteUserId, userId);
    }
    return request;
  }

  /// The coach's offer (2026-10-30): [userId] offers to coach [athleteId] — a
  /// friend.
  Future<CoachingRequest> offerCoaching(
    String userId,
    String athleteId,
  ) async {
    final request = await _remote.offerCoaching(athleteId);
    if (request.created) {
      await _mirrorAsk(request.coachUserId, request.athleteUserId, userId);
    }
    return request;
  }

  /// Accepts the pending edge [otherUserId] asked for — as the coach when they
  /// asked to be coached, as the athlete when they offered. The grant lands on
  /// the athlete's friendship row server-side; the stream repaints the list.
  Future<void> acceptRequest(String userId, String otherUserId) async {
    await _remote.acceptRequest(otherUserId);
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'UPDATE coaching_relationship SET accepted_date = ? '
          'WHERE accepted_date IS NULL '
          'AND ((coach_user_id = ? AND athlete_user_id = ?) '
          'OR (coach_user_id = ? AND athlete_user_id = ?))',
          [
            DateTime.now().toUtc().toIso8601String(),
            userId,
            otherUserId,
            otherUserId,
            userId,
          ],
        );
      });
    } catch (e) {
      debugPrint('CoachRepository.acceptRequest: local mirror failed: $e');
    }
  }

  /// Ends the relationship from either side and drops the local row at once.
  /// The other person's cached timeline goes with it — their rows leave the
  /// device on the next sync round, and nothing may serve them in between.
  Future<void> remove(String userId, String otherUserId) async {
    await _remote.remove(otherUserId);
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'DELETE FROM coaching_relationship '
          'WHERE (coach_user_id = ? AND athlete_user_id = ?) '
          'OR (coach_user_id = ? AND athlete_user_id = ?)',
          [userId, otherUserId, otherUserId, userId],
        );
      });
    } catch (e) {
      debugPrint('CoachRepository.remove: local delete failed: $e');
    }
    PastSetsTimelineCache.instance.invalidate(otherUserId);
  }

  /// Best-effort mirror of an ask (2026-10-30): the pending row under the
  /// synthetic id the stream uses, with the requester stamped. A failure must
  /// not read as a failed request — the RPC already wrote it, and the next
  /// sync round brings it down anyway.
  Future<void> _mirrorAsk(
    String coachId,
    String athleteId,
    String requestedBy,
  ) async {
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'INSERT OR IGNORE INTO coaching_relationship '
          '(id, coach_user_id, athlete_user_id, created_date, '
          'requested_by_user_id) VALUES (?, ?, ?, ?, ?)',
          [
            '$coachId-$athleteId',
            coachId,
            athleteId,
            DateTime.now().toUtc().toIso8601String(),
            requestedBy,
          ],
        );
      });
    } catch (e) {
      debugPrint('CoachRepository._mirrorAsk: local insert failed: $e');
    }
  }

  // ── Assignments (2026-10-26, #24) ──────────────────────────────────────────

  /// Every assignment the caller is a party to — sent as a coach, received as
  /// an athlete — newest first. The ViewModel splits by side and status.
  Stream<List<CoachAssignment>> watchAssignments(String userId) => ps.db
      .watch(
        'SELECT * FROM fact_coach_assignment '
        'WHERE coach_user_id = ? OR athlete_user_id = ? '
        'ORDER BY created_date DESC',
        parameters: [userId, userId],
      )
      .map((rows) => rows.map(CoachAssignment.fromMap).toList());

  /// The coach's own workouts for the assign sheet, newest first.
  Future<List<PlannedSession>> assignableWorkouts(String coachId) =>
      _plannedRepo.fetchAllActiveSessions(coachId);

  /// Writes an assignment: a frozen [ProgramContent] snapshot of [workout]
  /// plus the names the athlete's device cannot resolve, then the row.
  ///
  /// Local-first, like the nickname: the row is the caller's own, the server's
  /// insert policy checks [coaches_athlete] (`coach_user_id = auth.uid()` and
  /// an accepted edge), and the athlete sees it on the round after it uploads.
  Future<CoachAssignment> createAssignment({
    required String coachId,
    required String athleteId,
    required PlannedSession workout,
    String? note,
  }) async {
    final content = await _historyRepo.buildContentForSessions(
      userId: coachId,
      sessionIds: [workout.sessionId],
    );
    if (content.sessions.isEmpty) {
      throw const LambdaException(
        'That workout is no longer there — try another.',
      );
    }
    final session = content.sessions.first;

    final exerciseNameMap = await _exerciseRepo.fetchExerciseNameMap(coachId);
    final variationNameMap = await _exerciseRepo.fetchVariationNameMap(coachId);
    final exerciseIds = {
      for (final group in session.exercises)
        if (group.exerciseId != null) group.exerciseId!,
    };
    final variationIds = {
      for (final group in session.exercises)
        for (final set in group.sets)
          if (set.variationId != null) set.variationId!,
    };
    // Only the names this workout uses — the assignment is not a library
    // hand-off, so the coach's whole catalog never travels.
    final namesJson = jsonEncode({
      'exercises': {
        for (final id in exerciseIds)
          if ((exerciseNameMap[id] ?? '').isNotEmpty) id: exerciseNameMap[id],
      },
      'variations': {
        for (final id in variationIds)
          if ((variationNameMap[id] ?? '').isNotEmpty)
            id: variationNameMap[id],
      },
    });

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final assignment = CoachAssignment(
      assignmentId: id,
      coachUserId: coachId,
      athleteUserId: athleteId,
      plannedSessionId: workout.sessionId,
      name: session.name,
      note: note,
      snapshotContent: content.encode(),
      namesJson: namesJson,
      createdDate: now,
    );
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'INSERT INTO fact_coach_assignment '
        '(id, assignment_id, coach_user_id, athlete_user_id, '
        ' planned_session_id, name, note, snapshot_content, names_json, '
        ' created_date) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          id,
          coachId,
          athleteId,
          workout.sessionId,
          session.name,
          note,
          assignment.snapshotContent,
          namesJson,
          now.toIso8601String(),
        ],
      );
    });
    return assignment;
  }

  /// The athlete's accept: materializes the snapshot into their own library
  /// and stamps the assignment — one local transaction, so a half-copy can
  /// never be visible.
  ///
  /// Exercise and variation ids are remapped BY NAME: the snapshot is id-only
  /// (the house rule for same-user snapshots) and the coach's ids mean nothing
  /// on this device. A name the athlete's library lacks is created (or an
  /// archived row reactivated); a group whose name the coach could not resolve
  /// is skipped, because there is nothing to create it as.
  Future<PlannedSession> acceptAssignment(
    String athleteId,
    CoachAssignment assignment,
  ) async {
    final ProgramContent content;
    try {
      content = ProgramContent.decode(assignment.snapshotContent);
    } on FormatException {
      throw const LambdaException(
        "This assignment couldn't be read. Ask your coach to send it again.",
      );
    }
    if (content.sessions.isEmpty) {
      throw const LambdaException("This assignment doesn't hold a workout.");
    }
    final session = content.sessions.first;

    final exerciseNames = assignment.exerciseNames;
    final variationNames = assignment.variationNames;

    final exerciseIdBySource = <String, String>{};
    final resolvedExercises = <String>{};
    for (final group in session.exercises) {
      final source = group.exerciseId;
      if (source == null || !resolvedExercises.add(source)) continue;
      final name = (exerciseNames[source] ?? '').trim();
      if (name.isEmpty) continue;
      final found = await _exerciseRepo.findExerciseByName(athleteId, name);
      if (found == null) {
        final created = await _exerciseRepo.createExercise(athleteId, name);
        exerciseIdBySource[source] = created.exerciseId;
      } else {
        if (found.archivedDate != null) {
          await _exerciseRepo.reactivateExercise(found.exerciseId);
        }
        exerciseIdBySource[source] = found.exerciseId;
      }
    }

    final variationIdBySource = <String, String>{};
    for (final group in session.exercises) {
      for (final set in group.sets) {
        final source = set.variationId;
        if (source == null ||
            variationIdBySource.containsKey(source) ||
            variationNames[source] == null) {
          continue;
        }
        final name = variationNames[source]!.trim();
        if (name.isEmpty) continue;
        final found = await _exerciseRepo.findVariationByName(athleteId, name);
        if (found == null) {
          final created = await _exerciseRepo.createVariation(athleteId, name);
          variationIdBySource[source] = created.variationId;
        } else {
          if (found.archivedDate != null) {
            await _exerciseRepo.reactivateVariation(found.variationId);
          }
          variationIdBySource[source] = found.variationId;
        }
      }
    }

    // A group survives when it is a free row (no exercise) or its exercise
    // resolved. Losing every group means there is nothing worth writing.
    final groups = [
      for (final group in session.exercises)
        if (group.exerciseId == null ||
            exerciseIdBySource.containsKey(group.exerciseId))
          group,
    ];
    if (groups.isEmpty) {
      throw const LambdaException(
        "None of this workout's exercises could be matched to your library.",
      );
    }

    final newSessionId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'INSERT INTO dim_planned_session '
        '(id, session_id, user_id, name, notes, date_archived, created_date, '
        ' base_session_id, coach_assignment_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          newSessionId,
          newSessionId,
          athleteId,
          session.name,
          session.notes,
          null,
          now.toIso8601String(),
          null,
          assignment.assignmentId,
        ],
      );
      var order = 0;
      for (final group in groups) {
        order++;
        final plannedExerciseId = _uuid.v4();
        await tx.execute(
          'INSERT INTO dim_planned_session_exercise '
          '(id, planned_exercise_id, planned_session_id, user_id, '
          ' custom_exercise_id, exercise_order, is_archived) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            plannedExerciseId,
            plannedExerciseId,
            newSessionId,
            athleteId,
            group.exerciseId == null
                ? null
                : exerciseIdBySource[group.exerciseId],
            order,
            0,
          ],
        );
        for (final set in group.sets) {
          final plannedSetId = _uuid.v4();
          await tx.execute(
            'INSERT INTO dim_planned_session_exercise_set '
            '(id, planned_set_id, planned_exercise_id, user_id, '
            ' custom_variation_id, set_number, target_weight, target_reps, '
            ' target_notes, is_archived) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              plannedSetId,
              plannedSetId,
              plannedExerciseId,
              athleteId,
              set.variationId == null
                  ? null
                  : variationIdBySource[set.variationId],
              set.setNumber,
              set.targetWeight,
              set.targetReps,
              set.targetNotes,
              0,
            ],
          );
        }
      }
      await tx.execute(
        'UPDATE fact_coach_assignment '
        'SET accepted_date = ?, athlete_planned_session_id = ? '
        'WHERE assignment_id = ?',
        [now.toIso8601String(), newSessionId, assignment.assignmentId],
      );
    });

    return PlannedSession(
      sessionId: newSessionId,
      userId: athleteId,
      name: session.name,
      notes: session.notes,
      createdDate: now,
      coachAssignmentId: assignment.assignmentId,
    );
  }

  /// The athlete's decline: a stamp, so the row stays as history but is never
  /// "waiting" again and grants nothing.
  Future<void> declineAssignment(
    String athleteId,
    CoachAssignment assignment,
  ) async {
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'UPDATE fact_coach_assignment SET declined_date = ? '
        'WHERE assignment_id = ? AND athlete_user_id = ?',
        [DateTime.now().toUtc().toIso8601String(), assignment.assignmentId, athleteId],
      );
    });
  }

  /// The coach takes back an assignment nobody accepted. An accepted one is
  /// history: the athlete's copy is theirs now, and the row stays.
  Future<void> withdrawAssignment(
    String coachId,
    CoachAssignment assignment,
  ) async {
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'DELETE FROM fact_coach_assignment '
        'WHERE assignment_id = ? AND coach_user_id = ? '
        'AND accepted_date IS NULL',
        [assignment.assignmentId, coachId],
      );
    });
  }

  // ── Feedback (2026-10-26, #24) ─────────────────────────────────────────────

  /// The feedback rows on one session — for the athlete who owns it and the
  /// coach who wrote them, from the local mirror.
  Stream<List<CoachFeedback>> watchFeedback(String sessionId) => ps.db
      .watch(
        'SELECT * FROM fact_coach_feedback WHERE session_id = ? '
        'ORDER BY created_date',
        parameters: [sessionId],
      )
      .map((rows) => rows.map(CoachFeedback.fromMap).toList());

  /// `user_id → "First Last"` for the given ids, as far as this device knows
  /// them — the feedback card's attribution, read off the name-only `dim_user`
  /// slice the coaching stream carries. Ids with no name are absent from the
  /// map, and the card draws its fallback.
  Future<Map<String, String>> userNames(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await ps.db.getAll(
      'SELECT user_id, user_name, user_lastname FROM dim_user '
      'WHERE user_id IN (${List.filled(ids.length, '?').join(', ')})',
      ids,
    );
    final out = <String, String>{};
    for (final row in rows) {
      final name = [
        if ((row['user_name'] as String?)?.trim().isNotEmpty ?? false)
          (row['user_name'] as String).trim(),
        if ((row['user_lastname'] as String?)?.trim().isNotEmpty ?? false)
          (row['user_lastname'] as String).trim(),
      ].join(' ');
      if (name.isNotEmpty) out[row['user_id'] as String] = name;
    }
    return out;
  }

  /// Writes or rewrites the caller's feedback on [sessionId]. One row per
  /// (coach, session): an existing row is updated, its first write untouched.
  Future<CoachFeedback> saveFeedback({
    required String coachId,
    required String athleteId,
    required String sessionId,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) {
      throw const LambdaException('Write something first.');
    }
    final now = DateTime.now().toUtc();
    final existing = await ps.db.getAll(
      'SELECT * FROM fact_coach_feedback '
      'WHERE coach_user_id = ? AND session_id = ?',
      [coachId, sessionId],
    );
    if (existing.isNotEmpty) {
      final row = CoachFeedback.fromMap(existing.first);
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'UPDATE fact_coach_feedback SET body = ?, edited_date = ? '
          'WHERE feedback_id = ?',
          [text, now.toIso8601String(), row.feedbackId],
        );
      });
      return CoachFeedback(
        feedbackId: row.feedbackId,
        coachUserId: row.coachUserId,
        athleteUserId: row.athleteUserId,
        sessionId: row.sessionId,
        body: text,
        createdDate: row.createdDate,
        editedDate: now,
      );
    }
    final id = _uuid.v4();
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'INSERT INTO fact_coach_feedback '
        '(id, feedback_id, coach_user_id, athlete_user_id, session_id, body, '
        ' created_date) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          id,
          coachId,
          athleteId,
          sessionId,
          text,
          now.toIso8601String(),
        ],
      );
    });
    return CoachFeedback(
      feedbackId: id,
      coachUserId: coachId,
      athleteUserId: athleteId,
      sessionId: sessionId,
      body: text,
      createdDate: now,
    );
  }

  /// Deletes the caller's own feedback row.
  Future<void> deleteFeedback(String coachId, String feedbackId) async {
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'DELETE FROM fact_coach_feedback '
        'WHERE feedback_id = ? AND coach_user_id = ?',
        [feedbackId, coachId],
      );
    });
  }
}
