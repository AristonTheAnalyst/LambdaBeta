import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/name_limit.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:powersync/powersync.dart';

/// What `ExerciseRepository` does with a name that is too long: refuses it.
///
/// This is the layer the app cannot see past. The PowerSync mirror is a plain
/// `Column.text` with no CHECK support, so without this guard a 21-character
/// name would insert locally, render in the picker, survive a restart — and
/// then fail to upload (quarantined `23514` in `upload_failures`) with nothing
/// shown to the user. The alternative, clamping, is worse: it stores a
/// different name than the user typed.
///
/// The database enforces the same rule (`dim_exercise_name_length_check`,
/// `dim_variation_name_length_check`), so a bypass here is a device and server
/// that disagree about what was written.
///
///   flutter test integration_test/exercise_name_limit_repo_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late ExerciseRepository exercises;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    exercises = ExerciseRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> rowCount(String table) async {
    final rows = await db.getAll('SELECT count(*) AS n FROM $table');
    return rows.first['n'] as int;
  }

  group('createExercise', () {
    test('throws on twenty-one characters, and writes nothing', () async {
      await expectLater(
        exercises.createExercise(userId, 'a' * 21),
        throwsArgumentError,
      );
      expect(await rowCount('dim_exercise'), 0,
          reason: 'a refused name must not leave a half-made row behind');
    });

    test('a name at the limit is written verbatim', () async {
      final name = 'Single Leg Glute Br.';
      expect(name.length, kMaxExerciseNameLength,
          reason: 'the fixture is meant to be exactly at the limit');

      final created = await exercises.createExercise(userId, name);
      expect(created.name, name);
      expect(await rowCount('dim_exercise'), 1);
    });

    test('trailing whitespace does not spend the budget', () async {
      // The rule is measured on the trimmed value, so a name the user padded
      // is still a name that fits. The repository stores the string it is
      // handed, padding included — trimming is the viewmodels' job, and they
      // do it before this call.
      final created = await exercises.createExercise(userId, '${'a' * 20}  ');
      expect(created.name, '${'a' * 20}  ');
      expect(await rowCount('dim_exercise'), 1);
    });
  });

  group('createVariation', () {
    test('throws on twenty-one characters, and writes nothing', () async {
      await expectLater(
        exercises.createVariation(userId, 'b' * 21),
        throwsArgumentError,
      );
      expect(await rowCount('dim_variation'), 0);
    });

    test('a name at the limit is written verbatim', () async {
      final created = await exercises.createVariation(userId, 'c' * 20);
      expect(created.name, 'c' * 20);
      expect(await rowCount('dim_variation'), 1);
    });
  });

  group('the rename paths are guarded too', () {
    // The backfill shortened every over-long name on 2026-09-29, but a rename is
    // only as safe as its write point — the field's limit is a UI fact and the
    // repository is the last one that holds.
    test('updateExercise refuses', () async {
      final created = await exercises.createExercise(userId, 'Squat');
      await expectLater(
        exercises.updateExercise(created.exerciseId, 'd' * 21),
        throwsArgumentError,
      );

      final rows = await db.getAll(
        'SELECT exercise_name FROM dim_exercise WHERE custom_exercise_id = ?',
        [created.exerciseId],
      );
      expect(rows.single['exercise_name'], 'Squat',
          reason: 'the old name stands — a refused rename changes nothing');
    });

    test('updateVariation refuses', () async {
      final created = await exercises.createVariation(userId, 'Paused');
      await expectLater(
        exercises.updateVariation(created.variationId, 'e' * 21),
        throwsArgumentError,
      );

      final rows = await db.getAll(
        'SELECT variation_name FROM dim_variation WHERE custom_variation_id = ?',
        [created.variationId],
      );
      expect(rows.single['variation_name'], 'Paused');
    });
  });
}
