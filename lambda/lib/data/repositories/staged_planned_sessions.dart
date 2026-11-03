import 'package:uuid/uuid.dart';

import '../../core/powersync/database.dart' as ps;
import '../../core/utils/lambda_exception.dart';
import '../../core/utils/name_limit.dart';
import '../models/planned_session.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session_program.dart';
import '../models/review_stage.dart';
import 'planned_session_repository.dart';
import 'planned_session_store.dart';

const _uuid = Uuid();

/// The workout editor's store **inside a review pass** (2026-10-27).
///
/// Every call the editor makes lands here instead of on the live dim rows.
/// The first write to a workout copies that workout whole — its planned
/// session row, every exercise group, every target set, archived rows
/// included — into the pass's [ReviewStage]; from then on the stage answers
/// every read and takes every write, so the editor sees exactly what it has
/// done while the plan underneath never moves.
///
/// The stage is persisted after each write ([persist]), so leaving the app
/// mid-pass keeps the work: the pass resumes into the stage it left. Picking
/// up a workout the pass has not touched reads it live — there is nothing to
/// copy yet.
///
/// Writes are serialized on one chain and [flush] waits for the persisted
/// stage: the editor fires writes from several places at once (a keystroke
/// settle, a blur, the dispose commit), and a later read must never outrun an
/// earlier write.
class StagedPlannedSessions implements PlannedSessionStore {
  StagedPlannedSessions({
    required this.reviewId,
    required this.userId,
    required ReviewStage stage,
    PlannedSessionRepository? delegate,
    Future<Map<String, String>> Function()? variationNames,
    Future<void> Function(ReviewStage stage)? persist,
  }) : _stage = stage,
       _delegate = delegate ?? PlannedSessionRepository(),
       _variationNames = variationNames,
       _persist = persist;

  /// The pass this stage belongs to — what [persist] writes the document to.
  final String reviewId;

  /// The signed-in user, for the rows a staged create invents and the name
  /// checks a rename runs.
  final String userId;

  final ReviewStage _stage;
  final PlannedSessionRepository _delegate;
  final Future<Map<String, String>> Function()? _variationNames;
  final Future<void> Function(ReviewStage stage)? _persist;

  /// The workbook as it stands — the route hands this to the finish so the
  /// completion applies exactly what is on screen.
  ReviewStage get stage => _stage;

  Future<void> _chain = Future<void>.value();
  Object? _persistError;
  Map<String, String>? _variations;

  /// Which workout a group or a set belongs to, learned from every read and
  /// create — a delete is given an id and needs to know where it lives.
  final _groupOwner = <String, String>{};
  final _setOwner = <String, String>{};

  // ── Serialization ─────────────────────────────────────────────────────────

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _chain.then((_) => body());
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _schedulePersist() {
    final persist = _persist;
    if (persist == null) return;
    _chain = _chain
        .then((_) => persist(_stage))
        .then<void>(
          (_) {},
          onError: (Object e) {
            // A failed persist leaves the stage in memory, where the finish still
            // applies it — it only costs durability across an app restart. The
            // error is kept for flush, which is the caller that can say so.
            _persistError = e;
          },
        );
  }

