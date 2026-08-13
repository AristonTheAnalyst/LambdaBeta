import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/planned_session_set.dart';
import '../models/planned_session.dart';
import '../models/program.dart';
import '../models/goal.dart';
import '../../shared/utils/unique_name.dart';

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
/// dangles.
class ProgramRepository {
  // ── Programs ─────────────────────────────────────────────────────────────

  /// Program names for [userId], used to bump auto-generated defaults.
  Future<Set<String>> _programNames(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT program_name FROM dim_program WHERE user_id = ? AND is_archived = 0',
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
      WHERE user_id = ? AND is_archived = 0 AND LOWER(program_name) = LOWER(?)
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
        'SELECT * FROM dim_program WHERE user_id = ? AND is_archived = 0 ORDER BY program_created_date DESC',
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
          .eq('is_archived', false)
          .order('program_created_date', ascending: false)
          .timeout(const Duration(seconds: 5));
      return remote.map((r) => Program.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
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
    int? lengthWeeks,
    String progressionMode = 'sequential',
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
      'program_length_weeks': lengthWeeks,
      'progression_mode': progressionMode,
      'is_archived': false,
      'program_created_date': createdDate.toIso8601String(),
    }).timeout(const Duration(seconds: 8));

    // No local PowerSync mirror — writing locally creates a CRUD entry that
    // blocks the checkpoint (PowerSync will download the row on next sync).

