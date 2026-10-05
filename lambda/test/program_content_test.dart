import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_content.dart';

ContentSet _set(
  String id, {
  String? weight,
  String? reps,
  String? variation,
  String? notes,
  int n = 1,
}) =>
    ContentSet(
      plannedSetId: id,
      plannedExerciseId: 'e1',
      plannedSessionId: 's1',
      userId: 'u1',
      setNumber: n,
      variationId: variation,
      targetWeight: weight,
      targetReps: reps,
      targetNotes: notes,
    );

/// Re-parents a set fixture onto [exerciseId], so a fixture stays internally
/// consistent however the set was constructed.
ContentSet _withParent(ContentSet s, String exerciseId) => ContentSet(
      plannedSetId: s.plannedSetId,
      plannedExerciseId: exerciseId,
      plannedSessionId: s.plannedSessionId,
      userId: s.userId,
      variationId: s.variationId,
      setNumber: s.setNumber,
      targetWeight: s.targetWeight,
      targetReps: s.targetReps,
      targetNotes: s.targetNotes,
    );

ContentExercise _exercise(
  String id, {
  String? exerciseId = 'ex1',
  int order = 1,
  List<ContentSet>? sets,
}) =>
    ContentExercise(
      plannedExerciseId: id,
      plannedSessionId: 's1',
      userId: 'u1',
      exerciseId: exerciseId,
      exerciseOrder: order,
      sets: (sets ?? [_set('${id}set1', weight: '60', reps: '5')])
          .map((s) => _withParent(s, id))
          .toList(),
    );

ContentSession _session(
  String id, {
  String name = 'Push',
  String? notes,
  int? sequenceOrder = 1,
  String? blockId,
  List<ContentExercise>? exercises,
}) =>
    ContentSession(
      sessionId: id,
      userId: 'u1',
      name: name,
      notes: notes,
      sequenceOrder: sequenceOrder,
      blockId: blockId,
      exercises: exercises ?? [_exercise('${id}e1')],
    );

ContentGoal _goal(
  String id, {
  String? blockId,
  String? exerciseId,
  String? variationId,
  num? weight,
  int? reps,
  String? text,
}) =>
    ContentGoal(
      goalId: id,
      userId: 'u1',
      blockId: blockId,
      exerciseId: exerciseId,
      variationId: variationId,
      targetWeight: weight,
      targetReps: reps,
      text: text,
    );

ProgramContent _sample() => ProgramContent(
      blocks: const [
        ContentBlock(
          blockId: 'b1',
          name: 'Accumulation',
          blockOrder: 1,
          targetWeeks: 4,
          targetSessions: 16,
        ),
      ],
      sessions: [
        _session('s1', notes: 'chest focus', blockId: 'b1', exercises: [
          _exercise('s1e1', sets: [
            _set('s1e1set1', weight: '60', reps: '5', variation: 'v1'),
            _set('s1e1set2', weight: '60', reps: '5', n: 2, notes: 'backoff'),
          ]),
          _exercise('s1e2', exerciseId: 'ex2', order: 2),
        ]),
        _session('s2', name: 'Pull', sequenceOrder: 2),
      ],
      // One per scope: the program's own (in force through every block) and
      // the phase's, which is the pair a review has to tell apart.
      goals: [
        _goal('g1',
            exerciseId: 'ex1', variationId: 'v1', weight: 100, reps: 1,
            text: 'Bench'),
        _goal('g2', blockId: 'b1', text: 'Sleep eight hours'),
      ],
    );

/// Reverses key order at every level, so a document with identical content but
/// different serialization order can be produced.
dynamic _reverseKeys(dynamic v) {
  if (v is Map) {
    final entries = v.entries.toList().reversed;
    return {for (final e in entries) '${e.key}': _reverseKeys(e.value)};
  }
  if (v is List) return v.map(_reverseKeys).toList();
  return v;
}

