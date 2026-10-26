import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/powersync/database.dart' as ps;
import '../../core/utils/friend_code.dart';
import '../../core/utils/lambda_exception.dart';
import '../cache/past_sets_timeline_cache.dart';
import '../models/coach_relationship.dart';

/// What the invite RPC reports back: the athlete the code resolved to, and
/// whether the invitation is new ([created] false = the row was already there).
class CoachInvite {
  const CoachInvite({required this.athleteUserId, required this.created});

  final String athleteUserId;
  final bool created;
}

/// The network half of [CoachRepository] (2026-10-26) — the three calls that
/// must reach the server, in the [FriendRemote] seam's shape: host tests
/// cannot construct `Supabase.instance`, so the RPC contract is only testable
/// through an injected object.
abstract class CoachRemote {
  /// Resolves [code] to a user and writes the invitation, server-side.
  /// Throws [LambdaException] with a user-facing sentence on refusal.
  Future<CoachInvite> inviteByCode(String code);

  /// Stamps the athlete's consent on a pending invitation.
  Future<void> acceptInvitation(String coachUserId);

  /// Ends the relationship, from either side (decline, revoke or withdrawal).
  Future<void> remove(String otherUserId);
}

/// The real remote: the three SECURITY DEFINER RPCs. The SQL enforces the
/// consent rules; the messages below translate its `raise exception` keys.
class SupabaseCoachRemote implements CoachRemote {
  const SupabaseCoachRemote();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<CoachInvite> inviteByCode(String code) async {
    try {
      final data = await _client
          .rpc('coach_invite_by_code', params: {'p_code': code})
          .timeout(const Duration(seconds: 8));
      // The function returns one jsonb object (not a row set).
      final map = (data as Map).cast<String, dynamic>();
      return CoachInvite(
        athleteUserId: map['athlete_user_id'] as String,
        created: map['created'] as bool? ?? true,
      );
    } on PostgrestException catch (e) {
      throw LambdaException(
        _errorMessage(
          e.message,
          fallback: 'Could not send that invitation. Try again in a moment.',
        ),
      );
    }
  }

  @override
  Future<void> acceptInvitation(String coachUserId) async {
    try {
      await _client
          .rpc(
            'accept_coaching_invitation',
            params: {'p_coach_user_id': coachUserId},
          )
          .timeout(const Duration(seconds: 8));
    } on PostgrestException catch (e) {
      throw LambdaException(
        _errorMessage(
          e.message,
          fallback: 'Could not accept that invitation. Try again in a moment.',
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
    if (m.contains('friend_code_invalid')) {
      return "That friend code doesn't look right. Check it and try again.";
    }
    if (m.contains('friend_code_not_found')) {
      return 'No one has that friend code.';
    }
    if (m.contains('cannot_coach_self')) {
      return "That's your own friend code — enter your athlete's.";
    }
    if (m.contains('invitation_not_found')) {
      return 'That invitation is no longer there.';
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
  CoachRepository({CoachRemote? remote})
    : _remote = remote ?? const SupabaseCoachRemote();

  final CoachRemote _remote;

  /// Every relationship the caller is a party to, both directions, each side
  /// named where its slice has synced. The ViewModel splits and orders.
  Stream<List<CoachRelationship>> watchRelationships(String userId) => ps.db
      .watch(
        'SELECT cr.coach_user_id, cr.athlete_user_id, cr.created_date, '
        'cr.accepted_date, '
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

  /// Invites the owner of [rawCode] to share their training. A malformed code
  /// is refused here, before any network call; the server applies the same
  /// rule. Returns the RPC's report so the screen can say which name landed.
  Future<CoachInvite> inviteByCode(String userId, String rawCode) async {
    final code = normalizeFriendCode(rawCode);
    if (code == null) {
      throw const LambdaException(
        "That friend code doesn't look right. Check it and try again.",
      );
    }
    final invite = await _remote.inviteByCode(code);
    if (invite.created) {
      await _mirrorInvite(userId, invite.athleteUserId);
    }
    return invite;
  }

  /// Accepts [coachId]'s invitation — the athlete's consent. The stream starts
  /// sending their history to the coach on the round after the write lands.
  Future<void> acceptInvitation(String userId, String coachId) async {
    await _remote.acceptInvitation(coachId);
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'UPDATE coaching_relationship SET accepted_date = ? '
          'WHERE coach_user_id = ? AND athlete_user_id = ?',
          [DateTime.now().toUtc().toIso8601String(), coachId, userId],
        );
      });
    } catch (e) {
      debugPrint('CoachRepository.acceptInvitation: local mirror failed: $e');
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

  /// Best-effort: the RPC succeeded and the invitation exists server-side, so
  /// a failed local insert must not read as a failed invite. The next sync
  /// round brings the row down anyway.
  Future<void> _mirrorInvite(String coachId, String athleteId) async {
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'INSERT OR IGNORE INTO coaching_relationship '
          '(id, coach_user_id, athlete_user_id, created_date) '
          'VALUES (?, ?, ?, ?)',
          [
            // MUST match the stream's `coach_user_id || '-' || athlete_user_id`,
            // or the download lands as a second row.
            '$coachId-$athleteId',
            coachId,
            athleteId,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      });
    } catch (e) {
      debugPrint('CoachRepository.inviteByCode: local mirror failed: $e');
    }
  }
}