    return Program(
      programId: id,
      userId: userId,
      name: finalName,
      description: description,
      lengthWeeks: lengthWeeks,
      progressionMode: progressionMode,
      isArchived: false,
      createdDate: createdDate,
    );
  }

  Future<void> updateProgram(
    String programId, {
    String? name,
    String? description,
    int? lengthWeeks,
    String? progressionMode,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertProgramNameUnique(userId, name, excludeProgramId: programId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['program_name'] = name;
    if (description != null) updates['program_description'] = description;
    if (lengthWeeks != null) updates['program_length_weeks'] = lengthWeeks;
    if (progressionMode != null) updates['progression_mode'] = progressionMode;
    if (updates.isEmpty) return;
    final (setClause, params) = _buildSetClause(updates);
    await ps.safeExec(
      'UPDATE dim_program SET $setClause WHERE program_id = ?',
      [...params, programId],
    );
  }

  /// Soft-deletes a program (is_archived = 1). Planned sessions attached to
  /// the program are unlinked (program_id = NULL) and become standalone —
  /// they stay usable as templates. Runs are historical facts and remain.
  Future<void> deleteProgram(String programId) async {
    await ps.db.writeTransaction((tx) async {
      // Unlink planned sessions so they become standalone templates.
      await tx.execute(
        'UPDATE dim_planned_session SET program_id = NULL, sequence_order = NULL, day_of_week = NULL WHERE program_id = ?',
        [programId],
      );
      // Archive the program.
      await tx.execute(
        'UPDATE dim_program SET is_archived = 1 WHERE program_id = ?',
        [programId],
      );
    });
  }

  // ── Planned sessions (delegating reads to the unified table) ─────────────

  Future<List<PlannedSession>> fetchPlannedSessions(String programId) async {
    try {
      final rows = await ps.db.getAll(
        '''
        SELECT * FROM dim_planned_session
        WHERE program_id = ? AND is_archived = 0
        ORDER BY sequence_order
        ''',
        [programId],
      ).timeout(const Duration(seconds: 3));
      if (rows.isNotEmpty) return rows.map((r) => PlannedSession.fromMap(r)).toList();
    } catch (_) {}
    return [];
  }

  Future<List<PlannedSessionSet>> fetchPlannedSessionSets(
      String sessionId) async {
    try {
      final rows = await ps.db.getAll(
        '''
        SELECT s.*,
               COALESCE(s.exercise_name, e.exercise_name) AS exercise_name,
               COALESCE(s.variation_name, v.variation_name) AS variation_name
        FROM dim_planned_session_set s
        LEFT JOIN dim_exercise e ON e.custom_exercise_id = s.custom_exercise_id
        LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
        WHERE s.session_id = ? AND s.is_archived = 0
        ORDER BY s.exercise_sequence_order, s.set_number
        ''',
        [sessionId],
      ).timeout(const Duration(seconds: 3));
      if (rows.isNotEmpty) return rows.map((r) => PlannedSessionSet.fromMap(r)).toList();
    } catch (_) {}
    return [];
  }

  /// Deep-copies one planned session (and its sets) within the same program.
  /// The copy gets a fresh UUID, "(Copy)" suffix on the name, and is placed
  /// immediately after the source in sequence order.
  Future<String> duplicatePlannedSession(
      String userId, PlannedSession source) async {
    final sets = await fetchPlannedSessionSets(source.sessionId);

    final siblings = await fetchPlannedSessions(source.programId ?? '');
    final siblingNames = siblings.map((w) => w.name).toSet();
    final copyName = uniqueName('${source.name} (Copy)', siblingNames,
        numbered: (n) => '${source.name} (Copy $n)');

    final newId = _uuid.v4();
    final createdDate = DateTime.now().toUtc().toIso8601String();
    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_planned_session
          (id, session_id, program_id, user_id, name,
           notes, sequence_order, day_of_week, is_archived, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newId, newId, source.programId, userId,
          copyName, source.notes,
          (source.sequenceOrder ?? 0) + 1, source.dayOfWeek, 0, createdDate,
        ],
      );

      // Bump later sessions' sequence_order so the copy doesn't clobber.
      await tx.execute(
        '''
        UPDATE dim_planned_session
        SET sequence_order = sequence_order + 1
        WHERE program_id = ? AND sequence_order > ?
        ''',
        [source.programId, source.sequenceOrder ?? 0],
      );

      for (final set in sets) {
        final newSetId = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session_set
            (id, set_id, session_id, user_id, custom_exercise_id,
             custom_variation_id, exercise_sequence_order, set_number,
             target_weight, target_reps, target_notes,
             is_archived, exercise_name, variation_name)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSetId, newSetId, newId, userId,
            set.exerciseId, set.variationId,
            set.exerciseSequenceOrder, set.setNumber,
            set.targetWeight, jsonEncode(set.targetReps),
            set.targetNotes,
            0, set.exerciseName, set.variationName,
          ],
        );
      }
    });

    return newId;
  }

  // ── Composite reads / duplication ────────────────────────────────────────

  Future<ProgramWithSessions?> fetchProgramWithSessions(String programId) async {
    final program = await fetchProgram(programId);
    if (program == null) return null;
    final sessions = await fetchPlannedSessions(programId);
    return ProgramWithSessions(program: program, plannedSessions: sessions);
  }

  /// Deep-copies a program (and its planned sessions/sets) with fresh UUIDs.
  /// The copy is a brand-new program with no run history of its own. All
  /// inserts happen in a single local transaction so the copy either lands
  /// completely or not at all.
  Future<String> duplicateProgram(String userId, String programId) async {
    final source = await fetchProgramWithSessions(programId);
    if (source == null) throw StateError('Program not found: $programId');

    // Read every source session's sets up front — querying ps.db from inside
    // a writeTransaction callback below could contend with the write lock
    // that transaction holds.
    final setsBySessionId = <String, List<PlannedSessionSet>>{};
    for (final session in source.plannedSessions) {
      setsBySessionId[session.sessionId] =
          await fetchPlannedSessionSets(session.sessionId);
    }

    final programNames = await _programNames(userId);
    final name = uniqueName('${source.program.name} (Copy)', programNames,
        numbered: (n) => '${source.program.name} (Copy $n)');

    final newProgramId = _uuid.v4();

    await ps.db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO dim_program
          (id, program_id, user_id, program_name, program_description,
           program_length_weeks, progression_mode, is_archived, program_created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          newProgramId,
          newProgramId,
          userId,
          name,
          source.program.description,
          source.program.lengthWeeks,
          source.program.progressionMode,
          0,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );

      for (final session in source.plannedSessions) {
        final newSessionId = _uuid.v4();
        final createdDate = DateTime.now().toUtc().toIso8601String();
        await tx.execute(
          '''
          INSERT INTO dim_planned_session
            (id, session_id, program_id, user_id, name,
             notes, sequence_order, day_of_week, is_archived, created_date)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            newSessionId,
            newSessionId,
            newProgramId,
            userId,
            session.name,
            session.notes,
            session.sequenceOrder,
            session.dayOfWeek,
            0,
            createdDate,
          ],
        );

        final sets = setsBySessionId[session.sessionId] ?? const [];
        for (final set in sets) {
          final newSetId = _uuid.v4();
          await tx.execute(
            '''
            INSERT INTO dim_planned_session_set
              (id, set_id, session_id, user_id, custom_exercise_id, custom_variation_id,
               exercise_sequence_order, set_number, target_weight, target_reps,
               target_notes, is_archived, exercise_name, variation_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              newSetId,
              newSetId,
              newSessionId,
              userId,
              set.exerciseId,
              set.variationId,
              set.exerciseSequenceOrder,
              set.setNumber,
              set.targetWeight,
              jsonEncode(set.targetReps),
              set.targetNotes,
              0,
              set.exerciseName,
              set.variationName,
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
