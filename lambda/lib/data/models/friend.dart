/// A friend in the list — the caller's own outgoing edge paired with whatever
/// the friend's name row has synced so far (2026-10-23).
///
/// The row is `friend_relationship` (the caller's direction only) LEFT JOINed
/// to the friend's `dim_user`. The name arrives with the friends_data stream;
/// until it does, [displayName] reads `Friend` rather than showing an id.
class Friend {
  const Friend({
    required this.userId,
    this.firstName,
    this.lastName,
    this.createdDate,
  });

  final String userId;
  final String? firstName;
  final String? lastName;

  /// When the caller added this friend — the list's tiebreaker under the
  /// name.
  final DateTime? createdDate;

  /// The name to draw; `Friend` while the friend's name row is still on its
  /// way. Names are user-typed: read them through `UserNameText` on screen.
  String get displayName {
    final parts = [
      if (firstName?.trim().isNotEmpty ?? false) firstName!.trim(),
      if (lastName?.trim().isNotEmpty ?? false) lastName!.trim(),
    ];
    return parts.isEmpty ? 'Friend' : parts.join(' ');
  }

  /// A row of the repository's watch: `friend_user_id` plus the joined name
  /// columns (all nullable until the dim_user row syncs).
  factory Friend.fromMap(Map<String, dynamic> map) => Friend(
    userId: map['friend_user_id'] as String,
    firstName: map['user_name'] as String?,
    lastName: map['user_lastname'] as String?,
    createdDate: map['created_date'] != null
        ? DateTime.tryParse(map['created_date'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'friend_user_id': userId,
    'user_name': firstName,
    'user_lastname': lastName,
    'created_date': createdDate?.toIso8601String(),
  };
}
