import 'athlete.dart';

/// One `coaching_relationship` row as the caller sees it (2026-10-26): both
/// sides' ids and names, the invitation date and the consent date.
///
/// The caller is always one side of the row — `user_data` streams their own
/// rows only. [acceptedDate] NULL is a pending invitation: the athlete has not
/// agreed yet, so the athlete's name is absent (the coaching_data stream sends
/// nothing about an unaccepted athlete). The coach's name is present from the
/// invitation on — the athlete cannot judge a request from nobody.
///
/// Since 2026-10-30 either side can ask ([requestedByUserId]): a pending row
/// where the caller is the requester is one they WAIT on, and one where the
/// other side is the requester is one THEY must accept.
class CoachRelationship {
  const CoachRelationship({
    required this.coachUserId,
    required this.athleteUserId,
    this.createdDate,
    this.acceptedDate,
    this.requestedByUserId,
    this.coachFirstName,
    this.coachLastName,
    this.athleteFirstName,
    this.athleteLastName,
  });

  final String coachUserId;
  final String athleteUserId;
  final DateTime? createdDate;
  final DateTime? acceptedDate;

  /// Who asked for the edge: the athlete's id for "coach me", the coach's for
  /// "let me coach you". Null on rows written before the column existed —
  /// those were all coach-initiated.
  final String? requestedByUserId;

  final String? coachFirstName;
  final String? coachLastName;
  final String? athleteFirstName;
  final String? athleteLastName;

  bool get isAccepted => acceptedDate != null;

  /// Whether [userId] is the side that asked. A pending row they asked for is
  /// theirs to accept; one the caller asked for is theirs to wait on.
  bool requestedBy(String userId) =>
      (requestedByUserId ?? coachUserId) == userId;

  /// The coach, named where their `dim_user` slice has synced.
  Athlete get coach => Athlete(
    userId: coachUserId,
    firstName: coachFirstName,
    lastName: coachLastName,
    createdDate: createdDate,
    acceptedDate: acceptedDate,
  );

  /// The athlete, named where their `dim_user` slice has synced — for a
  /// pending invitation it has not, by design.
  Athlete get athlete => Athlete(
    userId: athleteUserId,
    firstName: athleteFirstName,
    lastName: athleteLastName,
    createdDate: createdDate,
    acceptedDate: acceptedDate,
  );

  /// A row of the repository's watch: both ids, the edge's dates, and the two
  /// joined name sets (each nullable until that side's slice syncs).
  factory CoachRelationship.fromMap(Map<String, dynamic> map) =>
      CoachRelationship(
        coachUserId: map['coach_user_id'] as String,
        athleteUserId: map['athlete_user_id'] as String,
        createdDate: map['created_date'] != null
            ? DateTime.tryParse(map['created_date'] as String)
            : null,
        acceptedDate: map['accepted_date'] != null
            ? DateTime.tryParse(map['accepted_date'] as String)
            : null,
        requestedByUserId: map['requested_by_user_id'] as String?,
        coachFirstName: map['coach_first_name'] as String?,
        coachLastName: map['coach_last_name'] as String?,
        athleteFirstName: map['athlete_first_name'] as String?,
        athleteLastName: map['athlete_last_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'coach_user_id': coachUserId,
    'athlete_user_id': athleteUserId,
    'created_date': createdDate?.toIso8601String(),
    'accepted_date': acceptedDate?.toIso8601String(),
    'requested_by_user_id': requestedByUserId,
    'coach_first_name': coachFirstName,
    'coach_last_name': coachLastName,
    'athlete_first_name': athleteFirstName,
    'athlete_last_name': athleteLastName,
  };
}
