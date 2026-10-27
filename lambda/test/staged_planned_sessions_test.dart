import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/lambda_exception.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/models/review_stage.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/staged_planned_sessions.dart';

/// The live plan the pass edits, held in memory — every read is real, and
/// every write reaching it fails the test: inside a review the plan must not
/// move, so a delegate write is the bug this fake exists to catch.
class _FakePlan extends Fake implements PlannedSessionRepository {
  _FakePlan({
    required this.workout,
    List<PlannedSessionExercise>? exercises,
    List<PlannedSessionExerciseSet>? sets,
  }) : exercises = exercises ?? const [],
       sets = sets ?? const [];

  PlannedSession workout;
  final List<PlannedSessionExercise> exercises;
  final List<PlannedSessionExerciseSet> sets;

  /// Other live workouts' names, lowercased — the ones a rename has every
  /// right to collide with.
  Set<String> taken = const {};

  /// Every name the staged store asked the delegate to judge.
  final nameChecks = <String>[];

  @override
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async =>
      sessionId == workout.sessionId ? workout : null;

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final e in exercises)
      if (e.plannedSessionId == plannedSessionId &&
          (includeArchived || !e.isArchived))
        e,
  ]..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final s in sets)
      if (s.plannedSessionId == plannedSessionId &&
          (includeArchived || !s.isArchived))
        s,
  ];

  @override
  Future<String?> storedPlannedName(String sessionId) async =>
      sessionId == workout.sessionId ? workout.name : null;

  @override
  Future<void> assertSessionNameAvailable(
    String userId,
    String name, {
    String? excludeSessionId,
  }) async {
    nameChecks.add(name);
    final wanted = name.trim().toLowerCase();
    final selfHoldsIt =
        workout.sessionId != excludeSessionId &&
        workout.name.trim().toLowerCase() == wanted;
    if (selfHoldsIt || taken.contains(wanted)) {
      throw LambdaException('A session named "$name" already exists.');
    }
  }
}

PlannedSession _session(String id, {String name = 'Push Day'}) =>
    PlannedSession(sessionId: id, userId: 'u1', name: name);

PlannedSessionExercise _group(
  String id, {
  String sessionId = 's1',
  int order = 1,
  bool archived = false,
}) => PlannedSessionExercise(
  plannedExerciseId: id,
  plannedSessionId: sessionId,
  userId: 'u1',
  exerciseId: 'ex-bench',
  exerciseOrder: order,
  exerciseName: 'Bench Press',
  isArchived: archived,
);

PlannedSessionExerciseSet _set(
  String id, {
  String groupId = 'g1',
  String sessionId = 's1',
  int number = 1,
  String? weight = '70',
  String? reps = '5',
  bool archived = false,
}) => PlannedSessionExerciseSet(
  plannedSetId: id,
  plannedExerciseId: groupId,
  plannedSessionId: sessionId,
  userId: 'u1',
  exerciseId: 'ex-bench',
  setNumber: number,
  targetWeight: weight,
  targetReps: reps,
  isArchived: archived,
);