void main() {
  group('ProgramContent round-trip', () {
    test('encode → decode preserves every field', () {
      final original = _sample();
      final decoded = ProgramContent.decode(original.encode());

      expect(decoded.schema, ProgramContent.currentSchema);
      expect(decoded.blocks, hasLength(1));
      expect(decoded.blocks.first.blockId, 'b1');
      expect(decoded.blocks.first.name, 'Accumulation');
      expect(decoded.blocks.first.targetWeeks, 4);
      expect(decoded.blocks.first.targetSessions, 16);

      expect(decoded.sessions, hasLength(2));
      final s1 = decoded.sessions.first;
      expect(s1.sessionId, 's1');
      expect(s1.name, 'Push');
      expect(s1.notes, 'chest focus');
      expect(s1.sequenceOrder, 1);
      expect(s1.blockId, 'b1');

      expect(s1.exercises, hasLength(2));
      expect(s1.exercises.first.exerciseId, 'ex1');
      expect(s1.exercises.first.sets, hasLength(2));
      expect(s1.exercises.first.sets.first.targetWeight, '60');
      expect(s1.exercises.first.sets.first.variationId, 'v1');
      expect(s1.exercises.first.sets[1].targetNotes, 'backoff');
      expect(s1.exercises[1].exerciseId, 'ex2');
      expect(s1.exercises[1].exerciseOrder, 2);

      expect(decoded.goals, hasLength(2));
      final programGoal = decoded.goals.first;
      expect(programGoal.goalId, 'g1');
      expect(programGoal.blockId, isNull,
          reason: 'a program-level goal is in force in every block — that is '
              'the scope, and storing it as null is how it stays so');
      expect(programGoal.exerciseId, 'ex1');
      expect(programGoal.variationId, 'v1');
      expect(programGoal.targetWeight, 100);
      expect(programGoal.targetReps, 1);
      expect(programGoal.text, 'Bench');

      expect(decoded.goals[1].blockId, 'b1');
      expect(decoded.goals[1].targetWeight, isNull);
      expect(decoded.goals[1].text, 'Sleep eight hours');
    });

    test('a document written before goals existed still decodes', () {
      // The whole risk of the schema bump: these rows are already stored, and
      // a reader that choked on them would take the review history with it.
      // Schema 1 had no `goals` key at all — so decoding is a matter of the
      // key being absent rather than null.
      final v1 = jsonEncode({
        'schema': 1,
        'blocks': [
          {
            'block_id': 'b1',
            'name': 'Accumulation',
            'block_order': 1,
            'target_weeks': 4,
          },
        ],
        'sessions': [
          {
            'session_id': 's1',
            'user_id': 'u1',
            'name': 'Push',
            'link': {'sequence_order': 1, 'block_id': 'b1'},
            'exercises': const [],
          },
        ],
      });

      final decoded = ProgramContent.decode(v1);

      expect(decoded.schema, 1, reason: 'the document says what it is');
      expect(decoded.goals, isEmpty,
          reason: 'it held no goals — not "it held unknown goals"');
      expect(decoded.blocks.single.name, 'Accumulation');
      expect(decoded.sessions.single.name, 'Push');
      expect(decoded.sessions.single.blockId, 'b1');
    });

    test('a document from a newer schema still refuses to decode', () {
      final future = jsonEncode({
        'schema': ProgramContent.currentSchema + 1,
        'blocks': const [],
        'sessions': const [],
        'goals': const [],
      });

      expect(() => ProgramContent.decode(future), throwsFormatException,
          reason: 'tolerating an older document is not the same as guessing '
              'at a newer one — an unknown shape renders as missing content, '
              'never as wrong content');
    });

    test('counts match the captured content', () {
      final content = _sample();
      expect(content.sessionCount, 2);
      expect(content.exerciseCount, 3); // 2 in s1, 1 in s2
      expect(content.setCount, 4); // 2 in s1e1, 1 in s1e2, 1 in s2e1
    });

    test('an empty program round-trips', () {
      const empty = ProgramContent();
      final decoded = ProgramContent.decode(empty.encode());
      expect(decoded.isEmpty, isTrue);
      expect(decoded.sessionCount, 0);
      expect(decoded.contentHash, empty.contentHash);
    });

    test('session order is preserved — it IS the program order', () {
      final decoded = ProgramContent.decode(_sample().encode());
      expect(decoded.sessions.map((s) => s.sessionId).toList(), ['s1', 's2']);
    });
  });

  group('content hash', () {
    test('is stable when key order differs', () {
      final original = _sample();
      // Same content, every map's keys emitted in reverse order.
      final scrambled = jsonEncode(_reverseKeys(jsonDecode(original.encode())));
      expect(scrambled, isNot(equals(original.encode())));

      final decoded = ProgramContent.decode(scrambled);
      expect(decoded.contentHash, original.contentHash);
    });

    test('is stable across repeated encodes', () {
      final content = _sample();
      expect(content.contentHash, content.contentHash);
      expect(content.encode(), content.encode());
    });

    test('changes when a single target changes', () {
      final before = _sample();
      final after = ProgramContent(
        blocks: before.blocks,
        sessions: [
          _session('s1', notes: 'chest focus', blockId: 'b1', exercises: [
            _exercise('s1e1', sets: [
              _set('s1e1set1', weight: '65', reps: '5', variation: 'v1'),
              _set('s1e1set2', weight: '60', reps: '5', n: 2, notes: 'backoff'),
            ]),
            _exercise('s1e2', exerciseId: 'ex2', order: 2),
          ]),
          _session('s2', name: 'Pull', sequenceOrder: 2),
        ],
      );
      expect(after.contentHash, isNot(before.contentHash));
    });

    test('changes when only the order changes', () {
      final before = _sample();
      final reordered = ProgramContent(
        blocks: before.blocks,
        sessions: before.sessions.reversed.toList(),
      );
      expect(reordered.contentHash, isNot(before.contentHash));
    });

    test('shortHash is the first 8 hex chars of the content hash', () {
      final content = _sample();
      expect(content.contentHash, hasLength(64));
      expect(content.shortHash, content.contentHash.substring(0, 8));
    });
  });

  group('decode rejects what it cannot understand', () {
    test('an unknown schema throws rather than guessing', () {
      expect(
        () => ProgramContent.decode(
            '{"schema": ${ProgramContent.currentSchema + 1}, '
            '"sessions": []}'),
        throwsFormatException,
      );
    });

    test('a missing schema throws', () {
      expect(
        () => ProgramContent.decode('{"sessions": []}'),
        throwsFormatException,
      );
    });

    test('non-object JSON throws', () {
      expect(
        () => ProgramContent.decode('[1, 2, 3]'),
        throwsFormatException,
      );
    });

    test('malformed JSON throws', () {
      expect(
        () => ProgramContent.decode('{not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('map adapters produce real models', () {
    test('ContentSession.toSession matches the shared model', () {
      final session = _sample().sessions.first;
      final model = session.toSession();

      expect(model.sessionId, 's1');
      expect(model.userId, 'u1');
      expect(model.name, 'Push');
      expect(model.notes, 'chest focus');
      // Snapshots capture active rows only, so archive columns are omitted —
      // the model must read that as "active", not throw.
      expect(model.isArchived, isFalse);
    });

    test('ContentExercise.toExercise matches the shared model', () {
      final exercise = _sample().sessions.first.exercises.first;
      final model = exercise.toExercise();

      expect(model.plannedExerciseId, 's1e1');
      expect(model.plannedSessionId, 's1');
      expect(model.exerciseId, 'ex1');
      expect(model.exerciseOrder, 1);
      expect(model.isArchived, isFalse);
    });

    test('ContentSet.toSet matches the shared model', () {
      final set = _sample().sessions.first.exercises.first.sets.first;
      final model = set.toSet();

      expect(model.plannedSetId, 's1e1set1');
      expect(model.plannedExerciseId, 's1e1');
      expect(model.variationId, 'v1');
      expect(model.setNumber, 1);
      expect(model.targetWeight, '60');
      expect(model.targetReps, '5');
      expect(model.isArchived, isFalse);
    });

    test('ContentGoal.toGoal matches the shared model, scope included', () {
      final goal = _sample().goals.last;
      final model = goal.toGoal(programId: 'p1');

      expect(model.goalId, 'g2');
      expect(model.userId, 'u1');
      expect(model.programId, 'p1');
      expect(model.blockId, 'b1');
      expect(model.text, 'Sleep eight hours');
      // The scope survives as a scope: the review asks `appliesDuring` of the
      // row it renders, so a goal flattened to "in force" at capture time
      // would answer for a run the snapshot never knew about.
      expect(model.appliesDuring('b1'), isTrue);
      expect(model.appliesDuring('b2'), isFalse);
    });

    test('legacy numeric targets normalize the way the planner shows them', () {
      // Values written before the free-text change (see
      // PlannedSessionExerciseSet._toTargetText).
      const legacy = ContentSet(
        plannedSetId: 'x',
        plannedExerciseId: 'e',
        plannedSessionId: 's',
        userId: 'u',
        setNumber: 1,
        targetWeight: '60.0',
        targetReps: '[8,10]',
      );
      final model = legacy.toSet();
      expect(model.targetWeight, '60');
      expect(model.targetReps, '8,10');
    });
  });
}
