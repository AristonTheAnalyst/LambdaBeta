import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;

const _uuid = Uuid();

/// Per-exercise PR journey view settings. Stores only HIDDEN axes — the
/// absence of a row means the axis is visible, so a fresh account (and any
/// new axis) defaults to visible. Strictly a view preference for the
/// exercise insights page; nothing else reads this table.
class PrViewSettingRepository {
  /// The hidden axes for one exercise: (hidden rep counts, hidden weights).
  /// Weights are stored/compared by their formatted string (e.g. "72.5").
  Future<({Set<int> hiddenReps, Set<String> hiddenWeights})> fetchHidden(
    String userId,
    String exerciseId,
  ) async {
    final rows = await ps.db.getAll(
      'SELECT axis_type, axis_value FROM dim_pr_view_setting WHERE user_id = ? AND exercise_id = ?',
      [userId, exerciseId],
    );
    final hiddenReps = <int>{};
    final hiddenWeights = <String>{};
    for (final r in rows) {
      final type = '${r['axis_type']}';
      final value = '${r['axis_value']}';
      if (type == 'reps') {
        hiddenReps.add(int.tryParse(value) ?? 0);
      } else {
        hiddenWeights.add(value);
      }
    }
    return (hiddenReps: hiddenReps, hiddenWeights: hiddenWeights);
  }

  Future<void> hideAxis(
    String userId,
    String exerciseId,
    String axisType,
    String axisValue,
  ) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_pr_view_setting
        (id, pr_view_setting_id, user_id, exercise_id, axis_type, axis_value)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, exerciseId, axisType, axisValue],
    );
  }

  Future<void> showAxis(
    String userId,
    String exerciseId,
    String axisType,
    String axisValue,
  ) async {
    await ps.db.execute(
      '''
      DELETE FROM dim_pr_view_setting
      WHERE user_id = ? AND exercise_id = ? AND axis_type = ? AND axis_value = ?
      ''',
      [userId, exerciseId, axisType, axisValue],
    );
  }
}
