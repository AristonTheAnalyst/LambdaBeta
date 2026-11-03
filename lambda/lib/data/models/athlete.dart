/// An athlete a coach reads (2026-10-26).
///
/// The row is `coaching_relationship` (the coach's side) LEFT JOINed to the
/// athlete's `dim_user`, which the coaching_data stream delivers as a
/// name-only slice. [acceptedDate] is the consent gate: a row without it is an
/// invitation still waiting on the athlete (#22), and no athlete data is sent
/// for it — so this list only ever carries accepted rows.
class Athlete {
  const Athlete({
    required this.userId,
    this.firstName,
    this.lastName,
    this.createdDate,
    this.acceptedDate,
  });

  final String userId;
  final String? firstName;
  final String? lastName;

  /// When the coach's invitation was written — the list's tiebreaker under
  /// the name.
  final DateTime? createdDate;

  /// When the athlete accepted; null on an invitation still pending. The
  /// roster reads accepted rows only, but the field is kept so #22's pending
  /// section can draw the same model.
  final DateTime? acceptedDate;

  /// Whether either name part actually carries text — a pending invitation's
  /// person has no synced name, and the screen draws its own fallback label
  /// rather than this model's `Athlete`.
  bool get hasName =>
      (firstName?.trim().isNotEmpty ?? false) ||
      (lastName?.trim().isNotEmpty ?? false);

  /// The name to draw: the athlete's own name, else the word `Athlete` while
  /// their row is on its way. Names are user-typed — read them through
  /// `UserNameText` on screen.
  String get displayName {
    final parts = [
      if (firstName?.trim().isNotEmpty ?? false) firstName!.trim(),
      if (lastName?.trim().isNotEmpty ?? false) lastName!.trim(),
    ];
    return parts.isEmpty ? 'Athlete' : parts.join(' ');
  }

  /// A row of the repository's watch: `athlete_user_id`, the edge's own
  /// dates, plus the joined name columns (nullable until the athlete's rows
  /// sync).
  factory Athlete.fromMap(Map<String, dynamic> map) => Athlete(
    userId: map['athlete_user_id'] as String,
    firstName: map['user_name'] as String?,
    lastName: map['user_lastname'] as String?,
    createdDate: map['created_date'] != null
        ? DateTime.tryParse(map['created_date'] as String)
        : null,
    acceptedDate: map['accepted_date'] != null
        ? DateTime.tryParse(map['accepted_date'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'athlete_user_id': userId,
    'user_name': firstName,
    'user_lastname': lastName,
    'created_date': createdDate?.toIso8601String(),
    'accepted_date': acceptedDate?.toIso8601String(),
  };
}
