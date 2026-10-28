import 'package:powersync/powersync.dart';

import '../../core/powersync/database.dart' as ps;
import '../models/name_change.dart';

/// The owner's name history, read from the local mirror (2026-10-29).
///
/// Rows arrive through the `user_data` stream (`fact_name_change` where
/// `user_id = auth.user_id()`); a coach never receives the athlete's history,
/// which is why the UI only offers it on the owner's own surfaces.
class NameChangeRepository {
  NameChangeRepository({PowerSyncDatabase? db}) : _db = db ?? ps.db;

  final PowerSyncDatabase _db;

  Future<List<NameChange>> fetchNameChanges({
    required String userId,
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _db.getAll(
      '''
      SELECT * FROM fact_name_change
      WHERE user_id = ? AND entity_type = ? AND entity_id = ?
      ORDER BY changed_at DESC
      ''',
      [userId, entityType, entityId],
    );
    return rows.map((r) => NameChange.fromMap(r)).toList();
  }
}
