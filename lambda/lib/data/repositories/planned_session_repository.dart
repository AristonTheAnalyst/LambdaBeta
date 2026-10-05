import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../core/utils/lambda_exception.dart';
import '../../shared/utils/unique_name.dart';
import '../models/planned_session.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session_program.dart';

const _uuid = Uuid();

/// Owns planned sessions (session templates — standalone or program-attached
/// via the join table) and their exercise groups + planned sets. Dimensions
/// are soft-deleted via is_archived so logged history that references them
/// never dangles; join-table rows hard-delete (nothing references them).
class PlannedSessionRepository {
  /// Planned session names for [userId], used to bump auto-generated defaults.
  Future<Set<String>> _sessionNames(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT name FROM dim_planned_session WHERE user_id = ? AND date_archived IS NULL',
      [userId],
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  Future<bool> _nameExists(
    String userId,
    String name, {
    String? excludeSessionId,
  }) async {
    final rows = await ps.db.getAll(
      '''
      SELECT 1 FROM dim_planned_session
      WHERE user_id = ? AND date_archived IS NULL AND LOWER(name) = LOWER(?)
        ${excludeSessionId != null ? 'AND session_id != ?' : ''}
      LIMIT 1
      ''',
      [userId, name.trim(), ?excludeSessionId],
    );
    return rows.isNotEmpty;
  }

  Future<void> _assertSessionNameUnique(
    String userId,
    String name, {
    String? excludeSessionId,
  }) async {
    if (await _nameExists(userId, name, excludeSessionId: excludeSessionId)) {
      throw LambdaException('A session named "$name" already exists.');
    }
  }

  /// Fetches planned sessions — standalone (no program link) or attached to
  /// [programId] via the join table.
  /// Program workouts (when [programId] is given) or library workouts.
  ///
  /// [blockId] narrows a program listing to one block. A null [blockId] with a
  /// non-null [programId] returns the WHOLE program, blocks included — the
  /// ordered block view groups that list in Dart rather than issuing a query
  /// per block.
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
    String? blockId,
  }) async {
    final rows = await ps.db.getAll(
      programId != null
          ? '''
            SELECT dps.*, psp.sequence_order, psp.day_of_week, psp.week_offset
            FROM dim_planned_session dps
            JOIN dim_planned_session_program psp
              ON psp.planned_session_id = dps.session_id
            WHERE dps.user_id = ? AND psp.program_id = ? AND dps.date_archived IS NULL
              ${blockId != null ? 'AND psp.block_id = ?' : ''}
            ORDER BY psp.sequence_order NULLS LAST, dps.created_date
            '''
          : '''
            SELECT * FROM dim_planned_session dps
            WHERE dps.user_id = ? AND dps.date_archived IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM dim_planned_session_program psp
                WHERE psp.planned_session_id = dps.session_id
              )
            ORDER BY dps.created_date DESC
            ''',
      programId != null ? [userId, programId, ?blockId] : [userId],
    );
    return rows.map((r) => PlannedSession.fromMap(r)).toList();
  }

  /// Creates a planned session. When [name] is null the app auto-generates one
  /// ("New Session", "New Session 2", …) bumped against the local mirror so it
  /// never throws; when a user-typed [name] is given, it must be unique.
  ///
  /// Like all name-uniqueness in this app, the check is client-side against
  /// the device's local PowerSync mirror — names are NOT unique at the
  /// database level, so two offline devices can still independently create
  /// (or rename to) the same string and the server accepts a cosmetic
  /// duplicate after sync. Records are keyed by UUID, never by name.
  Future<PlannedSession> createPlannedSession(
    String userId, {
    String? name,
    String? notes,
  }) async {
    var finalName = name;
    if (finalName == null) {
      final names = await _sessionNames(userId);
      finalName = uniqueName('New Session', names);
    } else {
      await _assertSessionNameUnique(userId, finalName);
    }
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session
        (id, session_id, user_id, name, notes, date_archived, created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        finalName,
        notes,
        null,
        createdDate.toIso8601String(),
      ],
    );
    return PlannedSession(
      sessionId: id,
      userId: userId,
      name: finalName,
      notes: notes,
      createdDate: createdDate,
    );
  }

  Future<void> updatePlannedSession(
    String sessionId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    String userId = '',
  }) async {
    if (name != null) {
      await _assertSessionNameUnique(userId, name, excludeSessionId: sessionId);
    }
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (clearNotes) {
      updates['notes'] = null;
    } else if (notes != null) {
      updates['notes'] = notes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session SET $setClause WHERE session_id = ?',
      [...updates.values, sessionId],
    );
  }

  /// Soft-deletes a planned session, its exercise groups and sets
  /// (is_archived = 1), and hard-deletes its program links.
  Future<void> deletePlannedSession(String sessionId) async {
    await ps.db.execute(
      '''
      UPDATE dim_planned_session_exercise_set SET is_archived = 1
      WHERE planned_exercise_id IN (
        SELECT planned_exercise_id FROM dim_planned_session_exercise
        WHERE planned_session_id = ?
      )
      ''',
      [sessionId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise SET is_archived = 1 WHERE planned_session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session SET date_archived = ? WHERE session_id = ?',
      [DateTime.now().toUtc().toIso8601String(), sessionId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_session_program WHERE planned_session_id = ?',
      [sessionId],
    );
  }

  /// Archived templates, latest archived first — the workouts tab's
  /// archived sheet.
  Future<List<PlannedSession>> fetchArchivedPlannedSessions(
    String userId,
  ) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_planned_session WHERE user_id = ? AND date_archived IS NOT NULL ORDER BY date_archived DESC',
      [userId],
    );
    return rows.map((r) => PlannedSession.fromMap(r)).toList();
  }

  /// Re-enables an archived template (clears its archive date).
  Future<void> reactivatePlannedSession(String sessionId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session SET date_archived = NULL WHERE session_id = ?',
      [sessionId],
    );
  }

  /// How many logged sessions were started from this template — > 0 means it
  /// can only be archived (fact rows FK it).
  Future<int> plannedSessionUsageCount(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT COUNT(*) c FROM fact_session WHERE planned_session_id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return 0;
    final v = rows.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  /// Hard-deletes a never-used template and everything under it (groups,
  /// sets, program links). Callers MUST check [plannedSessionUsageCount]
  /// first — the fact FK is the server backstop.
  Future<void> hardDeletePlannedSession(String sessionId) async {
    await ps.db.execute(
      '''
      DELETE FROM dim_planned_session_exercise_set
      WHERE planned_exercise_id IN (
        SELECT planned_exercise_id FROM dim_planned_session_exercise
        WHERE planned_session_id = ?
      )
      ''',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_session_exercise WHERE planned_session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_session_program WHERE planned_session_id = ?',
      [sessionId],
    );
    await ps.db.execute(
      'DELETE FROM dim_planned_session WHERE session_id = ?',
      [sessionId],
    );
  }

  /// One template by id — used to restore a session's planned context from
  /// its persisted `planned_session_id` (the template may be standalone or
  /// program-attached; both live in the same table).
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_planned_session WHERE session_id = ? AND date_archived IS NULL',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return PlannedSession.fromMap(rows.first);
  }

  // ── Exercise groups ────────────────────────────────────────────────────────

  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT pe.*, e.exercise_name AS exercise_name
      FROM dim_planned_session_exercise pe
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = pe.custom_exercise_id
      WHERE pe.planned_session_id = ? AND pe.is_archived = 0
      ORDER BY pe.exercise_order
      ''',
      [plannedSessionId],
    );
    return rows.map((r) => PlannedSessionExercise.fromMap(r)).toList();
  }

  Future<PlannedSessionExercise> createPlannedExercise(
    String userId,
    String plannedSessionId, {
    String? exerciseId,
    required int exerciseOrder,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_exercise
        (id, planned_exercise_id, planned_session_id, user_id, custom_exercise_id,
         exercise_order, is_archived)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        plannedSessionId,
        userId,
        exerciseId,
        exerciseOrder,
        0,
      ],
    );
    return PlannedSessionExercise(
      plannedExerciseId: id,
      plannedSessionId: plannedSessionId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseOrder: exerciseOrder,
    );
  }

  /// Archives an exercise group and its sets.
  Future<void> deletePlannedExercise(String plannedExerciseId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET is_archived = 1 WHERE planned_exercise_id = ?',
      [plannedExerciseId],
    );
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise SET is_archived = 1 WHERE planned_exercise_id = ?',
      [plannedExerciseId],
    );
  }

  // ── Planned sets ───────────────────────────────────────────────────────────

  /// Fetches a template's active target sets, hydrated with the exercise from
  /// their parent group so consumers don't need to re-join.
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId,
  ) async {
    final rows = await ps.db.getAll(
      '''
      SELECT s.*,
             pe.custom_exercise_id,
             pe.planned_session_id,
             e.exercise_name,
             v.variation_name
      FROM dim_planned_session_exercise_set s
      JOIN dim_planned_session_exercise pe
        ON pe.planned_exercise_id = s.planned_exercise_id
      LEFT JOIN dim_exercise e ON e.custom_exercise_id = pe.custom_exercise_id
      LEFT JOIN dim_variation v ON v.custom_variation_id = s.custom_variation_id
      WHERE pe.planned_session_id = ? AND s.is_archived = 0
      ORDER BY pe.exercise_order, s.set_number
      ''',
      [plannedSessionId],
    );
    return rows.map((r) => PlannedSessionExerciseSet.fromMap(r)).toList();
  }

  Future<PlannedSessionExerciseSet> createPlannedSet(
    String userId,
    String plannedExerciseId, {
    required String plannedSessionId,
    String? exerciseId,
    String? variationId,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_exercise_set
        (id, planned_set_id, planned_exercise_id, user_id, custom_variation_id,
         set_number, target_weight, target_reps, target_notes, is_archived)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        plannedExerciseId,
        userId,
        variationId,
        setNumber,
        targetWeight?.isNotEmpty == true ? targetWeight : null,
        targetReps?.isNotEmpty == true ? targetReps : null,
        targetNotes,
        0,
      ],
    );
    return PlannedSessionExerciseSet(
      plannedSetId: id,
      plannedExerciseId: plannedExerciseId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetNotes: targetNotes,
    );
  }

  Future<void> updatePlannedSet(
    String plannedSetId, {
    String? targetWeight,
    bool clearWeight = false,
    String? targetReps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? targetNotes,
    bool clearNotes = false,
  }) async {
    final updates = <String, dynamic>{};
    if (clearWeight) {
      updates['target_weight'] = null;
    } else if (targetWeight != null && targetWeight.isNotEmpty) {
      updates['target_weight'] = targetWeight;
    }
    if (clearReps) {
      updates['target_reps'] = null;
    } else if (targetReps != null && targetReps.isNotEmpty) {
      updates['target_reps'] = targetReps;
    }
    if (clearVariation) {
      updates['custom_variation_id'] = null;
    } else if (variationId != null) {
      updates['custom_variation_id'] = variationId;
    }
    if (clearNotes) {
      updates['target_notes'] = null;
    } else if (targetNotes != null) {
      updates['target_notes'] = targetNotes;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET $setClause WHERE planned_set_id = ?',
      [...updates.values, plannedSetId],
    );
  }

  /// Soft-deletes a planned set.
  Future<void> deletePlannedSet(String plannedSetId) async {
    await ps.db.execute(
      'UPDATE dim_planned_session_exercise_set SET is_archived = 1 WHERE planned_set_id = ?',
      [plannedSetId],
    );
  }

  /// A template's active sets, in the order the planner and the session
  /// preview both read them, with that order repaired on the way out:
  /// `exercise_order` across the groups and `set_number` within each, both
  /// renumbered by first appearance so the planner's counts and the preview's
  /// rows can never disagree about a template's shape. Idempotent — in steady
  /// state it writes nothing.
  ///
  /// **Nothing is archived here, and that is the point.** An empty planned set
  /// is a value the user saved: `WorkoutEditorViewModel.saveWorkout` writes one
  /// per untouched draft so that an exercise added to a workout survives a
  /// save/reopen before any target is entered. A row with no target data is
  /// indistinguishable from one an earlier version of this pass pruned as a
  /// keep-alive stub — so pruning here deleted exactly what Save had just
  /// written, and an exercise whose sets were all empty vanished on the next
  /// open. Only an explicit user action (`deletePlannedSet`,
  /// `deletePlannedExercise`) archives a row.
  Future<List<PlannedSessionExerciseSet>> fetchNormalizedPlannedSets(
    String plannedSessionId,
  ) async {
    final sets = await fetchPlannedSets(plannedSessionId);
    final exercises = await fetchPlannedExercises(plannedSessionId);

    final nextSetNumber = <String, int>{};
    for (final s in sets) {
      final number = nextSetNumber.putIfAbsent(s.plannedExerciseId, () => 1);
      nextSetNumber[s.plannedExerciseId] = number + 1;
      if (number != s.setNumber) {
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise_set SET set_number = ? WHERE planned_set_id = ?',
          [number, s.plannedSetId],
        );
      }
    }

    // Groups are numbered by their own order, not by the sets that follow them:
    // a group with no sets is still a group, and leaving it out of the
    // renumbering would let it collide with one that was renumbered.
    var nextOrder = 0;
    for (final e in exercises) {
      nextOrder++;
      if (nextOrder != e.exerciseOrder) {
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise SET exercise_order = ? WHERE planned_exercise_id = ?',
          [nextOrder, e.plannedExerciseId],
        );
      }
    }
    return fetchPlannedSets(plannedSessionId);
  }

  /// Deep-copies a planned session with all its exercise groups and sets
  /// (standalone). When [sourceLink] is given, the copy is also linked into
  /// the same program right after the source's slot (sequence bump included).
  Future<String> duplicatePlannedSession(
    String userId,
    PlannedSession source, {
    PlannedSessionProgram? sourceLink,
  }) async {
    final exercises = await fetchPlannedExercises(source.sessionId);
    final sets = await fetchPlannedSets(source.sessionId);

    final names = await _sessionNames(userId);
    final copyName = uniqueName(
      '${source.name} (Copy)',
      names,
      numbered: (n) => '${source.name} (Copy $n)',
    );

    final newId = _uuid.v4();
    final createdDate = DateTime.now().toUtc();

    await ps.safeWriteTransaction((tx) async {
      await _insertCopy(
        tx,
        userId,
        source: source,
        exercises: exercises,
        sets: sets,
        newId: newId,
        name: copyName,
        // A copy of a program workout inherits its base; a copy of a library
        // workout points at it. Either way the lineage names the original
        // rather than the last intermediate.
        baseSessionId: source.baseSessionId ??
            (sourceLink == null ? source.sessionId : null),
        createdDate: createdDate,
      );

      if (sourceLink != null) {
        // Bump later slots so the copy doesn't clobber sequence order.
        await tx.execute(
          '''
          UPDATE dim_planned_session_program
          SET sequence_order = sequence_order + 1
          WHERE program_id = ? AND sequence_order > ?
          ''',
          [sourceLink.programId, sourceLink.sequenceOrder ?? 0],
        );
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
            sourceLink.programId,
            newId,
            userId,
            (sourceLink.sequenceOrder ?? 0) + 1,
            sourceLink.dayOfWeek,
            sourceLink.weekOffset,
          ],
        );
      }
    });

    return newId;
  }

  /// Copies a library workout into [programId] as a program-local workout.
  ///
  /// This is how a workout enters a program from outside it. The library is a
  /// SOURCE, not a shared dependency: the copy is independent forever, editing
  /// it never touches the original, and the original is left exactly as it was.
  ///
  /// The name is kept verbatim — provenance lives in `base_session_id`, not in
  /// a "(Copy)" suffix, because importing is the normal path and suffix noise
  /// would land on every workout of every program. There is no name-uniqueness
  /// check for the same reason: a program may hold several workouts sharing a
  /// name, and the library original sharing the name is the expected case.
  ///
  /// [sequenceOrder] defaults to the end of the program's order. [blockId]
  /// places the copy straight into a block; null leaves it in the program's
  /// unassigned group.
  Future<String> copySessionIntoProgram(
    String userId, {
    required PlannedSession source,
    required String programId,
    int? sequenceOrder,
    String? blockId,
  }) async {
    final exercises = await fetchPlannedExercises(source.sessionId);
    final sets = await fetchPlannedSets(source.sessionId);

    final newId = _uuid.v4();
    final createdDate = DateTime.now().toUtc();

    await ps.safeWriteTransaction((tx) async {
      await _insertCopy(
        tx,
        userId,
        source: source,
        exercises: exercises,
        sets: sets,
        newId: newId,
        name: source.name,
        // The source is a library workout by construction; inheriting its base
        // if it somehow has one keeps a chain of copies pointing home.
        baseSessionId: source.baseSessionId ?? source.sessionId,
        createdDate: createdDate,
      );

      // Append rather than count the list the caller happens to be holding:
      // sequence_order is program-global and need not be dense, so the only
      // reliable "last place" is the column itself.
      var order = sequenceOrder;
      if (order == null) {
        final rows = await tx.getAll(
          'SELECT MAX(sequence_order) AS max_order FROM dim_planned_session_program WHERE program_id = ?',
          [programId],
        );
        order = (_toInt(rows.isEmpty ? null : rows.first['max_order']) ?? 0) + 1;
      }

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
          programId,
          newId,
          userId,
          order,
          null,
          null,
          blockId,
        ],
      );
    });

    return newId;
  }

  /// A single deep copy inside a transaction the CALLER owns.
  ///
  /// The children are passed in rather than read here, deliberately: a caller
  /// holding a write transaction must not query `ps.db` (it contends with the
  /// write lock the transaction holds), so the read happens before the
  /// transaction opens and the already-read rows arrive as arguments. Same
  /// contract as `_insertCopy`, exposed for callers outside this file —
  /// [ProgramRepository.duplicateBlock] copies a whole block's worth of
  /// workouts in one transaction.
  ///
  /// Returns the new session id.
  Future<String> insertCopyIn(
    dynamic tx,
    String userId, {
    required PlannedSession source,
    required List<PlannedSessionExercise> exercises,
    required List<PlannedSessionExerciseSet> sets,
    required String? baseSessionId,
  }) async {
    final newId = _uuid.v4();
    await _insertCopy(
      tx,
      userId,
      source: source,
      exercises: exercises,
      sets: sets,
      newId: newId,
      name: source.name,
      baseSessionId: baseSessionId,
      createdDate: DateTime.now().toUtc(),
    );
    return newId;
  }

  /// The one deep-copy body: a session row plus its exercise groups and target
  /// sets, all under fresh ids.
  ///
  /// Takes a transaction the CALLER owns so the copy and whatever attaches it
  /// (a program link, a slot bump) commit together — a half-copied workout
  /// already attached to a program is worse than no copy at all.
  Future<void> _insertCopy(
    dynamic tx,
    String userId, {
    required PlannedSession source,
    required List<PlannedSessionExercise> exercises,
    required List<PlannedSessionExerciseSet> sets,
    required String newId,
    required String name,
    required String? baseSessionId,
    required DateTime createdDate,
  }) async {
    await tx.execute(
      '''
      INSERT INTO dim_planned_session
        (id, session_id, user_id, name, notes, date_archived, created_date,
         base_session_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        newId,
        newId,
        userId,
        name,
        source.notes,
        null,
        createdDate.toIso8601String(),
        baseSessionId,
      ],
    );

    await _insertChildren(
      tx,
      userId,
      exercises: exercises,
      sets: sets,
      sessionId: newId,
    );
  }

  /// Writes [exercises] and [sets] as fresh rows under [sessionId].
  Future<void> _insertChildren(
    dynamic tx,
    String userId, {
    required List<PlannedSessionExercise> exercises,
    required List<PlannedSessionExerciseSet> sets,
    required String sessionId,
  }) async {
    for (final exercise in exercises) {
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
          sessionId,
          userId,
          exercise.exerciseId,
          exercise.exerciseOrder,
          0,
        ],
      );

      final exerciseSets = sets
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
  }

  /// Creates a standalone (library) workout holding a copy of [source]'s
  /// contents. Returns the new workout's id.
  ///
  /// Used when a workout authored inside a program is promoted to the library:
  /// it has no original to push to, so this is where its contents land. The
  /// name is kept verbatim and no uniqueness check runs — the workout it was
  /// copied from is usually right there in the program with the same name.
  ///
  /// [linkedCopyId] is the program workout that prompted the promotion. It is
  /// repointed at the new original in the SAME transaction, so "push to
  /// library" leaves either both facts or neither. Without that link the
  /// relationship would be invisible, and pushing twice would mint a second
  /// library workout instead of updating the first.
  Future<String> createLibraryFrom(
    String userId,
    PlannedSession source, {
    String? linkedCopyId,
  }) async {
    final exercises = await fetchPlannedExercises(source.sessionId);
    final sets = await fetchPlannedSets(source.sessionId);
    final newId = _uuid.v4();

    await ps.safeWriteTransaction((tx) async {
      await _insertCopy(
        tx,
        userId,
        source: source,
        exercises: exercises,
        sets: sets,
        newId: newId,
        name: source.name,
        // A library workout has no base: it is the origin, not a copy.
        baseSessionId: null,
        createdDate: DateTime.now().toUtc(),
      );

      if (linkedCopyId != null) {
        await tx.execute(
          'UPDATE dim_planned_session SET base_session_id = ? WHERE session_id = ?',
          [newId, linkedCopyId],
        );
      }
    });

    return newId;
  }

  /// Overwrites a library workout's contents with [source]'s — the write
  /// behind "push this back to the library".
  ///
  /// The target's existing groups are ARCHIVED rather than deleted, matching
  /// how every other dim child goes away. Logged sessions hold plain refs to
  /// `planned_exercise_id` / `planned_set_id` for their ghost hints, and a hard
  /// delete would leave those refs pointing at nothing; the replacement rows
  /// carry fresh ids, so a past session's hint still resolves to the target it
  /// was planned from.
  Future<void> replaceContentsFrom(
    String userId, {
    required String targetSessionId,
    required PlannedSession source,
  }) async {
    final exercises = await fetchPlannedExercises(source.sessionId);
    final sets = await fetchPlannedSets(source.sessionId);

    await ps.safeWriteTransaction((tx) async {
      await tx.execute(
        '''
        UPDATE dim_planned_session_exercise_set SET is_archived = 1
        WHERE planned_exercise_id IN (
          SELECT planned_exercise_id FROM dim_planned_session_exercise
          WHERE planned_session_id = ?
        )
        ''',
        [targetSessionId],
      );
      await tx.execute(
        'UPDATE dim_planned_session_exercise SET is_archived = 1 WHERE planned_session_id = ?',
        [targetSessionId],
      );
      // Name and notes travel with the contents: the point of pushing back is
      // that the library original now reads like the workout the user improved.
      await tx.execute(
        'UPDATE dim_planned_session SET name = ?, notes = ? WHERE session_id = ?',
        [source.name, source.notes, targetSessionId],
      );
      await _insertChildren(
        tx,
        userId,
        exercises: exercises,
        sets: sets,
        sessionId: targetSessionId,
      );
    });
  }

  /// Swaps the exercise_order between two exercise groups in a planned
  /// session (for exercise-tab reordering).
  Future<void> swapExerciseOrders(
    String plannedSessionId,
    int orderA,
    int orderB,
  ) async {
    await ps.db.execute(
      '''
      UPDATE dim_planned_session_exercise
        SET exercise_order = CASE exercise_order
          WHEN ? THEN ? ELSE ? END
      WHERE planned_session_id = ? AND is_archived = 0
      ''',
      [orderA, orderB, orderA, plannedSessionId],
    );
  }

  /// Renumbers every exercise group's order so each (old order → new index)
  /// entry in [orderToIndex] lands at index+1. Two-phase (shift to
  /// negatives, then assign) so intermediate collisions can't occur.
  Future<void> renumberExerciseOrders(
    String plannedSessionId,
    List<(int, int)> orderToIndex,
  ) async {
    final n = orderToIndex.length;
    for (final (old, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_exercise SET exercise_order = ? '
        'WHERE planned_session_id = ? AND exercise_order = ? AND is_archived = 0',
        [-n - index - 1, plannedSessionId, old],
      );
    }
    for (final (_, index) in orderToIndex) {
      await ps.db.execute(
        'UPDATE dim_planned_session_exercise SET exercise_order = ? '
        'WHERE planned_session_id = ? AND exercise_order = ? AND is_archived = 0',
        [index + 1, plannedSessionId, -n - index - 1],
      );
    }
  }

  // ── Program links (join table) ─────────────────────────────────────────────

  /// A program's join rows, in program-global `sequence_order`.
  ///
  /// [blockId] filters to one block. NULL means UNFILTERED, not "blockless" —
  /// a blockless program is simply every link carrying a null `block_id`, and
  /// callers that care filter in Dart (`l.blockId == null`), which reads better
  /// than a second, sentinel-flavoured parameter.
  Future<List<PlannedSessionProgram>> fetchProgramLinks(
    String programId, {
    String? blockId,
  }) async {
    final rows = await ps.db.getAll(
      blockId == null
          ? 'SELECT * FROM dim_planned_session_program WHERE program_id = ? ORDER BY sequence_order NULLS LAST'
          : 'SELECT * FROM dim_planned_session_program WHERE program_id = ? AND block_id = ? ORDER BY sequence_order NULLS LAST',
      blockId == null ? [programId] : [programId, blockId],
    );
    return rows.map((r) => PlannedSessionProgram.fromMap(r)).toList();
  }

  Future<PlannedSessionProgram> createProgramLink(
    String userId, {
    required String programId,
    required String plannedSessionId,
    int? sequenceOrder,
    int? dayOfWeek,
    int? weekOffset,
    String? blockId,
  }) async {
    final id = _uuid.v4();
    await ps.db.execute(
      '''
      INSERT INTO dim_planned_session_program
        (id, planned_session_program_id, program_id, planned_session_id,
         user_id, sequence_order, day_of_week, week_offset, block_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        programId,
        plannedSessionId,
        userId,
        sequenceOrder,
        dayOfWeek,
        weekOffset,
        blockId,
      ],
    );
    return PlannedSessionProgram(
      plannedSessionProgramId: id,
      programId: programId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      sequenceOrder: sequenceOrder,
      dayOfWeek: dayOfWeek,
      weekOffset: weekOffset,
      blockId: blockId,
    );
  }

  Future<void> updateProgramLink(
    String plannedSessionProgramId, {
    int? sequenceOrder,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    int? weekOffset,
    bool clearWeekOffset = false,
    String? blockId,
    bool clearBlockId = false,
  }) async {
    final updates = <String, dynamic>{};
    if (sequenceOrder != null) updates['sequence_order'] = sequenceOrder;
    if (clearDayOfWeek) {
      updates['day_of_week'] = null;
      updates['week_offset'] = null;
    } else {
      if (dayOfWeek != null) updates['day_of_week'] = dayOfWeek;
      if (clearWeekOffset) {
        updates['week_offset'] = null;
      } else if (weekOffset != null) {
        updates['week_offset'] = weekOffset;
      }
    }
    if (clearBlockId) {
      updates['block_id'] = null;
    } else if (blockId != null) {
      updates['block_id'] = blockId;
    }
    if (updates.isEmpty) return;
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_program SET $setClause WHERE planned_session_program_id = ?',
      [...updates.values, plannedSessionProgramId],
    );
  }

  /// Moves a set of the program's workouts into a block — or out of any block,
  /// when [blockId] is null.
  ///
  /// One statement for the whole batch: assigning a workout to a block and
  /// removing it from another must not be able to half-happen, or a workout
  /// could end up in two blocks.
  Future<void> assignLinksToBlock(
    String programId,
    List<String> linkIds,
    String? blockId,
  ) async {
    if (linkIds.isEmpty) return;
    final placeholders = List.filled(linkIds.length, '?').join(', ');
    await ps.db.execute(
      'UPDATE dim_planned_session_program SET block_id = ? '
      'WHERE program_id = ? AND planned_session_program_id IN ($placeholders)',
      [blockId, programId, ...linkIds],
    );
  }

  Future<void> deleteProgramLink(String plannedSessionProgramId) async {
    await ps.db.execute(
      'DELETE FROM dim_planned_session_program WHERE planned_session_program_id = ?',
      [plannedSessionProgramId],
    );
  }
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}
