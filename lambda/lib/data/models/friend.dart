import '../../core/utils/friend_code.dart';

/// A friend in the list — the caller's own outgoing edge paired with whatever
/// the friend's name row and code have synced so far (2026-10-23, nicknames
/// 2026-10-25).
///
/// The row is `friend_relationship` (the caller's direction only) LEFT JOINed
/// to the friend's `dim_user` and `dim_friend_code`. [displayName] falls back
/// through the nickname, the friend's own name, their code, and finally the
/// word `Friend` while nothing has synced.
class Friend {
  const Friend({
    required this.userId,
    this.firstName,
    this.lastName,
    this.nickname,
    this.friendCode,
    this.createdDate,
    this.shareNotes = false,
  });

  final String userId;
  final String? firstName;
  final String? lastName;

  /// The caller's private label for this friend. It lives on the caller's
  /// directed `friend_relationship` row — the only half the friends stream
  /// sends them — so it never reaches the friend.
  final String? nickname;

  /// Whether the caller shares notes with this friend (2026-10-26, #23) — the
  /// second privacy tier, also on the caller's own row. The numbers and each
  /// set's notes are shared regardless; exercise notes and a session's
  /// pre/post notes ride only when this is true.
  final bool shareNotes;

  /// The friend's shareable code, drawn `ABCD-EFGH` by [fallbackName]. Null
  /// until the friend's code row syncs.
  final String? friendCode;

  /// When the caller added this friend — the list's tiebreaker under the
  /// name.
  final DateTime? createdDate;

  /// What the row reads when no nickname is set: the friend's own name, else
  /// their code (the shareable handle), else `Friend` while both are on their
  /// way.
  String get fallbackName {
    final parts = [
      if (firstName?.trim().isNotEmpty ?? false) firstName!.trim(),
      if (lastName?.trim().isNotEmpty ?? false) lastName!.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    final code = friendCode?.trim();
    if (code != null && code.isNotEmpty) return formatFriendCode(code);
    return 'Friend';
  }

  /// The name to draw: the caller's [nickname], else [fallbackName]. Names
  /// are user-typed: read them through `UserNameText` on screen.
  String get displayName {
    final nick = nickname?.trim();
    return (nick == null || nick.isEmpty) ? fallbackName : nick;
  }

  /// A row of the repository's watch: `friend_user_id`, the row's own
  /// `nickname` and `share_notes`, plus the joined name and code columns (all
  /// nullable until the friend's rows sync).
  factory Friend.fromMap(Map<String, dynamic> map) => Friend(
    userId: map['friend_user_id'] as String,
    firstName: map['user_name'] as String?,
    lastName: map['user_lastname'] as String?,
    nickname: map['nickname'] as String?,
    friendCode: map['friend_code'] as String?,
    createdDate: map['created_date'] != null
        ? DateTime.tryParse(map['created_date'] as String)
        : null,
    // The mirror has no boolean type: 1 = sharing, 0 (or a row that predates
    // the column) = numbers only.
    shareNotes: (map['share_notes'] as int? ?? 0) != 0,
  );

  Map<String, dynamic> toMap() => {
    'friend_user_id': userId,
    'user_name': firstName,
    'user_lastname': lastName,
    'nickname': nickname,
    'friend_code': friendCode,
    'created_date': createdDate?.toIso8601String(),
    'share_notes': shareNotes ? 1 : 0,
  };
}
