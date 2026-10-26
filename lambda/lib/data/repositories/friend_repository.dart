import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/powersync/database.dart' as ps;
import '../../core/utils/friend_code.dart';
import '../../core/utils/lambda_exception.dart';
import '../../core/utils/name_limit.dart';
import '../cache/past_sets_timeline_cache.dart';
import '../models/friend.dart';

/// What the add RPC reports back: the friend it matched, and whether the
/// friendship is new ([created] false = you were already friends).
class AddFriendResult {
  const AddFriendResult({required this.friend, required this.created});

  final Friend friend;
  final bool created;
}

/// The network half of [FriendRepository] (2026-10-23) — the two calls that
/// must reach the server, in the [ProgramRunRemote] seam's shape. A seam, not
/// an abstraction for its own sake: host tests cannot construct
/// `Supabase.instance`, so the RPC contract is only testable through an
/// injected object.
abstract class FriendRemote {
  /// Resolves [code] to a user and makes the friendship mutual, server-side.
  /// Throws [LambdaException] with a user-facing sentence on refusal.
  Future<AddFriendResult> addByCode(String code);

  /// Removes both directions of the friendship.
  Future<void> remove(String friendUserId);
}

/// The real remote: Supabase RPCs via the ambient client. The SQL side is
/// SECURITY DEFINER — a client cannot write the other user's directed row
/// itself, and the RPC is the only path that writes both.
class SupabaseFriendRemote implements FriendRemote {
  const SupabaseFriendRemote();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<AddFriendResult> addByCode(String code) async {
    try {
      final data = await _client
          .rpc('add_friend_by_code', params: {'p_code': code})
          .timeout(const Duration(seconds: 8));
      // The function returns one jsonb object (not a row set).
      final map = (data as Map).cast<String, dynamic>();
      return AddFriendResult(
        friend: Friend(
          userId: map['friend_user_id'] as String,
          firstName: map['friend_user_name'] as String?,
          lastName: map['friend_user_lastname'] as String?,
        ),
        created: map['created'] as bool? ?? true,
      );
    } on PostgrestException catch (e) {
      throw LambdaException(_addErrorMessage(e.message));
    }
  }

  @override
  Future<void> remove(String friendUserId) async {
    try {
      await _client
          .rpc('remove_friend', params: {'p_friend_user_id': friendUserId})
          .timeout(const Duration(seconds: 8));
    } on PostgrestException catch (_) {
      throw const LambdaException(
        'Could not remove that friend. Try again in a moment.',
      );
    }
  }

  /// The RPC's `raise exception` text is the key; one sentence per outcome.
  static String _addErrorMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('friend_code_invalid')) {
      return "That friend code doesn't look right. Check it and try again.";
    }
    if (m.contains('friend_code_not_found')) {
      return 'No one has that friend code.';
    }
    if (m.contains('cannot_add_self')) {
      return "That's your own friend code — share it with a friend instead.";
    }
    if (m.contains('not_authenticated')) {
      return 'Your session has expired — sign in again.';
    }
    return 'Could not add that friend. Try again in a moment.';
  }
}

/// Friends, read from the local mirror and changed through the RPCs
/// (2026-10-23).
///
/// Reads are local-only: the friends_data sync stream delivers the caller's
/// own relationship rows, each friend's NAME (a partial dim_user slice),
/// their code and their completed training history. Writes are RPC-first,
/// then mirrored locally so the list updates in the same beat — except a
/// nickname, which is local-first: it touches only the caller's own directed
/// row, so the uploader's composite-key patch is the whole remote half.
///
/// * The mirror inserts ONLY the caller's own directed row, under the
///   synthetic id `'<userId>-<friendId>'` the stream uses. The reciprocal row
///   belongs to the friend and is written by the RPC; mirroring it here would
///   queue a PUT the friend's RLS rejects — a fatal upload that quarantines
///   the row. The friend's `dim_user` row is never mirrored for the same
///   reason; their name arrives by download.
/// * A removal's queued DELETE resolves its pair from the local row, which is
///   already gone by then, so the uploader skips it — harmless, because the
///   RPC has already deleted both rows server-side.
class FriendRepository {
  FriendRepository({FriendRemote? remote})
    : _remote = remote ?? const SupabaseFriendRemote();

  final FriendRemote _remote;

  /// The caller's friends, named where the friend's rows have synced.
  /// Outgoing rows only — the stream sends no other kind — ordered by the
  /// name the row DRAWS (nickname, else the friend's name, else their code),
  /// then by when they were added.
  Stream<List<Friend>> watchFriends(String userId) => ps.db
      .watch(
        'SELECT fr.friend_user_id, fr.created_date, fr.nickname, '
        'fr.share_notes, u.user_name, u.user_lastname, c.friend_code '
        'FROM friend_relationship fr '
        'LEFT JOIN dim_user u ON u.user_id = fr.friend_user_id '
        'LEFT JOIN dim_friend_code c ON c.user_id = fr.friend_user_id '
        'WHERE fr.user_id = ? '
        'ORDER BY COALESCE('
        "NULLIF(TRIM(fr.nickname), ''), "
        "NULLIF(TRIM(u.user_name), ''), "
        "c.friend_code, '') COLLATE NOCASE, fr.created_date",
        parameters: [userId],
      )
      .map((rows) => rows.map(Friend.fromMap).toList());

