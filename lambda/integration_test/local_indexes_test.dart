import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:powersync/powersync.dart';

/// The declared schema indexes are real local artifacts.
///
/// Every hot read filters or joins on FK/user columns, and the on-device
/// SQLite mirror is built from this schema — the server's indexes (in
/// supabase/migrations) do not exist here. This pins that the schema-declared
/// `Index` objects actually become local indexes that the query planner uses,
/// and that the writes still queue for upload (indexes must not disturb the
/// INSTEAD OF triggers).
///
///   flutter test integration_test/local_indexes_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_idx');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// The CREATE INDEX statements sqlite_master holds — one row per index, as
  /// `name | sql`. PowerSync names them `<table>__<name>` and may target the
  /// underlying `ps_data__*` tables rather than the app-visible views, so
  /// existence is matched by what the statement indexes, not its name.
  Future<List<(String, String)>> indexSqls() async {
    final rows = await db.getAll(
      "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
    );
    return rows
        .map((r) => (r['name']! as String, r['sql']! as String))
        .toList();
  }

  void expectIndexed(
    List<(String, String)> indexes,
    String tablePart,
    List<String> columns,
  ) {
    final match = indexes.where(
      (r) =>
          r.$2.contains(tablePart) &&
          columns.every((c) => r.$2.contains(c)),
    );
    expect(match, isNotEmpty,
        reason: 'no local index covers $tablePart(${columns.join(', ')}) — '
            'sqlite_master holds: ${indexes.map((r) => r.$1).toList()}');
  }

  /// The plan rows for [sql], as the planner's detail lines.
  Future<String> plan(String sql, List<Object?> params) async {
    final rows = await db.getAll('EXPLAIN QUERY PLAN $sql', params);
    return rows.map((r) => r['detail']).join('\n');
  }

  test('every declared index exists locally', () async {
    final indexes = await indexSqls();

    expectIndexed(indexes, 'fact_session', ['user_id', 'end_datetime']);
    expectIndexed(indexes, 'fact_session_exercise', ['session_id']);
    expectIndexed(
      indexes,
      'fact_session_exercise_set',
      ['session_exercise_id'],
    );
    expectIndexed(indexes, 'dim_exercise', ['user_id']);
    expectIndexed(indexes, 'dim_variation', ['user_id']);
    expectIndexed(indexes, 'dim_lesson', ['user_id', 'custom_exercise_id']);
    expectIndexed(indexes, 'dim_planned_session', ['user_id']);
    expectIndexed(
      indexes,
      'dim_planned_session_exercise',
      ['planned_session_id'],
    );
    expectIndexed(
      indexes,
      'dim_planned_session_exercise_set',
      ['planned_exercise_id'],
    );
    expectIndexed(
      indexes,
      'dim_planned_session_program',
      ['planned_session_id'],
    );
  });

  test('the hot set reads use the session_exercise_id index', () async {
    // The exact SQL of loadSetsForSession / loadPastSetsTimeline — the
    // session-scoped read and the timeline's sets join both funnel through
    // this column, so both must stop scanning the sets table.
    final setsJoin = '''
      SELECT s.*, fe.custom_exercise_id, fe.session_id,
             e.exercise_name, v.variation_name
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = fe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE fe.session_id = ?
      ORDER BY fe.exercise_order, s.set_number
    ''';

    final planText = await plan(setsJoin, ['s1']);
    expect(planText, contains('USING INDEX'),
        reason: 'the sets join should walk an index, not scan — plan:\n$planText');
    expect(planText.toLowerCase(), isNot(contains('scan fact_session_exercise_set')),
        reason: 'plan:\n$planText');
  });

  test('the timeline read uses the fact_session user index', () async {
    final timeline = '''
      SELECT s.*, w.created_datetime, fe.custom_exercise_id, fe.session_id,
             e.exercise_name, v.variation_name
      FROM fact_session_exercise_set s
      JOIN fact_session_exercise fe ON fe.session_exercise_id = s.session_exercise_id
      INNER JOIN fact_session w ON w.session_id = fe.session_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = fe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE w.user_id = ? AND w.end_datetime IS NOT NULL
      ORDER BY w.created_datetime DESC, fe.exercise_order, s.set_number
    ''';

    final planText = await plan(timeline, [userId]);
    expect(planText.toLowerCase(), isNot(contains('scan fact_session')),
        reason: 'the timeline entry point is fact_session by user — plan:\n$planText');
  });

  test('a write through the repo still queues for upload', () async {
    final sessionId = await repo.createSession(userId);
    final group = await repo.insertSessionExercise(
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: 1,
      exerciseId: 'ex-bench',
    );
    final set = await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      setNumber: 1,
      reps: const [],
    );

    await repo.updateSet(set.sessionExerciseSetId, weight: 5);

    final crud = await db.getAll('SELECT COUNT(*) AS c FROM ps_crud');
    expect(crud.single['c'], greaterThan(0),
        reason: 'the update must still reach ps_crud — the local index is '
            'read-side only and cannot disturb the write triggers');
  });
}