void main() {
  late _FakePlan plan;
  late ReviewStage stage;
  late StagedPlannedSessions store;

  setUp(() {
    plan = _FakePlan(
      workout: _session('s1'),
      exercises: [_group('g1'), _group('g2', order: 2)],
      sets: [
        _set('p1'),
        _set('p2', number: 2, weight: '75'),
        _set('p3', groupId: 'g2'),
      ],
    );
    stage = ReviewStage();
    store = StagedPlannedSessions(
      reviewId: 'r1',
      userId: 'u1',
      stage: stage,
      delegate: plan,
    );
  });

  /// The editor's open: the reads that teach the store where each id lives.
  Future<void> open() async {
    await store.fetchPlannedSessionById('s1');
    await store.fetchPlannedExercises('s1', includeArchived: true);
    await store.fetchPlannedSets('s1', includeArchived: true);
  }

  group('StagedPlannedSessions', () {
    test(
      'the first write copies the workout whole and leaves the plan alone',
      () async {
        await open();
        final before = stage.encode();

        await store.updatePlannedSet('p1', targetWeight: '80');
        await store.updatePlannedSession('s1', name: 'Push A');

        expect(stage.contains('s1'), isTrue);
        final staged = stage.workout('s1')!;
        expect(
          staged.sets.keys.toSet(),
          {'p1', 'p2', 'p3'},
          reason:
              'the stage is the whole workout, not a diff — applying it is a '
              'row-for-row write that needs no reading back',
        );
        expect(staged.exercises.keys.toSet(), {'g1', 'g2'});
        expect(staged.name, 'Push A');
        expect(staged.sets['p1']!['target_weight'], '80');
        expect(before, isNot(stage.encode()));
        expect(
          plan.workout.name,
          'Push Day',
          reason:
              'the plan only moves at Finish — a write that reached the '
              'delegate would be exactly the bug staging exists to prevent',
        );
      },
    );

    test('staged reads answer with what the pass has done', () async {
      await open();
      await store.updatePlannedSet('p1', targetWeight: '80', targetReps: '3');
      await store.updatePlannedSession('s1', name: 'Push A', notes: 'go slow');

      final session = await store.fetchPlannedSessionById('s1');
      expect(session!.name, 'Push A');
      expect(session.notes, 'go slow');

      final sets = await store.fetchPlannedSets('s1');
      final first = sets.firstWhere((s) => s.plannedSetId == 'p1');
      expect(first.targetWeight, '80');
      expect(first.targetReps, '3');
      expect(first.setNumber, 1);
    });

    test('a workout the pass never touched reads live', () async {
      await open();
      final other = await store.fetchPlannedSessionById('s9');
      expect(other, isNull, reason: 'the delegate has no s9 either');
      expect(stage.contains('s9'), isFalse);
      expect(stage.contains('s1'), isFalse, reason: 'a read stages nothing');
    });

    test('the normalized read renumbers by appearance off the stage', () async {
      await open();
      await store.deletePlannedSet('p1');

      final rows = await store.readNormalizedPlannedSession('s1');
      expect([for (final r in rows) r.plannedSetId], ['p2', 'p3']);
      expect(
        [for (final r in rows) r.setNumber],
        [1, 1],
        reason:
            'each group numbers from 1 by appearance, exactly as the '
            'repository\'s own read repairs it',
      );
    });

    test('an archived group keeps its rows and comes back whole', () async {
      await open();
      await store.deletePlannedExercise('g1');

      final live = await store.readNormalizedPlannedSession('s1');
      expect(
        [for (final r in live) r.plannedSetId],
        ['p3'],
        reason: 'an active read hides a removed group and its sets',
      );

      final reviewRead = await store.readNormalizedPlannedSession(
        's1',
        includeArchived: true,
      );
      expect(
        [for (final r in reviewRead) r.plannedSetId],
        ['p1', 'p2', 'p3'],
        reason:
            'the review read keeps a removed group\'s rows on the card '
            '(2026-10-26)',
      );

      final groups = await store.fetchPlannedExercises(
        's1',
        includeArchived: true,
      );
      expect(groups.first.isArchived, isTrue);

      await store.restorePlannedExercise('g1', exerciseOrder: 1);
      // A group's restore is its own flag; its sets come back one by one, the
      // way the editor's Restore button walks them.
      await store.restorePlannedSet('p1', setNumber: 1);
      await store.restorePlannedSet('p2', setNumber: 2);
      final restored = await store.readNormalizedPlannedSession('s1');
      expect(
        [for (final r in restored) r.plannedSetId],
        ['p1', 'p2', 'p3'],
        reason:
            'the rows never left the stage, so the restore is a plain '
            'flag flip — back in the slot the delete took it from',
      );
      final order = await store.fetchPlannedExercises('s1');
      expect(
        [for (final g in order) g.plannedExerciseId],
        ['g1', 'g2'],
        reason: 'the captured order is the one restored',
      );
    });

    test('a set removed on its own stays off the review read', () async {
      await open();
      await store.deletePlannedSet('p1');

      final reviewRead = await store.readNormalizedPlannedSession(
        's1',
        includeArchived: true,
      );
      expect(
        [for (final r in reviewRead) r.plannedSetId],
        ['p2', 'p3'],
        reason:
            'the card draws no row the user could not put back; a lone '
            'set\'s removal is not restorable on the card',
      );

      final withArchived = await store.fetchPlannedSets(
        's1',
        includeArchived: true,
      );
      expect(
        [for (final s in withArchived) s.plannedSetId],
        contains('p1'),
        reason: 'the trash still lists what was removed',
      );
    });

    test(
      'a created set stores empty targets as nothing, returns them raw',
      () async {
        await open();
        final created = await store.createPlannedSet(
          'u1',
          'g1',
          plannedSessionId: 's1',
          setNumber: 3,
          targetWeight: '',
          targetReps: '',
        );

        expect(created.targetWeight, '');
        expect(created.targetReps, '');

        final rows = await store.fetchPlannedSets('s1');
        final stored = rows.firstWhere(
          (s) => s.plannedSetId == created.plannedSetId,
        );
        expect(stored.targetWeight, isNull);
        expect(stored.targetReps, isNull);
        expect(stored.setNumber, 3);
      },
    );

    test('updates treat clear as final and empty strings as no-op', () async {
      await open();

      await store.updatePlannedSet('p2', targetWeight: '');
      var rows = await store.fetchPlannedSets('s1');
      expect(
        rows.firstWhere((s) => s.plannedSetId == 'p2').targetWeight,
        '75',
        reason: 'an empty string is the text box settling, not a target',
      );

      await store.updatePlannedSet('p2', targetWeight: '80', clearWeight: true);
      rows = await store.fetchPlannedSets('s1');
      expect(
        rows.firstWhere((s) => s.plannedSetId == 'p2').targetWeight,
        isNull,
        reason: 'clear wins over the value beside it',
      );
    });

    test('renumbering skips an archived set', () async {
      await open();
      await store.deletePlannedSet('p1');

      await store.renumberPlannedSets(['p1', 'p2', 'p3']);

      final rows = await store.fetchPlannedSets('s1', includeArchived: true);
      final byId = {for (final r in rows) r.plannedSetId: r.setNumber};
      expect(byId['p2'], 2);
      expect(byId['p3'], 3);
      expect(
        byId['p1'],
        1,
        reason:
            'the archived row keeps its number — the live write cannot '
            'reach it either',
      );
    });

    test('exercise reordering steps through the negatives', () async {
      await open();
      await store.renumberExerciseOrders('s1', [(1, 2), (2, 1)]);

      final groups = await store.fetchPlannedExercises('s1');
      expect(
        [for (final g in groups) g.plannedExerciseId],
        ['g2', 'g1'],
        reason:
            'a direct swap would collide midway; the repository writes '
            'through negatives and so does the stage',
      );
    });

    test('a rename judges the live rows and the other staged names', () async {
      await open();

      plan.taken = {'push day'};
      await expectLater(
        store.updatePlannedSession('s1', name: 'Push Day'),
        throwsA(isA<LambdaException>()),
        reason:
            'another live workout holds it; a staged rename collides '
            'exactly where a live one does',
      );

      stage.workouts['s2'] = StagedWorkout(
        session: _session('s2', name: 'Pull Day').toMap(),
        exercises: const {},
        sets: const {},
      );
      await expectLater(
        store.updatePlannedSession('s1', name: 'Pull Day'),
        throwsA(isA<LambdaException>()),
        reason:
            'two staged renames that only collide with each other would '
            'otherwise land together at Finish',
      );
      expect(plan.nameChecks, isNotEmpty);
    });

    test('a grandfathered name can be written back', () async {
      plan.workout = _session('s1', name: 'A name that outran its budget');
      await open();

      await store.updatePlannedSession(
        's1',
        name: 'A name that outran its budget',
      );
      expect(stage.workout('s1')!.name, 'A name that outran its budget');

      // The grandfather is the row as found: a store whose live row sits
      // inside the cap refuses a typed over-long name exactly where the field
      // would have.
      final fresh = StagedPlannedSessions(
        reviewId: 'r2',
        userId: 'u1',
        stage: ReviewStage(),
        delegate: _FakePlan(workout: _session('s1')),
      );
      await expectLater(
        fresh.updatePlannedSession('s1', name: 'A typed name over twenty'),
        throwsA(isA<ArgumentError>()),
        reason:
            'the grandfather covers the row as found, not any edit the '
            'field would have stopped',
      );
    });

    test('a pass cannot create, delete or file a workout', () async {
      await expectLater(
        store.createPlannedSession('u1'),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        store.deletePlannedSession('s1'),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        store.createProgramLink('u1', programId: 'p1', plannedSessionId: 's1'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'every write is persisted, and flush waits for the last one',
      () async {
        final persisted = <String>[];
        store = StagedPlannedSessions(
          reviewId: 'r1',
          userId: 'u1',
          stage: stage,
          delegate: plan,
          persist: (s) async => persisted.add(s.encode()),
        );
        await open();

        // Fired without waiting: the editor writes from several places at once
        // and the store must settle them in order.
        final first = store.updatePlannedSet('p1', targetWeight: '80');
        final second = store.updatePlannedSession('s1', name: 'Push A');
        await Future.wait([first, second]);

        await store.flush();
        expect(persisted, hasLength(2));
        final last = ReviewStage.tryDecode(persisted.last)!;
        expect(last.workout('s1')!.name, 'Push A');
        expect(last.workout('s1')!.sets['p1']!['target_weight'], '80');
      },
    );

    test('a failed persist is raised by flush, and only once', () async {
      var calls = 0;
      store = StagedPlannedSessions(
        reviewId: 'r1',
        userId: 'u1',
        stage: stage,
        delegate: plan,
        persist: (s) async {
          calls++;
          if (calls == 1) throw StateError('disk full');
        },
      );
      await open();
      await store.updatePlannedSet('p1', targetWeight: '80');

      await expectLater(store.flush(), throwsA(isA<StateError>()));

      await store.updatePlannedSet('p1', targetWeight: '85');
      await store.flush();
      expect(
        stage.workout('s1')!.sets['p1']!['target_weight'],
        '85',
        reason:
            'the stage in memory is never lost to a failed write; it only '
            'costs durability across a restart',
      );
    });

    test('a variation created mid-pass still names its sets', () async {
      var names = <String, String>{};
      store = StagedPlannedSessions(
        reviewId: 'r1',
        userId: 'u1',
        stage: stage,
        delegate: plan,
        variationNames: () async => names,
      );
      await open();

      await store.updatePlannedSet('p1', variationId: 'v1');
      var rows = await store.fetchPlannedSets('s1');
      expect(
        rows.firstWhere((s) => s.plannedSetId == 'p1').variationName,
        isNull,
        reason: 'the catalog does not have it yet',
      );

      // The variation is created (say, by the picker) and the next read
      // reloads the catalog rather than holding a stale map.
      names = {'v1': 'Paused'};
      rows = await store.fetchPlannedSets('s1');
      expect(
        rows.firstWhere((s) => s.plannedSetId == 'p1').variationName,
        'Paused',
      );
    });
  });
}