  /// The caller's own shareable code; null until the row first syncs.
  Stream<String?> watchMyCode(String userId) => ps.db
      .watch(
        'SELECT friend_code FROM dim_friend_code WHERE user_id = ?',
        parameters: [userId],
      )
      .map(
        (rows) => rows.isEmpty ? null : rows.first['friend_code'] as String?,
      );

  /// Adds [rawCode]'s owner as a friend — instantly mutual, no request step.
  /// A malformed code is refused here, before any network call; the server
  /// applies the same rule.
  Future<AddFriendResult> addByCode(String userId, String rawCode) async {
    final code = normalizeFriendCode(rawCode);
    if (code == null) {
      throw const LambdaException(
        "That friend code doesn't look right. Check it and try again.",
      );
    }
    final result = await _remote.addByCode(code);
    await _mirrorAdd(userId, result.friend.userId);
    return result;
  }

  /// Cuts the friendship on both sides (the RPC deletes the pair), then drops
  /// the local row so the list empties at once. The removed friend's cached
  /// timeline is dropped too — their rows leave the device on the next sync
  /// round, and nothing may serve them in between.
  Future<void> removeFriend(String userId, String friendId) async {
    await _remote.remove(friendId);
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'DELETE FROM friend_relationship '
          'WHERE user_id = ? AND friend_user_id = ?',
          [userId, friendId],
        );
      });
    } catch (e) {
      debugPrint('FriendRepository.removeFriend: local delete failed: $e');
    }
    PastSetsTimelineCache.instance.invalidate(friendId);
  }

  /// Sets — or clears, with null or a blank value — the caller's private
  /// label for one friend.
  ///
  /// The repository's one LOCAL-FIRST write: it touches only the caller's own
  /// `friend_relationship` row, which the uploader already knows how to patch
  /// on the composite key, so the watch repaints in the same beat and the
  /// label survives offline. Add and remove stay RPC-first because they write
  /// the friend's half too.
  ///
  /// Throws [ArgumentError] above [kMaxFriendNicknameLength] chars — the
  /// repository is the rail, since the mirror has no CHECK (the database's
  /// own rail is 120).
  Future<void> setNickname(
    String userId,
    String friendId,
    String? nickname,
  ) async {
    final trimmed = nickname?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (value != null && nameTooLong(value, kMaxFriendNicknameLength)) {
      throw ArgumentError.value(
        value,
        'nickname',
        'exceeds $kMaxFriendNicknameLength characters',
      );
    }
    await ps.safeExec(
      'UPDATE friend_relationship SET nickname = ? '
      'WHERE user_id = ? AND friend_user_id = ?',
      [value, userId, friendId],
    );
  }

  /// Sets whether the caller shares NOTES with [friendId] (2026-10-26, #23).
  ///
  /// Local-first, like [setNickname]: the flag lives on the caller's own
  /// directed row, so the composite-key UPDATE is the whole write — the
  /// uploader patches the pair, the friend's device stops (or starts) being
  /// sent this caller's exercise notes and session notes on the next sync
  /// round, and nothing about the caller's numbers changes either way.
  Future<void> setShareNotes(
    String userId,
    String friendId,
    bool shareNotes,
  ) async {
    await ps.safeExec(
      'UPDATE friend_relationship SET share_notes = ? '
      'WHERE user_id = ? AND friend_user_id = ?',
      [shareNotes ? 1 : 0, userId, friendId],
    );
  }

  /// Best-effort: the RPC succeeded and the friendship exists server-side, so
  /// a failed local insert must not read as a failed add. The next sync round
  /// brings the row down anyway.
  Future<void> _mirrorAdd(String userId, String friendId) async {
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          'INSERT OR IGNORE INTO friend_relationship '
          '(id, user_id, friend_user_id, created_date, share_notes) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            // MUST match the stream's `user_id || '-' || friend_user_id`,
            // or the download lands as a second row.
            '$userId-$friendId',
            userId,
            friendId,
            DateTime.now().toUtc().toIso8601String(),
            // The server column is NOT NULL DEFAULT false, and the local
            // mirror has no defaults: a NULL here would ride the uploader's
            // upsert into a 23502 and quarantine the row. A new friendship
            // starts on the first tier — numbers only.
            0,
          ],
        );
      });
    } catch (e) {
      debugPrint('FriendRepository.addByCode: local mirror failed: $e');
    }
  }
}
