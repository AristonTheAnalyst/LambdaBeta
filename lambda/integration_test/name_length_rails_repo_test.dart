import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/name_limit.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:powersync/powersync.dart';

/// What the repositories do with a name longer than its field allows:
/// refuse it, at the column, before anything is written.
///
/// This is the same guard `exercise_name_limit_repo_test.dart` pins for
/// exercises and variations. It matters for the same reason: the PowerSync
/// mirror is a plain `Column.text` with no CHECK (the server's rail is 120,
/// `20261020120000_name_length_rails.sql`), so a write the app allows is a row
/// that inserts locally, renders, survives a restart — and then quarantines on
/// upload with nothing shown to the user.
///
/// The wider kinds carry their own caps (`name_limit.dart`); this file walks
/// each write path at its boundary, because a cap enforced on create but not on
/// rename is a cap with a hole.
///
///   flutter test integration_test/name_length_rails_repo_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late PlannedSessionRepository planned;
  late ProgramRepository programs;
  late ProgramHistoryRepository history;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    planned = PlannedSessionRepository();
    // The REST half is not under test; the local half is.
    programs = ProgramRepository(remote: const LocalOnlyProgramRemote());
    history = ProgramHistoryRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> rowCount(String table) async {
    final rows = await db.getAll('SELECT count(*) AS n FROM $table');
    return rows.first['n'] as int;
  }

  group('workout names — 20', () {
    test(
      'a create one character past the cap is refused, and writes nothing',
      () async {
        await expectLater(
          planned.createPlannedSession(
            userId,
            name: 'a' * (kMaxWorkoutNameLength + 1),
          ),
          throwsArgumentError,
        );
        expect(
          await rowCount('dim_planned_session'),
          0,
          reason: 'a refused name must not leave a half-made row behind',
        );
      },
    );

    test('the name at the limit is written verbatim', () async {
      final name = 'a' * kMaxWorkoutNameLength;
      final created = await planned.createPlannedSession(userId, name: name);
      expect(created.name, name);
      expect(await rowCount('dim_planned_session'), 1);
    });

    test(
      'a rename past the limit is refused, and the old name stands',
      () async {
        final created = await planned.createPlannedSession(
          userId,
          name: 'Push',
        );
        await expectLater(
          planned.updatePlannedSession(
            created.sessionId,
            name: 'a' * (kMaxWorkoutNameLength + 1),
            userId: userId,
          ),
          throwsArgumentError,
        );

        final rows = await db.getAll(
          'SELECT name FROM dim_planned_session WHERE session_id = ?',
          [created.sessionId],
        );
        expect(
          rows.single['name'],
          'Push',
          reason: 'a refused rename changes nothing',
        );
      },
    );

    test(
      'a row written before the cap tightened can still be restored',
      () async {
        // `discardWorkoutChanges` writes back the name the workout was OPENED
        // with. A row from the wider-cap days (or the 30-character one that
        // prompted the tightening, 2026-10-20) must survive that rollback — the
        // grandfather rule in `updatePlannedSession` exists for exactly this
        // write. Without it the discard aborts on its own first statement.
        const id = '00000000-0000-4000-8000-000000000001';
        final oldName = 'a' * 30;
        expect(nameTooLong(oldName, kMaxWorkoutNameLength), isTrue);
        await db.execute(
          '''
        INSERT INTO dim_planned_session
          (id, session_id, user_id, name, notes, date_archived, created_date)
        VALUES (?, ?, ?, ?, NULL, NULL, ?)
        ''',
          [id, id, userId, oldName, DateTime.now().toUtc().toIso8601String()],
        );

        await planned.updatePlannedSession(id, name: oldName, userId: userId);

        final rows = await db.getAll(
          'SELECT name FROM dim_planned_session WHERE session_id = ?',
          [id],
        );
        expect(rows.single['name'], oldName);
      },
    );
  });

  group('program names — 20', () {
    test(
      'a program one character past the cap is refused, and writes nothing',
      () async {
        await expectLater(
          programs.createProgram(
            userId,
            name: 'b' * (kMaxProgramNameLength + 1),
          ),
          throwsArgumentError,
        );
        expect(await rowCount('dim_program'), 0);
      },
    );

    test('the name at the limit is written verbatim', () async {
      final name = 'b' * kMaxProgramNameLength;
      final created = await programs.createProgram(userId, name: name);
      expect(created.name, name);
      expect(await rowCount('dim_program'), 1);
    });

    test('a rename past the limit is refused', () async {
      final created = await programs.createProgram(userId, name: 'Base');
      await expectLater(
        programs.updateProgram(
          created.programId,
          name: 'b' * (kMaxProgramNameLength + 1),
          userId: userId,
        ),
        throwsArgumentError,
      );

      final rows = await db.getAll(
        'SELECT program_name FROM dim_program WHERE program_id = ?',
        [created.programId],
      );
      expect(rows.single['program_name'], 'Base');
    });
  });

  group('block names — 20', () {
    test(
      'a create one character past the cap is refused, and writes nothing',
      () async {
        final program = await programs.createProgram(userId, name: 'P');
        await expectLater(
          programs.createProgramBlock(
            userId,
            programId: program.programId,
            name: 'c' * (kMaxBlockNameLength + 1),
          ),
          throwsArgumentError,
        );
        expect(await rowCount('dim_program_block'), 0);
      },
    );

    test('the name at the limit is written verbatim', () async {
      final program = await programs.createProgram(userId, name: 'P');
      final name = 'c' * kMaxBlockNameLength;
      final block = await programs.createProgramBlock(
        userId,
        programId: program.programId,
        name: name,
      );
      expect(block.name, name);
      expect(await rowCount('dim_program_block'), 1);
    });

    test('a rename past the limit is refused', () async {
      final program = await programs.createProgram(userId, name: 'P');
      final block = await programs.createProgramBlock(
        userId,
        programId: program.programId,
        name: 'Base',
      );
      await expectLater(
        programs.updateBlock(
          block.blockId,
          name: 'c' * (kMaxBlockNameLength + 1),
        ),
        throwsArgumentError,
      );

      final rows = await db.getAll(
        'SELECT name FROM dim_program_block WHERE block_id = ?',
        [block.blockId],
      );
      expect(rows.single['name'], 'Base');
    });
  });

  group('review titles — 20', () {
    test(
      'a title one character past the cap is refused, and writes nothing',
      () async {
        await expectLater(
          history.scheduleReview(
            userId: userId,
            sessionIds: const ['s1'],
            title: 'd' * (kMaxReviewTitleLength + 1),
          ),
          throwsArgumentError,
        );
        expect(await rowCount('fact_program_review'), 0);
      },
    );

    test('the title at the limit is written verbatim', () async {
      final title = 'd' * kMaxReviewTitleLength;
      final review = await history.scheduleReview(
        userId: userId,
        sessionIds: const ['s1'],
        title: title,
      );
      expect(review.title, title);
      expect(await rowCount('fact_program_review'), 1);
    });

    test('an absent title is not this rule', () async {
      // A pass may go unnamed — the list falls back to its workouts' names.
      final review = await history.scheduleReview(
        userId: userId,
        sessionIds: const ['s1'],
      );
      expect(review.title, isNull);
      expect(await rowCount('fact_program_review'), 1);
    });
  });
}
