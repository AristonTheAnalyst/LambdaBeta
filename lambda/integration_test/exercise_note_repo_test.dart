import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL ExerciseNoteRepository against a REAL PowerSync SQLite
/// DB (real schema + real INSTEAD OF triggers incl. powersync_strip_subtype) —
/// the exact code path the running app uses. Run with:
///   flutter test integration_test/exercise_note_repo_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('real repo: multiple notes persist; pin is exclusive and never deletes',
      () async {
    final dir = await Directory.systemTemp.createTemp('lambda_ps');
    final db = PowerSyncDatabase(
      schema: schema,
      path: '${dir.path}/test.db',
    );
    await db.initialize();

    final repo = ExerciseNoteRepository(db: db);
    const userId = 'u1';
    const exerciseId = 'ex1';

    await repo.createNote(userId, exerciseId, 'note one');
    await repo.createNote(userId, exerciseId, 'note two');

    final afterAdd = await repo.fetchNotes(userId, exerciseId);
    expect(afterAdd.length, 2,
        reason: 'both notes must persist after two createNote calls');

    await repo.setPinned(userId, exerciseId, afterAdd[0].exerciseNoteId, true);
    final afterPin = await repo.fetchNotes(userId, exerciseId);
    expect(afterPin.length, 2, reason: 'pinning must never delete a note');
    expect(afterPin.where((l) => l.pinned).length, 1,
        reason: 'only one note may be pinned at a time');

    final second = afterPin.firstWhere((l) => !l.pinned);
    await repo.setPinned(userId, exerciseId, second.exerciseNoteId, true);
    final afterSwap = await repo.fetchNotes(userId, exerciseId);
    expect(afterSwap.length, 2, reason: 'swapping the pin must not delete');
    expect(afterSwap.where((l) => l.pinned).single.exerciseNoteId, second.exerciseNoteId);

    await repo.setPinned(userId, exerciseId, second.exerciseNoteId, false);
    final afterUnpin = await repo.fetchNotes(userId, exerciseId);
    expect(afterUnpin.length, 2,
        reason: 'unpinning must never delete a note');
    expect(afterUnpin.every((l) => !l.pinned), isTrue);

    await db.close();
    await dir.delete(recursive: true);
  });
}
