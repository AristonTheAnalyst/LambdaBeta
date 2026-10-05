import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../core/utils/lambda_exception.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session.dart';
import '../models/planned_session_program.dart';
import '../models/program.dart';
import '../models/program_block.dart';
import '../models/goal.dart';
import '../../shared/utils/unique_name.dart';
import 'planned_session_repository.dart';

const _uuid = Uuid();

/// Turns a partial `{column: value}` update map into a `SET col = ?, ...`
/// clause plus its bound parameters, for the dynamic partial-update methods
/// below.
(String, List<Object?>) _buildSetClause(Map<String, dynamic> updates) {
  final clause = updates.keys.map((k) => '$k = ?').join(', ');
  return (clause, updates.values.toList());
}

/// The network half of [ProgramRepository] — the four calls that go straight
/// to Supabase.
///
/// Most of this repository is local-first: a read tries the PowerSync mirror
/// and falls back to REST only when it comes up empty, and a write is purely
/// local (PowerSync uploads it). Two creates are the exception — `createProgram`
/// and `createProgramBlock` are REST-first, because a row the server has never
/// seen would make the next dependent upload (a workout assigned to a block, a
/// run started against one) fail on the server. Those same two mirror their row
/// back locally, and the mirror exists so the UI can read the row immediately
/// rather than waiting for a download.
///
/// A seam, not an abstraction for its own sake — the same one
/// `ProgramRunRemote` is: tests cannot construct `Supabase.instance` at all, so
/// the REST-first create paths, and the local mirror that is their whole point,
/// are only reachable through an injected object. Each method is exactly one
/// REST call; the local half stays in the repository.
abstract class ProgramRemote {
  Future<List<Map<String, dynamic>>> fetchPrograms(String userId);

  Future<Map<String, dynamic>?> fetchProgram(String programId);

  Future<void> insertProgram(Map<String, dynamic> row);

  Future<void> insertBlock(Map<String, dynamic> row);
}

/// The real remote: Supabase REST via the ambient client.
class SupabaseProgramRemote implements ProgramRemote {
  const SupabaseProgramRemote();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> fetchPrograms(String userId) async {
    return await _client
        .from('dim_program')
        .select('*')
        .eq('user_id', userId)
        .isFilter('date_archived', null)
        .order('program_created_date', ascending: false)
        .timeout(const Duration(seconds: 5));
  }

  @override
  Future<Map<String, dynamic>?> fetchProgram(String programId) async {
    final remote = await _client
        .from('dim_program')
        .select('*')
        .eq('program_id', programId)
        .limit(1)
        .timeout(const Duration(seconds: 5));
    return remote.isEmpty ? null : remote.first;
  }

  @override
  Future<void> insertProgram(Map<String, dynamic> row) async {
    await _client
        .from('dim_program')
        .insert(row)
        .timeout(const Duration(seconds: 8));
  }

  @override
  Future<void> insertBlock(Map<String, dynamic> row) async {
    await _client
        .from('dim_program_block')
        .insert(row)
        .timeout(const Duration(seconds: 8));
  }
}

/// Program library CRUD — programs (dimensions), their planned sessions, and
/// goals. Programs are soft-deleted via is_archived so run history never
/// dangles. Planned-session reads/writes delegate to [PlannedSessionRepository].
class ProgramRepository {
  ProgramRepository({ProgramRemote? remote})
      : _remote = remote ?? const SupabaseProgramRemote();

  final ProgramRemote _remote;
  final PlannedSessionRepository _plannedRepo = PlannedSessionRepository();
  // ── Programs ─────────────────────────────────────────────────────────────