  /// Waits for every pending write and persist, and rethrows the last persist
  /// failure. Called before Finish, so a pass never completes on a stage that
  /// silently failed to save.
  Future<void> flush() async {
    await _chain;
    final error = _persistError;
    if (error != null) {
      _persistError = null;
      throw error;
    }
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  @override
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) {
    final staged = _stage.workout(sessionId);
    if (staged != null) return Future.value(staged.model);
    return _delegate.fetchPlannedSessionById(sessionId);
  }

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId, {
    bool includeArchived = false,
  }) {
    final staged = _stage.workout(plannedSessionId);
    if (staged == null) {
      return _delegate
          .fetchPlannedExercises(
            plannedSessionId,
            includeArchived: includeArchived,
          )
          .then((rows) {
            for (final row in rows) {
              _groupOwner[row.plannedExerciseId] = plannedSessionId;
            }
            return rows;
          });
    }
    return _serial(
      () async => _exerciseModels(staged, includeArchived: includeArchived),
    );
  }

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId, {
    bool includeArchived = false,
  }) {
    final staged = _stage.workout(plannedSessionId);
    if (staged == null) {
      return _delegate
          .fetchPlannedSets(plannedSessionId, includeArchived: includeArchived)
          .then((rows) {
            for (final row in rows) {
              _setOwner[row.plannedSetId] = plannedSessionId;
            }
            return rows;
          });
    }
    return _serial(() => _setModels(staged, includeArchived: includeArchived));
  }

  @override
  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String plannedSessionId, {
    bool includeArchived = false,
  }) {
    final staged = _stage.workout(plannedSessionId);
    if (staged == null) {
      return _delegate
          .readNormalizedPlannedSession(
            plannedSessionId,
            includeArchived: includeArchived,
          )
          .then((rows) {
            for (final row in rows) {
              _setOwner[row.plannedSetId] = plannedSessionId;
              _groupOwner[row.plannedExerciseId] = plannedSessionId;
            }
            return rows;
          });
    }
    // The repository's read, mirrored row for row: a removed GROUP keeps the
    // rows under it, a set removed on its own stays hidden, and both number
    // by first appearance (2026-10-26).
    return _serial(() async {
      final exercises = _exerciseModels(
        staged,
        includeArchived: includeArchived,
      );
      final archivedGroups = {
        for (final e in exercises)
          if (e.isArchived) e.plannedExerciseId,
      };
      final allSets = await _setModels(
        staged,
        includeArchived: includeArchived,
      );
      final sets = includeArchived
          ? [
              for (final s in allSets)
                if (!s.isArchived ||
                    archivedGroups.contains(s.plannedExerciseId))
                  s,
            ]
          : allSets;
      final exerciseOrder = {
        for (var i = 0; i < exercises.length; i++)
          exercises[i].plannedExerciseId: i + 1,
      };
      final nextSetNumber = <String, int>{};
      final out = <PlannedSessionExerciseSet>[];
      for (final s in sets) {
        if (!exerciseOrder.containsKey(s.plannedExerciseId)) {
          out.add(s);
          continue;
        }
        final number = nextSetNumber.putIfAbsent(s.plannedExerciseId, () => 1);
        nextSetNumber[s.plannedExerciseId] = number + 1;
        out.add(s.copyWith(setNumber: number));
      }
      return out;
    });
  }

  /// The stage's groups, filtered and ordered as the repository's read.
  List<PlannedSessionExercise> _exerciseModels(
    StagedWorkout workout, {
    required bool includeArchived,
  }) {
    final rows = [
      for (final row in workout.exercises.values)
        if (includeArchived || !_archived(row))
          PlannedSessionExercise.fromMap(row),
    ]..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));
    for (final row in rows) {
      _groupOwner[row.plannedExerciseId] = workout.sessionId;
    }
    return rows;
  }

  /// The stage's sets, filtered and ordered as the repository's JOINed read —
  /// exercise and variation names hydrated from the group and the live
  /// catalog, because the stage stores neither.
  Future<List<PlannedSessionExerciseSet>> _setModels(
    StagedWorkout workout, {
    required bool includeArchived,
  }) async {
    final rows = [
      for (final row in workout.sets.values)
        if (includeArchived || !_archived(row)) row,
    ];
    final names = await _variationMap(
      rows.map((row) => row['custom_variation_id'] as String?),
    );

    final groupOrder = <String, int>{};
    final groupExercise = <String, String?>{};
    final groupName = <String, String?>{};
    for (final group in workout.exercises.values) {
      final id = group['planned_exercise_id'] as String;
      groupOrder[id] = (group['exercise_order'] as num?)?.toInt() ?? 0;
      groupExercise[id] = group['custom_exercise_id'] as String?;
      groupName[id] = group['exercise_name'] as String?;
    }

    final models = <PlannedSessionExerciseSet>[
      for (final row in rows)
        PlannedSessionExerciseSet.fromMap({
          ...row,
          'custom_exercise_id':
              row['custom_exercise_id'] ??
              groupExercise[row['planned_exercise_id']],
          'exercise_name':
              row['exercise_name'] ?? groupName[row['planned_exercise_id']],
          'variation_name': switch (row['custom_variation_id']) {
            final String id => names?[id] ?? row['variation_name'],
            _ => null,
          },
        }),
    ];
    models.sort((a, b) {
      final byGroup = (groupOrder[a.plannedExerciseId] ?? 0).compareTo(
        groupOrder[b.plannedExerciseId] ?? 0,
      );
      return byGroup != 0 ? byGroup : a.setNumber.compareTo(b.setNumber);
    });
    for (final row in models) {
      _setOwner[row.plannedSetId] = workout.sessionId;
    }
    return models;
  }

  /// The live variation catalog, loaded once and reloaded only when a row
  /// names a variation the cache does not hold (one created mid-pass).
  Future<Map<String, String>?> _variationMap(Iterable<String?> ids) async {
    final needed = [for (final id in ids) ?id];
    if (needed.isEmpty) return _variations;
    final cached = _variations;
    if (cached != null && needed.every(cached.containsKey)) return cached;
    final resolver = _variationNames;
    if (resolver == null) return cached;
    try {
      _variations = await resolver();
    } catch (_) {
      // A failed catalog read only costs names the next read retries.
    }
    return _variations;
  }

  // ── Seeding ───────────────────────────────────────────────────────────────

  /// The workout's entry in the stage, copied whole from the live rows on the
  /// first write. Every later read and write of it goes through this.
  Future<StagedWorkout> _ensure(String sessionId) {
    final existing = _stage.workout(sessionId);
    if (existing != null) return Future.value(existing);
    return () async {
      final session = await _delegate.fetchPlannedSessionById(sessionId);
      if (session == null) {
        throw StateError('Workout $sessionId is no longer available.');
      }
      final exercises = await _delegate.fetchPlannedExercises(
        sessionId,
        includeArchived: true,
      );
      final sets = await _delegate.fetchPlannedSets(
        sessionId,
        includeArchived: true,
      );
      final workout = StagedWorkout(
        session: session.toMap(),
        exercises: {for (final e in exercises) e.plannedExerciseId: e.toMap()},
        sets: {for (final s in sets) s.plannedSetId: s.toMap()},
      );
      _stage.workouts[sessionId] = workout;
      for (final e in exercises) {
        _groupOwner[e.plannedExerciseId] = sessionId;
      }
      for (final s in sets) {
        _setOwner[s.plannedSetId] = sessionId;
      }
      return workout;
    }();
  }

  /// Which workout a group belongs to: learned from a read, else the stage
  /// itself, else one row read from the mirror.
  Future<String> _ownerOfGroup(String plannedExerciseId) async {
    final known = _groupOwner[plannedExerciseId];
    if (known != null) return known;
    for (final entry in _stage.workouts.entries) {
      if (entry.value.exercises.containsKey(plannedExerciseId)) {
        return _groupOwner[plannedExerciseId] = entry.key;
      }
    }
    final rows = await ps.db.getAll(
      'SELECT planned_session_id FROM dim_planned_session_exercise '
      'WHERE planned_exercise_id = ?',
      [plannedExerciseId],
    );
    if (rows.isEmpty) {
      throw StateError('Unknown planned exercise $plannedExerciseId.');
    }
    return _groupOwner[plannedExerciseId] =
        rows.first['planned_session_id'] as String;
  }

  /// Which workout a set belongs to — the same lookup one level down.
  Future<String> _ownerOfSet(String plannedSetId) async {
    final known = _setOwner[plannedSetId];
    if (known != null) return known;
    for (final entry in _stage.workouts.entries) {
      if (entry.value.sets.containsKey(plannedSetId)) {
        return _setOwner[plannedSetId] = entry.key;
      }
    }
    final rows = await ps.db.getAll(
      '''
      SELECT pe.planned_session_id
      FROM dim_planned_session_exercise_set s
      JOIN dim_planned_session_exercise pe
        ON pe.planned_exercise_id = s.planned_exercise_id
      WHERE s.planned_set_id = ?
      ''',
      [plannedSetId],
    );
    if (rows.isEmpty) throw StateError('Unknown planned set $plannedSetId.');
    return _setOwner[plannedSetId] = rows.first['planned_session_id'] as String;
  }

  // ── Session writes ────────────────────────────────────────────────────────

  /// A review edits the workouts it was given — it never creates one.
  @override
  Future<PlannedSession> createPlannedSession(
    String userId, {
    String? name,
    String? notes,
  }) async => throw UnsupportedError('A review pass cannot create a workout.');

  /// A review edits the workouts it was given — it never archives one.
  @override
  Future<void> deletePlannedSession(String sessionId) async =>
      throw UnsupportedError('A review pass cannot delete a workout.');

  /// Membership is the pass's own stored set — a review never re-files one.
  @override
  Future<PlannedSessionProgram> createProgramLink(
    String userId, {
    required String programId,
    required String plannedSessionId,
    int? sequenceOrder,
    int? dayOfWeek,
    int? weekOffset,
    String? blockId,
  }) async => throw UnsupportedError(
    'A review pass cannot link a workout into a program.',
  );

  @override
  Future<void> updatePlannedSession(
    String sessionId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    String userId = '',
  }) {
    return _serial(() async {
      final workout = await _ensure(sessionId);
      var changed = false;
      if (name != null) {
        final stored = await _delegate.storedPlannedName(sessionId);
        // The row as the plan holds it is what the cap judges: an over-long
        // name written before the cap tightened must still be writable back,
        // or a discard inside the pass could not roll back at all — the same
        // grandfather rule the repository applies to that path.
        final grandfathered =
            stored != null && nameTooLong(stored, kMaxWorkoutNameLength);
        if (!grandfathered && nameTooLong(name, kMaxWorkoutNameLength)) {
          throw ArgumentError.value(
            name,
            'name',
            'exceeds $kMaxWorkoutNameLength characters',
          );
        }
        await _assertNameUnique(
          userId.isEmpty ? this.userId : userId,
          name,
          sessionId,
        );
        workout.session['name'] = name;
        changed = true;
      }
      if (clearNotes) {
        workout.session['notes'] = null;
        changed = true;
      } else if (notes != null) {
        workout.session['notes'] = notes;
        changed = true;
      }
      if (changed) _schedulePersist();
    });
  }

  /// A name is unique among the user's active workouts — the live rows, less
  /// this one, plus the other workouts this pass has already staged a name
  /// for. Two renames that only collide with each other would otherwise land
  /// together at Finish.
  Future<void> _assertNameUnique(
    String userId,
    String name,
    String excludeSessionId,
  ) async {
    await _delegate.assertSessionNameAvailable(
      userId,
      name,
      excludeSessionId: excludeSessionId,
    );
    final wanted = name.trim().toLowerCase();
    for (final entry in _stage.workouts.entries) {
      if (entry.key == excludeSessionId) continue;
      if (entry.value.name.trim().toLowerCase() == wanted) {
        throw LambdaException('A session named "$name" already exists.');
      }
    }
  }

  // ── Group writes ──────────────────────────────────────────────────────────

  @override
  Future<PlannedSessionExercise> createPlannedExercise(
    String userId,
    String plannedSessionId, {
    String? exerciseId,
    required int exerciseOrder,
  }) {
    return _serial(() async {
      final workout = await _ensure(plannedSessionId);
      final id = _uuid.v4();
      final row = <String, dynamic>{
        'planned_exercise_id': id,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'exercise_order': exerciseOrder,
        'exercise_name': null,
        'is_archived': false,
      };
      workout.exercises[id] = row;
      _groupOwner[id] = plannedSessionId;
      _schedulePersist();
      return PlannedSessionExercise.fromMap(row);
    });
  }

  @override
  Future<void> deletePlannedExercise(String plannedExerciseId) {
    return _serial(() async {
      final workout = await _ensure(await _ownerOfGroup(plannedExerciseId));
      final group = workout.exercises[plannedExerciseId];
      if (group == null) {
        throw StateError('Unknown planned exercise $plannedExerciseId.');
      }
      group['is_archived'] = true;
      for (final set in workout.sets.values) {
        if (set['planned_exercise_id'] == plannedExerciseId) {
          set['is_archived'] = true;
        }
      }
      _schedulePersist();
    });
  }

  @override
  Future<void> restorePlannedExercise(
    String plannedExerciseId, {
    required int exerciseOrder,
  }) {
    return _serial(() async {
      final workout = await _ensure(await _ownerOfGroup(plannedExerciseId));
      final group = workout.exercises[plannedExerciseId];
      if (group == null) {
        throw StateError('Unknown planned exercise $plannedExerciseId.');
      }
      group['is_archived'] = false;
      group['exercise_order'] = exerciseOrder;
      _schedulePersist();
    });
  }

  @override
  Future<void> renumberExerciseOrders(
    String plannedSessionId,
    List<(int, int)> orderToIndex,
  ) {
    return _serial(() async {
      final workout = await _ensure(plannedSessionId);
      // Two phases through the negatives, exactly as the repository writes
      // them: a direct assignment could collide midway through a reorder.
      final n = orderToIndex.length;
      for (final (old, index) in orderToIndex) {
        for (final group in workout.exercises.values) {
          if (_archived(group)) continue;
          if ((group['exercise_order'] as num?)?.toInt() == old) {
            group['exercise_order'] = -n - index - 1;
          }
        }
      }
      for (final (_, index) in orderToIndex) {
        for (final group in workout.exercises.values) {
          if (_archived(group)) continue;
          if ((group['exercise_order'] as num?)?.toInt() == -n - index - 1) {
            group['exercise_order'] = index + 1;
          }
        }
      }
      _schedulePersist();
    });
  }

  // ── Set writes ────────────────────────────────────────────────────────────

  @override
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
  }) {
    return _serial(() async {
      final workout = await _ensure(plannedSessionId);
      final id = _uuid.v4();
      final row = <String, dynamic>{
        'planned_set_id': id,
        'planned_exercise_id': plannedExerciseId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'set_number': setNumber,
        'target_weight': targetWeight?.isNotEmpty == true ? targetWeight : null,
        'target_reps': targetReps?.isNotEmpty == true ? targetReps : null,
        'target_notes': targetNotes,
        'exercise_name': null,
        'variation_name': _variations?[variationId],
        'is_archived': false,
      };
      workout.sets[id] = row;
      _setOwner[id] = plannedSessionId;
      _schedulePersist();
      // The repository returns the arguments, not the row — an empty string is
      // stored as nothing but comes back as given.
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
    });
  }

  @override
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
  }) {
    return _serial(() async {
      final workout = await _ensure(await _ownerOfSet(plannedSetId));
      final set = workout.sets[plannedSetId];
      if (set == null) throw StateError('Unknown planned set $plannedSetId.');
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
        updates['variation_name'] = null;
      } else if (variationId != null) {
        updates['custom_variation_id'] = variationId;
        // The name is resolved on read; storing what the catalog held keeps a
        // snapshot faithful when no catalog read is available.
        updates['variation_name'] = _variations?[variationId];
      }
      if (clearNotes) {
        updates['target_notes'] = null;
      } else if (targetNotes != null) {
        updates['target_notes'] = targetNotes;
      }
      if (updates.isEmpty) return;
      set.addAll(updates);
      _schedulePersist();
    });
  }

  @override
  Future<void> deletePlannedSet(String plannedSetId) {
    return _serial(() async {
      final workout = await _ensure(await _ownerOfSet(plannedSetId));
      final set = workout.sets[plannedSetId];
      if (set == null) throw StateError('Unknown planned set $plannedSetId.');
      set['is_archived'] = true;
      _schedulePersist();
    });
  }

  @override
  Future<void> restorePlannedSet(
    String plannedSetId, {
    required int setNumber,
  }) {
    return _serial(() async {
      final workout = await _ensure(await _ownerOfSet(plannedSetId));
      final set = workout.sets[plannedSetId];
      if (set == null) throw StateError('Unknown planned set $plannedSetId.');
      set['is_archived'] = false;
      set['set_number'] = setNumber;
      _schedulePersist();
    });
  }

  @override
  Future<void> renumberPlannedSets(List<String> orderedSetIds) {
    return _serial(() async {
      for (var i = 0; i < orderedSetIds.length; i++) {
        final id = orderedSetIds[i];
        final workout = await _ensure(await _ownerOfSet(id));
        final set = workout.sets[id];
        if (set == null || _archived(set)) continue;
        set['set_number'] = i + 1;
      }
      _schedulePersist();
    });
  }

  static bool _archived(Map<String, dynamic> row) {
    final value = row['is_archived'];
    if (value is bool) return value;
    if (value is int) return value != 0;
    return false;
  }
}
