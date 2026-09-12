import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session.dart';
import '../models/planned_session_program.dart';
import '../models/program.dart';
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

/// Program library CRUD — programs (dimensions), their planned sessions, and
/// goals. Programs are soft-deleted via is_archived so run history never
/// dangles. Planned-session reads/writes delegate to [PlannedSessionRepository].
class ProgramRepository {
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

  /// Throws if another program owned by `userId` already has [name].
  Future<void> _assertProgramNameUnique(
      String userId, String name, {String? excludeProgramId}) async {
    if (await _programNameExists(userId, name,
        excludeProgramId: excludeProgramId)) {
      throw Exception('A program named "$name" already exists.');
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
      final remote = await Supabase.instance.client
          .from('dim_program')
          .select('*')
          .eq('user_id', userId)
          .isFilter('date_archived', null)
          .order('program_created_date', ascending: false)
          .timeout(const Duration(seconds: 5));
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
      final remote = await Supabase.instance.client
          .from('dim_program')
          .select('*')
          .eq('program_id', programId)
          .limit(1)
          .timeout(const Duration(seconds: 5));
      if (remote.isNotEmpty) return Program.fromMap(remote.first);
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
    await Supabase.instance.client.from('dim_program').insert({
      'program_id': id,
      'user_id': userId,
      'program_name': finalName,
      'program_description': description,
      'date_archived': null,
      'program_created_date': createdDate.toIso8601String(),
      'program_updated_date': createdDate.toIso8601String(),
    }).timeout(const Duration(seconds: 8));

    // No local PowerSync mirror — writing locally creates a CRUD entry that
    // blocks the checkpoint (PowerSync will download the row on next sync).

    return Program(
      programId: id,
      userId: userId,
      name: finalName,
      description: description,
      createdDate: createdDate,
      updatedDate: createdDate,
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
      // Archive the program.
      await tx.execute(
        'UPDATE dim_program SET date_archived = ? WHERE program_id = ?',
        [DateTime.now().toUtc().toIso8601String(), programId],
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
           date_archived, program_created_date, program_updated_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
        ],
      );

      for (final session in source.plannedSessions) {
        final newSessionId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session
            (id, session_id, user_id, name, notes, is_archived, created_date)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSessionId,
            newSessionId,
            userId,
            session.name,
            session.notes,
            0,
            now,
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
               user_id, sequence_order, day_of_week, week_offset)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
            ],
          );
        }
      }
    });

    return newProgramId;
  }

  // ── Goals ────────────────────────────────────────────────────────────────

  Future<List<Goal>> fetchGoals(String userId, {String? programRunId}) async {
    final rows = await ps.db.getAll(
      programRunId != null
          ? 'SELECT * FROM fact_goal WHERE user_id = ? AND program_run_id = ? ORDER BY goal_created_date'
          : 'SELECT * FROM fact_goal WHERE user_id = ? AND program_run_id IS NULL ORDER BY goal_created_date',
      programRunId != null ? [userId, programRunId] : [userId],
    );
    return rows.map((r) => Goal.fromMap(r)).toList();
  }

  Future<void> createGoal(String userId, String runId, Goal goal) async {
    await ps.db.execute(
      '''
      INSERT INTO fact_goal
        (id, goal_id, program_run_id, user_id, goal_text, custom_exercise_id,
         target_weight, target_reps, goal_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        goal.goalId,
        goal.goalId,
        runId,
        userId,
        goal.text,
        goal.exerciseId,
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