  /// Program names for [userId], used to bump auto-generated defaults.
  Future<Set<String>> _programNames(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT program_name FROM dim_program WHERE user_id = ? AND date_archived IS NULL',
      [userId],
    );
    return rows.map((r) => r['program_name'] as String).toSet();
  }

  /// Returns true if another program owned by `userId` already has [name]
  /// (ignoring [excludeProgramId] when provided).
  Future<bool> _programNameExists(String userId, String name,
      {String? excludeProgramId}) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM dim_program
      WHERE user_id = ? AND date_archived IS NULL AND LOWER(program_name) = LOWER(?)
        ${excludeProgramId != null ? 'AND program_id != ?' : ''}
      LIMIT 1
      ''',
      [
        userId,
        name.trim(),
        ?excludeProgramId,
      ],
    );
    return rows.isNotEmpty;
  }

  /// Throws a [LambdaException] if another program owned by `userId` already
  /// has [name] — the message is shown to the user as it stands.
  Future<void> _assertProgramNameUnique(
      String userId, String name, {String? excludeProgramId}) async {
    if (await _programNameExists(userId, name,
        excludeProgramId: excludeProgramId)) {
      throw LambdaException('A program named "$name" already exists.');
    }
  }

  Future<List<Program>> fetchPrograms(String userId) async {
    // 1. Try the local PowerSync mirror.
    try {
      final rows = await ps.db.getAll(
        'SELECT * FROM dim_program WHERE user_id = ? AND date_archived IS NULL ORDER BY program_created_date DESC',
        [userId],
      ).timeout(const Duration(seconds: 3));
      if (rows.isNotEmpty) return rows.map((r) => Program.fromMap(r)).toList();
    } catch (_) {
      // Timed out — fall through to REST.
    }

    // 2. Fall back to Supabase REST.
    try {
      final remote = await _remote.fetchPrograms(userId);
      return remote.map((r) => Program.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Archived programs, latest archived first — the programs tab's
  /// archived sheet.
  Future<List<Program>> fetchArchivedPrograms(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program WHERE user_id = ? AND date_archived IS NOT NULL ORDER BY date_archived DESC',
      [userId],
    );
    return rows.map((r) => Program.fromMap(r)).toList();
  }

  /// Re-enables an archived program (clears its archive date).
  Future<void> reactivateProgram(String programId) async {
    await ps.db.execute(
      'UPDATE dim_program SET date_archived = NULL WHERE program_id = ?',
      [programId],
    );
  }

  Future<Program?> fetchProgram(String programId) async {
    // 1. Try the local PowerSync mirror.
    try {
      final rows = await ps.db.getAll(
        'SELECT * FROM dim_program WHERE program_id = ?',
        [programId],
      ).timeout(const Duration(seconds: 3));
      if (rows.isNotEmpty) return Program.fromMap(rows.first);
    } catch (_) {
      // Timed out — fall through to REST.
    }

    // 2. Fall back to Supabase REST.
    try {
      final remote = await _remote.fetchProgram(programId);
      if (remote != null) return Program.fromMap(remote);
    } catch (_) {}
    return null;
  }

  /// Creates a program. When [name] is null the app auto-generates one
  /// ("New Program", "New Program 2", …) bumped against the local mirror so it
  /// never throws; when a user-typed [name] is given, it must be unique.
  ///
  /// Like all name-uniqueness in this app, the check is client-side against
  /// the device's local PowerSync mirror — names are NOT unique at the
  /// database level, so two offline devices can still independently create
  /// (or rename to) the same string and the server accepts a cosmetic
  /// duplicate after sync. Records are keyed by UUID, never by name.
  Future<Program> createProgram(
    String userId, {
    String? name,
    String? description,
    bool usesBlocks = false,
  }) async {
    var finalName = name;
    if (finalName == null) {
      final names = await _programNames(userId);
      finalName = uniqueName('New Program', names);
    } else {
      await _assertProgramNameUnique(userId, finalName);
    }
    final id = _uuid.v4();
    // .toUtc() avoids a naive local-time string being reinterpreted as UTC
    // by Postgres's timestamptz column (see SessionRepository.createSession).
    final createdDate = DateTime.now().toUtc();

    // 1. Authoritative write — hits Supabase directly so the program exists
    //    server-side even if PowerSync is stuck reconciling a checkpoint.
    await _remote.insertProgram({
      'program_id': id,
      'user_id': userId,
      'program_name': finalName,
      'program_description': description,
      'date_archived': null,
      'program_created_date': createdDate.toIso8601String(),
      'program_updated_date': createdDate.toIso8601String(),
      // The shape is written at creation because it is one-way: nothing in
      // the app ever flips it afterwards.
      'uses_blocks': usesBlocks,
      'default_target_sessions': null,
    });

    // Mirror it locally, under the same id — the same fix, for the same reason,
    // as `createProgramBlock` below and `startProgramRun`. The library reads
    // `fetchPrograms` locally, so without this the program the wizard just
    // created is missing from the list it returns to until a download lands.
    // The queued PUT is idempotent: the uploader upserts, and the server's copy
    // downloads onto the same row. Best-effort, like the others.
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          '''
          INSERT INTO dim_program
            (id, program_id, user_id, program_name, program_description,
             date_archived, program_created_date, program_updated_date,
             uses_blocks, default_target_sessions)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            id,
            id,
            userId,
            finalName,
            description,
            null,
            createdDate.toIso8601String(),
            createdDate.toIso8601String(),
            usesBlocks ? 1 : 0,
            null,
          ],
        );
      });
    } catch (e) {
      debugPrint('createProgram: local mirror failed: $e');
    }

    return Program(
      programId: id,
      userId: userId,
      name: finalName,
      description: description,
      createdDate: createdDate,
      updatedDate: createdDate,
      usesBlocks: usesBlocks,
    );
  }

  Future<void> updateProgram(
    String programId, {
    String? name,
    String? description,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertProgramNameUnique(userId, name, excludeProgramId: programId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['program_name'] = name;
    if (description != null) updates['program_description'] = description;
    if (updates.isEmpty) return;
    updates['program_updated_date'] = DateTime.now().toUtc().toIso8601String();
    final (setClause, params) = _buildSetClause(updates);
    await ps.safeExec(
      'UPDATE dim_program SET $setClause WHERE program_id = ?',
      [...params, programId],
    );
  }

  /// Remembers a simple program's own length: the session count its last begin
  /// used, so the next begin opens on it instead of asking from scratch.
  ///
  /// The run still owns the number it runs against — this is what the program
  /// suggests, never what an attempt in flight is measured by, which is why
  /// editing a default can never rewrite a run. A block run has no number of
  /// its own to remember (the block owns the length), so a begin carrying a
  /// [blockId] is a no-op here rather than something each caller has to
  /// remember to skip.
  ///
  /// Best-effort by design: this is called once the run is already live, and a
  /// forgotten default — at worst a prefilled field next time — is never worth
  /// reporting the begin as failed for.
  Future<void> rememberDefaultTargetSessions(
    String programId, {
    String? blockId,
    required int? targetSessions,
  }) async {
    if (blockId != null || targetSessions == null) return;
    try {
      await ps.safeExec(
        'UPDATE dim_program SET default_target_sessions = ? '
        'WHERE program_id = ?',
        [targetSessions, programId],
      );
    } catch (e) {
      debugPrint('ProgramRepository: could not remember the target length of '
          '$programId: $e');
    }
  }

  /// How many active blocks each of a user's programs has, keyed by program id.
  /// A program with none is absent from the map.
  ///
  /// One grouped read rather than a list per program: the library asks this of
  /// every card it renders, to know whether a blocked program has anything to
  /// begin, and N queries to answer one question about N rows is the shape of
  /// read that gets slower the more the user owns.
  Future<Map<String, int>> fetchActiveBlockCounts(String userId) async {
    final rows = await ps.db.getAll('''
      SELECT b.program_id AS program_id, COUNT(*) AS n
      FROM dim_program_block b
      JOIN dim_program p ON p.program_id = b.program_id
      WHERE p.user_id = ? AND b.date_archived IS NULL
      GROUP BY b.program_id
      ''', [userId]);
    return {
      for (final r in rows) r['program_id'] as String: (r['n'] as num).toInt(),
    };
  }

  /// Bumps `program_updated_date` — the single entry point for marking a
  /// program structurally changed.
  ///
  /// Call this from STRUCTURAL mutations only, never from per-set cell commits
  /// (`quickUpdatePlannedSessionExerciseSet`), which fire on every keystroke
  /// and would be write amplification against a dim row.
  ///
  /// Wired where the program id is already in hand: workout import (here) and
  /// block CRUD (Phase 4). The template- and link-level mutations in
  /// [PlannedSessionRepository] are NOT wired, and that is a real gap rather
  /// than an oversight: a `dim_planned_session` row does not know which
  /// program it belongs to — it may be standalone, or linked into zero, one or
  /// several programs — so bumping on a template edit would cost a lookup per
  /// affected program, and on a shared template it is ambiguous which program
  /// "changed". Wire those when something renders or sorts by `updatedDate`.
  Future<void> touchProgram(String programId) async {
    await ps.safeExec(
      'UPDATE dim_program SET program_updated_date = ? WHERE program_id = ?',
      [DateTime.now().toUtc().toIso8601String(), programId],
    );
  }

  /// Soft-deletes a program (is_archived = 1). Its planned sessions are
  /// unlinked (join rows hard-deleted) and become standalone — they stay
  /// usable as templates. Runs are historical facts and remain.
  Future<void> deleteProgram(String programId) async {
    await ps.db.writeTransaction((tx) async {
      // Unlink planned sessions so they become standalone templates.
      await tx.execute(
        'DELETE FROM dim_planned_session_program WHERE program_id = ?',
        [programId],
      );
      // Blocks go with the program. They are NOT deleted — the revision and
      // run history references them, and an archived program's phases must
      // stay browsable.
      await tx.execute(
        'UPDATE dim_program_block SET date_archived = ?, updated_date = ? '
        'WHERE program_id = ? AND date_archived IS NULL',
        [
          DateTime.now().toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
          programId,
        ],
      );
      // Archive the program.
      await tx.execute(
        'UPDATE dim_program SET date_archived = ? WHERE program_id = ?',
        [DateTime.now().toUtc().toIso8601String(), programId],
      );
    });
  }

  /// How many logged sessions hang off this program's runs — what a
  /// [hardDeleteProgram] would cost. Those sessions are NOT deleted (the FK
  /// is ON DELETE SET NULL); they lose their link to the run and nothing else.
  Future<int> programSessionCount(String programId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT COUNT(*) c FROM fact_session
      WHERE program_run_id IN (
        SELECT program_run_id FROM fact_program_run WHERE program_id = ?
      )
      ''',
      [programId],
    );
    if (rows.isEmpty) return 0;
    final v = rows.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  /// Hard-deletes a program and everything under it — blocks, goals, reviews,
  /// runs. There is no soft option left, unlike [deleteProgram].
  ///
  /// Logged sessions survive: `fact_session.program_run_id` is ON DELETE SET
  /// NULL, so they stay in Training Logs and simply lose the run they belonged
  /// to. Callers should show [programSessionCount] before confirming.
  ///
  /// **The statement order is load-bearing**, because Postgres refuses several
  /// of these in the wrong sequence: `fact_program_review.program_run_id` is
  /// NO ACTION rather than CASCADE, so runs cannot go until reviews do, and
  /// `fact_program_run.block_id` pins runs to blocks, so blocks cannot go until
  /// runs do. PowerSync drains its CRUD queue in order, so what the server sees
  /// is what is written here.
  Future<void> hardDeleteProgram(String programId) async {
    await ps.db.writeTransaction((tx) async {
      // Leaves — nothing references these, so they can go first.
      await tx.execute(
        'DELETE FROM fact_program_review WHERE program_id = ?',
        [programId],
      );
      // Goals FK block_id AND program_run_id — they block both of the next two.
      // Matching on block as well as program is belt-and-braces. The server
      // cannot hold the gap: fact_goal_block_scope_check requires program_id
      // whenever block_id is set. But this statement runs against the LOCAL
      // SQLite, which declares no constraints at all, and createGoal writes the
      // two scope columns independently — so a row only this DB can hold is
      // still a row that would strand the block delete below.
      await tx.execute(
        '''
        DELETE FROM fact_goal
        WHERE program_id = ?
           OR block_id IN (SELECT block_id FROM dim_program_block
                           WHERE program_id = ?)
        ''',
        [programId, programId],
      );
      // Also clears every block_id reference into this program's blocks.
      await tx.execute(
        'DELETE FROM dim_planned_session_program WHERE program_id = ?',
        [programId],
      );
      // Mirror the server's ON DELETE SET NULL by hand. Locally there is no FK
      // to fire it, so without this the sessions keep pointing at a run that
      // no longer exists until a sync round-trip — which may never come if the
      // device is offline, and Training Logs reads the local rows.
      await tx.execute(
        '''
        UPDATE fact_session SET program_run_id = NULL
        WHERE program_run_id IN (SELECT program_run_id FROM fact_program_run
                                 WHERE program_id = ?)
        ''',
        [programId],
      );
      await tx.execute(
        'DELETE FROM fact_program_run WHERE program_id = ?',
        [programId],
      );
      await tx.execute(
        'DELETE FROM dim_program_block WHERE program_id = ?',
        [programId],
      );
      await tx.execute(
        'DELETE FROM dim_program WHERE program_id = ?',
        [programId],
      );
    });
  }

  // ── Planned sessions (delegating to PlannedSessionRepository) ─────────────

  Future<List<PlannedSession>> fetchPlannedSessions(String programId) async {
    // user_id isn't known here (callers pass only the program id) — look the
    // program up locally first for its owner.
    final program = await fetchProgram(programId);
    if (program == null) return [];
    return _plannedRepo.fetchPlannedSessions(program.userId,
        programId: programId);
  }

  Future<List<PlannedSessionExerciseSet>> fetchPlannedSessionExerciseSets(
      String sessionId) async {
    return _plannedRepo.fetchPlannedSets(sessionId);
  }

  /// Deep-copies one standalone planned session (workout-library flow).
  Future<String> duplicatePlannedSession(
      String userId, PlannedSession source) async {
    return _plannedRepo.duplicatePlannedSession(userId, source);
  }

  // ── Copy-on-add ──────────────────────────────────────────────────────────

  /// Imports a library workout into a program, as a private copy.
  ///
  /// The library is a SOURCE, not a shared dependency: the copy is independent
  /// forever and editing it never touches the original, which stays listed in
  /// the Workouts library exactly as it was. [`base_session_id`] records where
  /// it came from so the program can push improvements back on request —
  /// copies never track the base, so nothing warns when the two drift.
  ///
  /// Returns the new program-local session id.
  Future<String> importWorkoutIntoProgram(
    String userId, {
    required String programId,
    required String sourceSessionId,
    int? sequenceOrder,
    String? blockId,
  }) async {
    final source = await _plannedRepo.fetchPlannedSessionById(sourceSessionId);
    if (source == null) {
      throw StateError('Workout not found: $sourceSessionId');
    }
    final newId = await _plannedRepo.copySessionIntoProgram(
      userId,
      source: source,
      programId: programId,
      sequenceOrder: sequenceOrder,
      blockId: blockId,
    );
    await touchProgram(programId);
    return newId;
  }

  /// Pushes a program workout's contents back to the library original.
  ///
  /// A program workout with no original — one authored inside a program — gets
  /// a NEW library workout instead, and is then linked to it, so a second push
  /// updates that one rather than minting another duplicate.
  ///
  /// This is the only path that writes to a library workout from a program.
  /// It is explicit and button-driven by design: imports are one-way until the
  /// user says otherwise.
  Future<void> pushWorkoutToLibrary(String userId, String sessionId) async {
    final session = await _plannedRepo.fetchPlannedSessionById(sessionId);
    if (session == null) throw StateError('Workout not found: $sessionId');

    final linked = await ps.db.getAll(
      'SELECT planned_session_program_id FROM dim_planned_session_program '
      'WHERE planned_session_id = ? LIMIT 1',
      [sessionId],
    );
    if (linked.isEmpty) {
      throw StateError('Not a program workout: $sessionId');
    }

    final baseId = session.baseSessionId;
    // An archived or missing original is the same problem: nowhere to push to.
    final base = baseId == null
        ? null
        : await _plannedRepo.fetchPlannedSessionById(baseId);

    if (base == null) {
      await _plannedRepo.createLibraryFrom(
        userId,
        session,
        linkedCopyId: sessionId,
      );
      return;
    }

    await _plannedRepo.replaceContentsFrom(
      userId,
      targetSessionId: base.sessionId,
      source: session,
    );
  }

  // ── Composite reads / duplication ────────────────────────────────────────

  Future<ProgramWithSessions?> fetchProgramWithSessions(String programId) async {
    final program = await fetchProgram(programId);
    if (program == null) return null;
    final sessions = await fetchPlannedSessions(programId);
    return ProgramWithSessions(program: program, plannedSessions: sessions);
  }

  /// Deep-copies a program (and its planned sessions/sets/links) with fresh
  /// UUIDs. The copy is a brand-new program with no run history of its own.
  /// All inserts happen in a single local transaction so the copy either
  /// lands completely or not at all.
  Future<String> duplicateProgram(String userId, String programId) async {
    final source = await fetchProgramWithSessions(programId);
    if (source == null) throw StateError('Program not found: $programId');

    // Read every source session's exercises/sets and links up front —
    // querying ps.db from inside a writeTransaction callback below could
    // contend with the write lock that transaction holds.
    final linksBySessionId = <String, PlannedSessionProgram>{};
    for (final link in await _plannedRepo.fetchProgramLinks(programId)) {
      linksBySessionId[link.plannedSessionId] = link;
    }
    // Active blocks only. An archived phase is not part of the program any
    // more, so it is not part of the copy either — and its workouts come
    // across unassigned rather than pointing at a block that was never copied.
    final sourceBlocks = await fetchBlocks(programId);
    final exercisesBySessionId =
        <String, List<PlannedSessionExercise>>{};
    final setsBySessionId =
        <String, List<PlannedSessionExerciseSet>>{};
    for (final session in source.plannedSessions) {
      exercisesBySessionId[session.sessionId] =
          await _plannedRepo.fetchPlannedExercises(session.sessionId);
      setsBySessionId[session.sessionId] =
          await _plannedRepo.fetchPlannedSets(session.sessionId);
    }

    final programNames = await _programNames(userId);
    final name = uniqueName('${source.program.name} (Copy)', programNames,
        numbered: (n) => '${source.program.name} (Copy $n)');

    final newProgramId = _uuid.v4();

    await ps.db.writeTransaction((tx) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.execute(
        '''
        INSERT INTO dim_program
          (id, program_id, user_id, program_name, program_description,
           date_archived, program_created_date, program_updated_date,
           uses_blocks, default_target_sessions)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newProgramId,
          newProgramId,
          userId,
          name,
          source.program.description,
          null,
          now,
          now,
          // The copy has the source's shape and remembered length. Copied
          // from the columns, not recomputed from whether blocks came across:
          // a blocked program whose blocks were all archived still has zero
          // blocks to copy, and the copy is still a blocked program.
          source.program.usesBlocks ? 1 : 0,
          source.program.defaultTargetSessions,
        ],
      );

      // Blocks first, so the copied links below can point at the copies. The
      // old→new map is what makes a workout land in the block it belongs to
      // rather than in the copy's unassigned group.
      final newBlockIds = <String, String>{};
      for (final block in sourceBlocks) {
        final newBlockId = _uuid.v4();
        newBlockIds[block.blockId] = newBlockId;
        await tx.execute(
          '''
          INSERT INTO dim_program_block
            (id, block_id, user_id, program_id, name, notes, block_order,
             target_weeks, target_days, target_sessions, start_date, end_date,
             date_archived, created_date, updated_date)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newBlockId,
            newBlockId,
            userId,
            newProgramId,
            block.name,
            block.notes,
            block.blockOrder,
            block.targetWeeks,
            block.targetDays,
            block.targetSessions,
            block.startDate?.toIso8601String(),
            block.endDate?.toIso8601String(),
            null,
            now,
            now,
          ],
        );
      }

      for (final session in source.plannedSessions) {
        final newSessionId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session
            (id, session_id, user_id, name, notes, date_archived, created_date,
             base_session_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSessionId,
            newSessionId,
            userId,
            session.name,
            session.notes,
            null,
            now,
            // Lineage is inherited, never invented: a copy of a copy is still
            // a copy of the same library workout, so the new program points
            // home too. Pointing at the source session instead would make the
            // OTHER program the original, and pushing back would overwrite a
            // workout in a program the user wasn't even looking at.
            session.baseSessionId,
          ],
        );

        for (final exercise in exercisesBySessionId[session.sessionId] ?? const <PlannedSessionExercise>[]) {
          final newExerciseId = _uuid.v4();
          await tx.execute(
            '''
            INSERT INTO dim_planned_session_exercise
              (id, planned_exercise_id, planned_session_id, user_id,
               custom_exercise_id, exercise_order, is_archived)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              newExerciseId,
              newExerciseId,
              newSessionId,
              userId,
              exercise.exerciseId,
              exercise.exerciseOrder,
              0,
            ],
          );

          final exerciseSets = (setsBySessionId[session.sessionId] ?? const <PlannedSessionExerciseSet>[])
              .where((s) => s.plannedExerciseId == exercise.plannedExerciseId)
              .toList();
          for (final set in exerciseSets) {
            final newSetId = _uuid.v4();
            await tx.execute(
              '''
              INSERT INTO dim_planned_session_exercise_set
                (id, planned_set_id, planned_exercise_id, user_id,
                 custom_variation_id, set_number, target_weight, target_reps,
                 target_notes, is_archived)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              [
                newSetId,
                newSetId,
                newExerciseId,
                userId,
                set.variationId,
                set.setNumber,
                set.targetWeight,
                set.targetReps,
                set.targetNotes,
                0,
              ],
            );
          }
        }

        final link = linksBySessionId[session.sessionId];
        if (link != null) {
          final newLinkId = _uuid.v4();
          await tx.execute(
            '''
            INSERT INTO dim_planned_session_program
              (id, planned_session_program_id, program_id, planned_session_id,
               user_id, sequence_order, day_of_week, week_offset, block_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              newLinkId,
              newLinkId,
              newProgramId,
              newSessionId,
              userId,
              link.sequenceOrder,
              link.dayOfWeek,
              link.weekOffset,
              // Remapped through the block copies; null when the source link
              // was unassigned OR pointed at an archived block, which the copy
              // deliberately does not carry.
              link.blockId == null ? null : newBlockIds[link.blockId],
            ],
          );
        }
      }
    });

    return newProgramId;
  }

  // ── Blocks ───────────────────────────────────────────────────────────────

  /// A program's active blocks, in `block_order`.
  Future<List<ProgramBlock>> fetchBlocks(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program_block '
      'WHERE program_id = ? AND date_archived IS NULL ORDER BY block_order',
      [programId],
    );
    return rows.map((r) => ProgramBlock.fromMap(r)).toList();
  }

  Future<ProgramBlock?> fetchBlock(String blockId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program_block WHERE block_id = ?',
      [blockId],
    );
    if (rows.isEmpty) return null;
    return ProgramBlock.fromMap(rows.first);
  }

  /// Creates a block, appended to the program's order.
  ///
  /// REST-FIRST, like [createProgram], and for the same reason: the server
  /// enforces `(program_id, block_id)` as a composite FK on the join rows and
  /// a single-column FK from `fact_program_run`. A block that only exists
  /// locally would make the first "assign a workout" or "start this block"
  /// upload fail on a server that has never seen the block. The cost is that a
  /// fully offline user cannot create a block — accepted deliberately, because
  /// the alternative failure mode (a run pointing at a block id that never
  /// uploaded) is a quarantined row nobody can explain.
  Future<ProgramBlock> createProgramBlock(
    String userId, {
    required String programId,
    String? name,
    String? notes,
    int? targetWeeks,
    int? targetDays,
    int? targetSessions,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var finalName = name;
    if (finalName == null || finalName.trim().isEmpty) {
      final existing = await fetchBlocks(programId);
      final names = existing.map((b) => b.name).toSet();
      finalName = uniqueName('Block ${existing.length + 1}', names);
    }

    // Append: read the current maximum rather than trusting a list the caller
    // happens to hold, so two offline creations cannot both claim one order.
    final orderRows = await ps.db.getAll(
      'SELECT MAX(block_order) AS max_order FROM dim_program_block WHERE program_id = ?',
      [programId],
    );
    final order =
        (_toInt(orderRows.isEmpty ? null : orderRows.first['max_order']) ?? 0) +
            1;

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    // The same exclusivity rule `updateBlock` enforces, for the same reason —
    // see the note there. A new block should never be the thing that trips
    // `dim_program_block_length_check`.
    if (targetSessions != null) {
      targetWeeks = null;
      targetDays = null;
      endDate = null;
    }

    await _remote.insertBlock({
      'block_id': id,
      'user_id': userId,
      'program_id': programId,
      'name': finalName,
      'notes': notes,
      'block_order': order,
      'target_weeks': targetWeeks,
      'target_days': targetDays,
      'target_sessions': targetSessions,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'date_archived': null,
      'created_date': now.toIso8601String(),
      'updated_date': now.toIso8601String(),
    });

    // Mirror it locally, under the same id the server now holds.
    //
    // Without this the block is invisible until the next download lands, and
    // the block editor makes that window visible: saving pops back to the
    // program, which reloads and reads `fetchBlocks` from the LOCAL table — so
    // a freshly created block is missing from the list it was just created in.
    // (The reload also overwrites the view model's optimistic append, so the
    // append cannot cover for the missing row.)
    //
    // This is the same fix, for the same reason, as `startProgramRun`'s mirror:
    // the uploader upserts (`database.dart` → `uploadData`), so the PUT this
    // queues is a no-op against the row that is already there, and the server's
    // copy downloads onto the same row rather than beside it. The old note here
    // warned that a local write blocks the checkpoint; `duplicateBlock` in this
    // same file has always written its block locally through this path, and the
    // Stage 1 device smoke showed `ps_crud` draining cleanly with mirrors in
    // place — the "different id" collision was what the warning was really
    // describing.
    //
    // Best-effort: the block exists server-side either way, so a mirror failure
    // logs and moves on rather than failing a create that succeeded.
    try {
      await ps.safeWriteTransaction((tx) async {
        await tx.execute(
          '''
          INSERT INTO dim_program_block
            (id, block_id, user_id, program_id, name, notes, block_order,
             target_weeks, target_days, target_sessions, start_date, end_date,
             date_archived, created_date, updated_date)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            id,
            id,
            userId,
            programId,
            finalName,
            notes,
            order,
            targetWeeks,
            targetDays,
            targetSessions,
            startDate?.toIso8601String(),
            endDate?.toIso8601String(),
            null,
            now.toIso8601String(),
            now.toIso8601String(),
          ],
        );
      });
    } catch (e) {
      debugPrint('createProgramBlock: local mirror failed: $e');
    }

    await touchProgram(programId);

    return ProgramBlock(
      blockId: id,
      userId: userId,
      programId: programId,
      name: finalName,
      notes: notes,
      blockOrder: order,
      targetWeeks: targetWeeks,
      targetDays: targetDays,
      targetSessions: targetSessions,
      startDate: startDate,
      endDate: endDate,
      createdDate: now,
      updatedDate: now,
    );
  }

  /// Updates a block.
  ///
  /// The clear flags exist because "set this to null" and "leave this alone"
  /// cannot both be spelled with a nullable parameter — the same reason
  /// `updateProgramLink` carries its own.
  ///
  /// Writing a length also settles the exclusivity rule here rather than
  /// trusting the caller. A block is measured in weeks **or** in sessions, and
  /// sessions mode has no calendar end (the block ends when the sessions are
  /// done). Both are CHECK constraints on `dim_program_block`
  /// (`dim_program_block_length_check`, `dim_program_block_sessions_no_end_check`),
  /// so normalising at the one place these columns are written is what keeps
  /// them unreachable from the app instead of a source of quarantined uploads.
  /// Sessions wins when both arrive, matching `blockLengthModeOf`.
  ///
  /// `targetWeeks` and `targetDays` are two halves of one number — a calendar
  /// length is whole weeks plus a remainder — so they are meant to be sent
  /// together. The remainder's own constraints (`0..6`, and weeks-without-days)
  /// are settled here for the same reason as the exclusivity rule.
  ///
  /// Lengths are applied *after* dates for that reason — a length is the last
  /// word on whether an end date is allowed to exist.
  Future<void> updateBlock(
    String blockId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    int? targetWeeks,
    int? targetDays,
    bool clearTargetDays = false,
    bool clearWeeks = false,
    int? targetSessions,
    bool clearSessions = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (clearNotes) {
      updates['notes'] = null;
    } else if (notes != null) {
      updates['notes'] = notes;
    }
    if (startDate != null) updates['start_date'] = startDate.toIso8601String();
    if (endDate != null) updates['end_date'] = endDate.toIso8601String();
    if (clearStartDate) updates['start_date'] = null;
    if (clearEndDate) updates['end_date'] = null;

    if (targetWeeks != null) {
      updates['target_weeks'] = targetWeeks;
      updates['target_sessions'] = null;
    }
    if (targetSessions != null) {
      updates['target_sessions'] = targetSessions;
      updates['target_weeks'] = null;
      updates['target_days'] = null;
      updates['end_date'] = null;
    }
    if (targetDays != null) updates['target_days'] = targetDays;
    if (clearTargetDays) updates['target_days'] = null;
    if (clearWeeks) {
      updates['target_weeks'] = null;
      // A remainder with no weeks to remain from is a value nothing can read
      // (`dim_program_block_days_need_weeks_check`) — clearing the weeks takes
      // the days with it, whether or not the caller remembered to say so. That
      // is why this clear runs last: the days pair cannot be written past it.
      updates['target_days'] = null;
    }
    if (clearSessions) updates['target_sessions'] = null;

    if (updates.isEmpty) return;
    updates['updated_date'] = DateTime.now().toUtc().toIso8601String();
    final (setClause, params) = _buildSetClause(updates);
    await ps.safeExec(
      'UPDATE dim_program_block SET $setClause WHERE block_id = ?',
      [...params, blockId],
    );
    final block = await fetchBlock(blockId);
    if (block != null) await touchProgram(block.programId);
  }

  /// Rewrites `block_order` to match [blockIdsInOrder] (1-based).
  ///
  /// Only blocks in the list are touched. `block_order` is scoped to the block
  /// table alone, so reordering blocks never renumbers a workout —
  /// `sequence_order` on the join rows stays program-global and untouched.
  Future<void> reorderBlocks(
    String programId,
    List<String> blockIdsInOrder,
  ) async {
    if (blockIdsInOrder.isEmpty) return;
    await ps.safeWriteTransaction((tx) async {
      for (var i = 0; i < blockIdsInOrder.length; i++) {
        await tx.execute(
          'UPDATE dim_program_block SET block_order = ?, updated_date = ? '
          'WHERE block_id = ? AND program_id = ?',
          [
            i + 1,
            DateTime.now().toUtc().toIso8601String(),
            blockIdsInOrder[i],
            programId,
          ],
        );
      }
    });
    await touchProgram(programId);
  }

  /// Soft-deletes a block. Its workouts are NOT deleted — they return to the
  /// program's unassigned group, because a block is a grouping, not a
  /// container: removing the phase must not remove the training.
  Future<void> archiveBlock(String blockId) async {
    final block = await fetchBlock(blockId);
    if (block == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        'UPDATE dim_planned_session_program SET block_id = NULL WHERE block_id = ?',
        [blockId],
      );
      await tx.execute(
        'UPDATE dim_program_block SET date_archived = ?, updated_date = ? WHERE block_id = ?',
        [now, now, blockId],
      );
    });
    await touchProgram(block.programId);
  }

  /// Restores an archived block. Its workouts are NOT restored with it — the
  /// membership was cleared on archive and cannot be reconstructed.
  Future<void> reactivateBlock(String blockId) async {
    final block = await fetchBlock(blockId);
    if (block == null) return;
    await ps.safeExec(
      'UPDATE dim_program_block SET date_archived = NULL, updated_date = ? WHERE block_id = ?',
      [DateTime.now().toUtc().toIso8601String(), blockId],
    );
    await touchProgram(block.programId);
  }

  Future<List<ProgramBlock>> fetchArchivedBlocks(String programId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_program_block WHERE program_id = ? '
      'AND date_archived IS NOT NULL ORDER BY date_archived DESC',
      [programId],
    );
    return rows.map((r) => ProgramBlock.fromMap(r)).toList();
  }

  /// Deep-copies a block AND its workouts.
  ///
  /// The workouts are fresh copies, not links to the originals: a duplicated
  /// block is a new phase, and editing one must never change the other. Each
  /// copy inherits its source's `base_session_id`, so lineage still points at
  /// the library original rather than at the block's first copy.
  ///
  /// Returns the new block id.
  Future<String> duplicateBlock(
    String userId,
    String blockId, {
    String? name,
  }) async {
    final source = await fetchBlock(blockId);
    if (source == null) throw StateError('Block not found: $blockId');

    final links = await _plannedRepo.fetchProgramLinks(
      source.programId,
      blockId: blockId,
    );
    // Read every workout up front: querying ps.db inside the transaction below
    // would contend with the write lock it holds.
    final sessions = <String, PlannedSession>{};
    final exercisesBySessionId = <String, List<PlannedSessionExercise>>{};
    final setsBySessionId = <String, List<PlannedSessionExerciseSet>>{};
    for (final link in links) {
      final session =
          await _plannedRepo.fetchPlannedSessionById(link.plannedSessionId);
      if (session == null) continue;
      sessions[link.plannedSessionId] = session;
      exercisesBySessionId[session.sessionId] =
          await _plannedRepo.fetchPlannedExercises(session.sessionId);
      setsBySessionId[session.sessionId] =
          await _plannedRepo.fetchPlannedSets(session.sessionId);
    }

    final existing = await fetchBlocks(source.programId);
    final finalName = name ??
        uniqueName(
          '${source.name} (Copy)',
          existing.map((b) => b.name).toSet(),
          numbered: (n) => '${source.name} (Copy $n)',
        );

    final orderRows = await ps.db.getAll(
      'SELECT MAX(block_order) AS max_order FROM dim_program_block WHERE program_id = ?',
      [source.programId],
    );
    final newOrder =
        (_toInt(orderRows.isEmpty ? null : orderRows.first['max_order']) ?? 0) +
            1;

    final newBlockId = _uuid.v4();
    final now = DateTime.now().toUtc();

    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_program_block
          (id, block_id, user_id, program_id, name, notes, block_order,
           target_weeks, target_days, target_sessions, start_date, end_date,
           date_archived, created_date, updated_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newBlockId,
          newBlockId,
          userId,
          source.programId,
          finalName,
          source.notes,
          newOrder,
          source.targetWeeks,
          source.targetDays,
          source.targetSessions,
          source.startDate?.toIso8601String(),
          source.endDate?.toIso8601String(),
          null,
          now.toIso8601String(),
          now.toIso8601String(),
        ],
      );

      // The workouts, as copies. `_insertCopy` writes the session row and its
      // children; the link is inserted here so it lands in the same
      // transaction — a copied block holding no workouts would be a partial
      // success nobody asked for.
      for (final link in links) {
        final session = sessions[link.plannedSessionId];
        if (session == null) continue;
        final newSessionId = await _plannedRepo.insertCopyIn(
          tx,
          userId,
          source: session,
          exercises:
              exercisesBySessionId[session.sessionId] ?? const [],
          sets: setsBySessionId[session.sessionId] ?? const [],
          baseSessionId: session.baseSessionId,
        );
        final newLinkId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session_program
            (id, planned_session_program_id, program_id, planned_session_id,
             user_id, sequence_order, day_of_week, week_offset, block_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newLinkId,
            newLinkId,
            source.programId,
            newSessionId,
            userId,
            link.sequenceOrder,
            link.dayOfWeek,
            link.weekOffset,
            newBlockId,
          ],
        );
      }
    });

    await touchProgram(source.programId);
    return newBlockId;
  }

  // ── Goals ────────────────────────────────────────────────────────────────

  /// Goals, narrowed by whichever scope is given.
  ///
  /// - `programId` — that program's goals, **both levels**. Filtering to one
  ///   block in Dart is the caller's job (`g.appliesDuring(run.blockId)`),
  ///   because the usual question is "what is in force right now", and that is
  ///   the program's goals PLUS the running block's — a union, not a filter.
  /// - `blockId` — only when paired with `programId`: that block's own goals.
  /// - `programRunId` — the run link, for goals created before scoping.
  ///
  /// With no scope at all: standalone goals. The clauses are explicit rather
  /// than implied by "no filter given", so a goal can never be returned by a
  /// query that did not name its scope.
  Future<List<Goal>> fetchGoals(
    String userId, {
    String? programId,
    String? blockId,
    String? programRunId,
  }) async {
    final where = <String>['user_id = ?'];
    final args = <Object?>[userId];

    if (programId != null) {
      where.add('program_id = ?');
      args.add(programId);
      if (blockId != null) {
        where.add('block_id = ?');
        args.add(blockId);
      }
    } else if (programRunId != null) {
      where.add('program_run_id = ?');
      args.add(programRunId);
    } else {
      where.add('program_id IS NULL AND program_run_id IS NULL');
    }

    final rows = await ps.db.getAll(
      'SELECT * FROM fact_goal WHERE ${where.join(' AND ')} '
      'ORDER BY goal_created_date',
      args,
    );
    return rows.map((r) => Goal.fromMap(r)).toList();
  }

  /// Writes a goal. The goal carries its own scope — program, block, variation
  /// and run link are all on [Goal], so there is no second place for a caller
  /// to pass one that disagrees with the row.
  Future<void> createGoal(String userId, Goal goal) async {
    await ps.db.execute(
      '''
      INSERT INTO fact_goal
        (id, goal_id, user_id, program_id, block_id, program_run_id, goal_text,
         custom_exercise_id, custom_variation_id, target_weight, target_reps,
         goal_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        goal.goalId,
        goal.goalId,
        userId,
        goal.programId,
        goal.blockId,
        goal.programRunId,
        goal.text,
        goal.exerciseId,
        goal.variationId,
        goal.targetWeight,
        goal.targetReps,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> deleteGoal(String goalId) async {
    await ps.db.execute(
      'DELETE FROM fact_goal WHERE goal_id = ?',
      [goalId],
    );
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}
