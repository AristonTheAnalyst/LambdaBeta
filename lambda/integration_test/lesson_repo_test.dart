import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL LessonRepository against a REAL PowerSync SQLite
/// DB (real schema + real INSTEAD OF triggers incl. powersync_strip_subtype) —
/// the exact code path the running app uses. Run with:
///   flutter test integration_test/lesson_repo_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('real repo: multiple lessons persist; pin is exclusive and never deletes',
      () async {
    final dir = await Directory.systemTemp.createTemp('lambda_ps');
    final db = PowerSyncDatabase(
      schema: schema,
      path: '${dir.path}/test.db',
    );
    await db.initialize();

    final repo = LessonRepository(db: db);
    const userId = 'u1';
    const exerciseId = 'ex1';

    await repo.createLesson(userId, exerciseId, 'lesson one');
    await repo.createLesson(userId, exerciseId, 'lesson two');

    final afterAdd = await repo.fetchLessons(userId, exerciseId);
    expect(afterAdd.length, 2,
        reason: 'both lessons must persist after two createLesson calls');

    await repo.setPinned(userId, exerciseId, afterAdd[0].lessonId, true);
    final afterPin = await repo.fetchLessons(userId, exerciseId);
    expect(afterPin.length, 2, reason: 'pinning must never delete a lesson');
    expect(afterPin.where((l) => l.pinned).length, 1,
        reason: 'only one lesson may be pinned at a time');

    final second = afterPin.firstWhere((l) => !l.pinned);
    await repo.setPinned(userId, exerciseId, second.lessonId, true);
    final afterSwap = await repo.fetchLessons(userId, exerciseId);
    expect(afterSwap.length, 2, reason: 'swapping the pin must not delete');
    expect(afterSwap.where((l) => l.pinned).single.lessonId, second.lessonId);

    await repo.setPinned(userId, exerciseId, second.lessonId, false);
    final afterUnpin = await repo.fetchLessons(userId, exerciseId);
    expect(afterUnpin.length, 2,
        reason: 'unpinning must never delete a lesson');
    expect(afterUnpin.every((l) => !l.pinned), isTrue);

    await db.close();
    await dir.delete(recursive: true);
  });
}
