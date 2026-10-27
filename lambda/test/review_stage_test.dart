import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/review_stage.dart';

/// One staged workout, shaped exactly as `StagedPlannedSessions` copies it:
/// the model's own `toMap` keys, one group, one set.
StagedWorkout _workout(
  String id, {
  String name = 'Push Day',
  bool archived = false,
  bool groupArchived = false,
}) => StagedWorkout(
  session: {
    'session_id': id,
    'user_id': 'u1',
    'name': name,
    'notes': null,
    'date_archived': archived ? '2026-10-27T00:00:00.000Z' : null,
    'created_date': '2026-01-01T00:00:00.000Z',
    'base_session_id': null,
    'coach_assignment_id': null,
  },
  exercises: {
    '$id-g1': {
      'planned_exercise_id': '$id-g1',
      'planned_session_id': id,
      'user_id': 'u1',
      'custom_exercise_id': 'ex-bench',
      'exercise_order': 1,
      'exercise_name': 'Bench Press',
      'is_archived': groupArchived,
    },
  },
  sets: {
    '$id-s1': {
      'planned_set_id': '$id-s1',
      'planned_exercise_id': '$id-g1',
      'planned_session_id': id,
      'user_id': 'u1',
      'custom_exercise_id': 'ex-bench',
      'custom_variation_id': null,
      'set_number': 1,
      'target_weight': '70',
      'target_reps': '5',
      'target_notes': null,
      'exercise_name': 'Bench Press',
      'variation_name': null,
      'is_archived': false,
    },
  },
);

void main() {
  group('ReviewStage', () {
    test('an untouched stage encodes as an empty document', () {
      final stage = ReviewStage();
      expect(stage.isEmpty, isTrue);
      expect(ReviewStage.tryDecode(stage.encode())!.isEmpty, isTrue);
    });

    test('a stage round-trips every row and the order they were staged in', () {
      final stage = ReviewStage(
        workouts: {
          's2': _workout('s2', name: 'Pull Day'),
          's1': _workout('s1', groupArchived: true),
        },
      );

      final decoded = ReviewStage.tryDecode(stage.encode())!;

      expect(
        decoded.workouts.keys.toList(),
        ['s2', 's1'],
        reason:
            'staging order is the encode order — a resume walks them in '
            'the order the pass touched them',
      );
      final pull = decoded.workout('s2')!;
      expect(pull.name, 'Pull Day');
      expect(pull.exercises.keys, ['s2-g1']);
      expect(pull.sets['s2-s1']!['target_weight'], '70');
      expect(
        decoded.workout('s1')!.exercises['s1-g1']!['is_archived'],
        isTrue,
        reason:
            'an archived group is part of the workout the pass left; a '
            'stage that dropped it could not put it back',
      );
      expect(
        decoded.encode(),
        stage.encode(),
        reason:
            'decode-then-encode is the same document — hashes compare '
            'across a restart',
      );
    });

    test('a workout the pass archived carries no model to read', () {
      final workout = _workout('s1', archived: true);
      expect(workout.isArchived, isTrue);
      expect(workout.model, isNull);
      expect(_workout('s1').model, isNotNull);
    });

    test('the hash moves only when the content does', () {
      final a = ReviewStage(workouts: {'s1': _workout('s1')});
      final b = ReviewStage(workouts: {'s1': _workout('s1')});
      final c = ReviewStage(workouts: {'s1': _workout('s1', name: 'Push 2')});

      expect(a.contentHash, b.contentHash);
      expect(a.contentHash, isNot(c.contentHash));
      expect(a.contentHash, hasLength(64));
    });

    test('what the build cannot read decodes to no stage at all', () {
      expect(ReviewStage.tryDecode(null), isNull);
      expect(ReviewStage.tryDecode(''), isNull);
      expect(ReviewStage.tryDecode('not json'), isNull);
      expect(
        ReviewStage.tryDecode('{"stage":2,"workouts":{}}'),
        isNull,
        reason: 'a document from a newer build is not half-read',
      );
      expect(
        ReviewStage.tryDecode('{"sessions":[],"goals":[]}'),
        isNull,
        reason:
            'the column once held ProgramContent; a leftover one must not '
            'read as a stage with no version',
      );
    });

    test('rows without ids are dropped rather than crashing the resume', () {
      final decoded = ReviewStage.tryDecode(
        '{"stage":1,"workouts":{"s1":{'
        '"session":{"session_id":"s1","name":"Push"},'
        '"exercises":[{"exercise_order":1}],'
        '"sets":[{"set_number":1}]}}}',
      )!;

      final workout = decoded.workout('s1')!;
      expect(workout.exercises, isEmpty);
      expect(workout.sets, isEmpty);
      expect(
        decoded.workout('missing'),
        isNull,
        reason:
            'a workout entry whose name does not match its row is still '
            'one workout',
      );
    });

    test('a workout entry without a session id is skipped', () {
      final decoded = ReviewStage.tryDecode(
        '{"stage":1,"workouts":{"s1":{"session":{"name":"Push"}}}}',
      )!;
      expect(decoded.workouts, isEmpty);
    });
  });
}
