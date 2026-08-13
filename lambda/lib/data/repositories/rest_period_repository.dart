import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;

const _uuid = Uuid();

/// Logs every rest-timer run as its own event — planned vs. actual duration,
/// so a completed rest and a skipped/cut-short one are distinguishable.
class RestPeriodRepository {
  Future<void> logRestPeriod(
    String userId,
    String workoutId, {
    String? exerciseId,
    required int plannedSeconds,
    required int actualSeconds,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO fact_rest
        (id, rest_id, user_id, session_id, custom_exercise_id,
         planned_seconds, actual_seconds, rest_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        workoutId,
        exerciseId,
        plannedSeconds,
        actualSeconds,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> deleteForWorkout(String workoutId) async {
    await ps.db.execute(
      'DELETE FROM fact_rest WHERE session_id = ?',
      [workoutId],
    );
  }
}
