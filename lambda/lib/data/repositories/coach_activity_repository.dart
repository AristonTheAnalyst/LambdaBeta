import 'package:powersync/powersync.dart';

import '../../core/powersync/database.dart' as ps;
import '../models/coach_activity.dart';

/// Reads what a coach did to the viewer's training from the local mirror
/// (2026-10-29). Derived, not stored: creations and edits come from the audit
/// columns, renames from `fact_name_change`.
class CoachActivityRepository {
  CoachActivityRepository({PowerSyncDatabase? db}) : _db = db ?? ps.db;

  final PowerSyncDatabase _db;

  /// The coach the viewer granted, if any. The athlete's own directed friend
  /// row carries the grant and is in `user_data`.
  Future<String?> coachIdFor(String userId) async {
    final rows = await _db.getAll(
      '''
      SELECT friend_user_id FROM friend_relationship
      WHERE user_id = ? AND coaching_granted_at IS NOT NULL
      LIMIT 1
      ''',
      [userId],
    );
    return rows.isEmpty ? null : rows.first['friend_user_id'] as String?;
  }

  Future<String?> coachNameFor(String coachId) async {
    final rows = await _db.getAll(
      'SELECT user_name, user_lastname FROM dim_user WHERE user_id = ?',
      [coachId],
    );
    if (rows.isEmpty) return null;
    final name = [
      if ((rows.first['user_name'] as String?)?.trim().isNotEmpty ?? false)
        (rows.first['user_name'] as String).trim(),
      if ((rows.first['user_lastname'] as String?)?.trim().isNotEmpty ?? false)
        (rows.first['user_lastname'] as String).trim(),
    ].join(' ');
    return name.isEmpty ? null : name;
  }

  Future<List<CoachActivityEntry>> fetch({
    required String userId,
    required String coachId,
  }) async {
    final out = <CoachActivityEntry>[];

    final renames = await _db.getAll(
      '''
      SELECT * FROM fact_name_change
      WHERE user_id = ? AND changed_by_user_id = ?
      ORDER BY changed_at DESC LIMIT 100
      ''',
      [userId, coachId],
    );
    for (final r in renames) {
      final at = DateTime.tryParse('${r['changed_at']}')?.toLocal();
      if (at == null) continue;
      out.add(
        CoachActivityEntry(
          kind: CoachActivityKind.renamed,
          label: (r['entity_type'] as String?) ?? 'exercise',
          name: '${r['old_name'] ?? ''} → ${r['new_name'] ?? ''}',
          at: at,
        ),
      );
    }

    const tables = [
      (table: 'dim_exercise', name: 'exercise_name', label: 'exercise'),
      (table: 'dim_variation', name: 'variation_name', label: 'variation'),
      (table: 'dim_planned_session', name: 'name', label: 'workout'),
      (table: 'fact_goal', name: 'COALESCE(goal_text, \'Goal\')', label: 'goal'),
      (
        table: 'dim_exercise_note',
        name: 'substr(note_text, 1, 60)',
        label: 'note',
      ),
      (
        table: 'fact_session',
        name: "COALESCE(planned_session_name, 'Freestyle session')",
        label: 'session',
      ),
    ];

    for (final t in tables) {
      final rows = await _db.getAll(
        '''
        SELECT ${t.name} AS name, created_at, updated_at,
               created_by_user_id, updated_by_user_id
        FROM ${t.table}
        WHERE user_id = ?
          AND (created_by_user_id = ? OR updated_by_user_id = ?)
        ORDER BY COALESCE(updated_at, created_at) DESC
        LIMIT 100
        ''',
        [userId, coachId, coachId],
      );
      for (final r in rows) {
        final added = r['created_by_user_id'] == coachId;
        final at = DateTime.tryParse(
          '${added ? r['created_at'] : r['updated_at']}',
        )?.toLocal();
        if (at == null) continue;
        out.add(
          CoachActivityEntry(
            kind: added ? CoachActivityKind.added : CoachActivityKind.edited,
            label: t.label,
            name: (r['name'] as String?)?.trim().isNotEmpty == true
                ? (r['name'] as String).trim()
                : 'Untitled ${t.label}',
            at: at,
          ),
        );
      }
    }

    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(100).toList();
  }
}
