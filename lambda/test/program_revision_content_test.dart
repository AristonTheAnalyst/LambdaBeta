import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_revision.dart';

RevisionSet _set(
  String id, {
  String? weight,
  String? reps,
  String? variation,
  String? notes,
  int n = 1,
}) =>
    RevisionSet(
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
RevisionSet _withParent(RevisionSet s, String exerciseId) => RevisionSet(
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

RevisionExercise _exercise(
  String id, {
  String? exerciseId = 'ex1',
  int order = 1,
  List<RevisionSet>? sets,
}) =>
    RevisionExercise(
      plannedExerciseId: id,
      plannedSessionId: 's1',
      userId: 'u1',
      exerciseId: exerciseId,
      exerciseOrder: order,
      sets: (sets ?? [_set('${id}set1', weight: '60', reps: '5')])
          .map((s) => _withParent(s, id))
          .toList(),
    );

RevisionSession _session(
  String id, {
  String name = 'Push',
  String? notes,
  int? sequenceOrder = 1,
  String? blockId,
  List<RevisionExercise>? exercises,
}) =>
    RevisionSession(
      sessionId: id,
      userId: 'u1',
      name: name,
      notes: notes,
      sequenceOrder: sequenceOrder,
      blockId: blockId,
      exercises: exercises ?? [_exercise('${id}e1')],
    );

ProgramRevisionContent _sample() => ProgramRevisionContent(
      blocks: const [
        RevisionBlock(
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
  group('ProgramRevisionContent round-trip', () {
    test('encode → decode preserves every field', () {
      final original = _sample();
      final decoded = ProgramRevisionContent.decode(original.encode());

      expect(decoded.schema, ProgramRevisionContent.currentSchema);
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
    });

    test('counts match the captured content', () {
      final content = _sample();
      expect(content.sessionCount, 2);
      expect(content.exerciseCount, 3); // 2 in s1, 1 in s2
      expect(content.setCount, 4); // 2 in s1e1, 1 in s1e2, 1 in s2e1
    });

    test('an empty program round-trips', () {
      const empty = ProgramRevisionContent();
      final decoded = ProgramRevisionContent.decode(empty.encode());
      expect(decoded.isEmpty, isTrue);
      expect(decoded.sessionCount, 0);
      expect(decoded.contentHash, empty.contentHash);
    });

    test('session order is preserved — it IS the program order', () {
      final decoded = ProgramRevisionContent.decode(_sample().encode());
      expect(decoded.sessions.map((s) => s.sessionId).toList(), ['s1', 's2']);
    });
  });

  group('content hash', () {
    test('is stable when key order differs', () {
      final original = _sample();
      // Same content, every map's keys emitted in reverse order.
      final scrambled = jsonEncode(_reverseKeys(jsonDecode(original.encode())));
      expect(scrambled, isNot(equals(original.encode())));

      final decoded = ProgramRevisionContent.decode(scrambled);
      expect(decoded.contentHash, original.contentHash);
    });

    test('is stable across repeated encodes', () {
      final content = _sample();
      expect(content.contentHash, content.contentHash);
      expect(content.encode(), content.encode());
    });

    test('changes when a single target changes', () {
      final before = _sample();
      final after = ProgramRevisionContent(
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
      final reordered = ProgramRevisionContent(
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
        () => ProgramRevisionContent.decode(
            '{"schema": ${ProgramRevisionContent.currentSchema + 1}, '
            '"sessions": []}'),
        throwsFormatException,
      );
    });

    test('a missing schema throws', () {
      expect(
        () => ProgramRevisionContent.decode('{"sessions": []}'),
        throwsFormatException,
      );
    });

    test('non-object JSON throws', () {
      expect(
        () => ProgramRevisionContent.decode('[1, 2, 3]'),
        throwsFormatException,
      );
    });

    test('malformed JSON throws', () {
      expect(
        () => ProgramRevisionContent.decode('{not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a newer schema surfaces as null content instead of crashing', () {
      final revision = ProgramRevision(
        revisionId: 'r1',
        userId: 'u1',
        programId: 'p1',
        revisionNumber: 1,
        reason: kRevisionCreated,
        contentJson: '{"schema": 999}',
        contentHash: 'x',
        createdDate: DateTime(2026, 9, 1),
      );
      expect(revision.content, isNull);
    });
  });

  group('map adapters produce real models', () {
    test('RevisionSession.toSession matches the shared model', () {
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

    test('RevisionExercise.toExercise matches the shared model', () {
      final exercise = _sample().sessions.first.exercises.first;
      final model = exercise.toExercise();

      expect(model.plannedExerciseId, 's1e1');
      expect(model.plannedSessionId, 's1');
      expect(model.exerciseId, 'ex1');
      expect(model.exerciseOrder, 1);
      expect(model.isArchived, isFalse);
    });

    test('RevisionSet.toSet matches the shared model', () {
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

    test('legacy numeric targets normalize the way the planner shows them', () {
      // Values written before the free-text change (see
      // PlannedSessionExerciseSet._toTargetText).
      const legacy = RevisionSet(
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
