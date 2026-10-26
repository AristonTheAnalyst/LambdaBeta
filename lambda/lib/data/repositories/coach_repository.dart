import '../../core/powersync/database.dart' as ps;
import '../models/athlete.dart';

/// The coach's side of a coaching relationship (2026-10-26), read from the
/// local mirror.
///
/// Reads are local-only, exactly like the friends repository's: the coaching_data
/// stream delivers each accepted athlete's name and completed training
/// history, and the coach's own `coaching_relationship` rows ride user_data.
/// Nothing here writes — #22's invite/accept/revoke are the write paths.
///
/// The consent gate lives in two places and this repository trusts both: the
/// stream's `my_athletes` CTE requires `accepted_date`, so an unaccepted
/// invitation sends no athlete rows; and this watch asks for it again, so a
/// pending row never even draws a name.
class CoachRepository {
  /// Accepted athletes, named where their `dim_user` slice has synced.
  /// Ordered by the name the row draws, then by when the invitation was
  /// written — the same order the friends list uses.
  Stream<List<Athlete>> watchAthletes(String coachUserId) => ps.db
      .watch(
        'SELECT cr.athlete_user_id, cr.created_date, cr.accepted_date, '
        'u.user_name, u.user_lastname '
        'FROM coaching_relationship cr '
        'LEFT JOIN dim_user u ON u.user_id = cr.athlete_user_id '
        'WHERE cr.coach_user_id = ? AND cr.accepted_date IS NOT NULL '
        "ORDER BY COALESCE(NULLIF(TRIM(u.user_name), ''), '') COLLATE NOCASE, "
        'cr.created_date',
        parameters: [coachUserId],
      )
      .map((rows) => rows.map(Athlete.fromMap).toList());
}
