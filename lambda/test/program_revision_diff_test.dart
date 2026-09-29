import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_revision.dart';
import 'package:lambda/features/programs/model/program_revision_diff.dart';

RevisionSet _set(
  String id, {
  String? weight = '60',
  String? reps = '5',
  String? variation,
  String? notes,
  int n = 1,
}) =>
    RevisionSet(
      plannedSetId: id,
      plannedExerciseId: 'e',
      plannedSessionId: 's',
      userId: 'u1',
      setNumber: n,
      variationId: variation,
      targetWeight: weight,
      targetReps: reps,
      targetNotes: notes,
    );

RevisionExercise _exercise(
  String id, {
  String exerciseId = 'ex1',
  int order = 1,
  List<RevisionSet>? sets,
}) =>
    RevisionExercise(
      plannedExerciseId: id,
      plannedSessionId: 's',
      userId: 'u1',
      exerciseId: exerciseId,
      exerciseOrder: order,
      sets: sets ?? [_set('${id}set1')],
    );

RevisionSession _session(
  String id, {
  String? name,
  String? notes,
  String? blockId,
  List<RevisionExercise>? exercises,
}) =>
    RevisionSession(
      sessionId: id,
      userId: 'u1',
      name: name ?? id,
      notes: notes,
      blockId: blockId,
      exercises: exercises ?? [_exercise('${id}e1')],
    );

ProgramRevisionContent _content(
  List<RevisionSession> sessions, {
  List<RevisionBlock> blocks = const [],
}) =>
    ProgramRevisionContent(blocks: blocks, sessions: sessions);

void main() {
  group('first version', () {
    test('everything is added and nothing is reported as moved', () {
      final diff = diffRevisions(null, _content([_session('A'), _session('B')]));

      expect(diff.addedCount, 2);
      expect(diff.movedCount, 0);
      expect(diff.removedCount, 0);
      expect(diff.changes.every((c) => c.entity == RevisionEntity.session),
          isTrue);
    });

    test('null on both sides is an empty diff', () {
      expect(diffRevisions(null, null).isEmpty, isTrue);
    });

    test('comparing against null reports everything as removed', () {
      final diff = diffRevisions(_content([_session('A')]), null);
      expect(diff.removedCount, 1);
    });
  });

  group('order changes do not become noise', () {
    test('inserting a workout at the head reports ONE added and NO moves', () {
      // The case that makes version histories unreadable if handled naively:
      // every later workout shifts down by one position.
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after =
          _content([_session('NEW'), _session('A'), _session('B'), _session('C')]);

      final diff = diffRevisions(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 0);
      expect(diff.movedCount, 0);
      expect(diff.changes.single.label, 'NEW');
    });

    test('removing a workout reports ONE removed and NO moves', () {
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('A'), _session('C')]);

      final diff = diffRevisions(before, after);

      expect(diff.removedCount, 1);
      expect(diff.movedCount, 0);
      expect(diff.changes.single.label, 'B');
    });

    test('moving one workout to the front reports ONLY that workout', () {
      // Survivor-position comparison alone would report all three; the LCS is
      // [A,B], so only C actually moved.
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('C'), _session('A'), _session('B')]);

      final diff = diffRevisions(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'C');
      expect(diff.changes.single.kind, RevisionChangeKind.moved);
      expect(diff.changes.single.detail, 'position 3 → 1');
    });

    test('swapping two adjacent workouts reports ONE move, not two', () {
      // A swap is one user action, so it must read as one change. The LCS is
      // [A,C], which leaves exactly B to report. Which side of the swap gets
      // named is inherently ambiguous; the tie-break names the one that moved
      // earlier (B moved up above A).
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('B'), _session('A'), _session('C')]);

      final diff = diffRevisions(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'B');
      expect(diff.changes.single.detail, 'position 2 → 1');
    });

    test('renumbering orders without reordering reports NOTHING', () {
      // Relative order is unchanged, so nothing moved even though every
      // stored sequence number differs.
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('A'), _session('B'), _session('C')]);

      expect(diffRevisions(before, after).isEmpty, isTrue);
    });

    test('no changes at all is an empty diff with a readable summary', () {
      final content = _content([_session('A'), _session('B')]);
      final diff = diffRevisions(content, content);

      expect(diff.isEmpty, isTrue);
      expect(diff.summary, 'no content changes');
    });
  });

  group('workout edits', () {
    test('a rename is one edit, not an add plus a remove', () {
      final before = _content([_session('A', name: 'Push')]);
      final after = _content([_session('A', name: 'Push Day')]);

      final diff = diffRevisions(before, after);

      expect(diff.editedCount, 1);
      expect(diff.addedCount, 0);
      expect(diff.removedCount, 0);
      expect(diff.changes.single.detail, 'renamed: Push → Push Day');
    });

    test('a notes change is one edit', () {
      final before = _content([_session('A', notes: null)]);
      final after = _content([_session('A', notes: 'add a backoff set')]);

      final diff = diffRevisions(before, after);

      expect(diff.editedCount, 1);
      expect(diff.changes.single.detail, 'notes edited');
    });

    test('an unchanged null notes field is not an edit', () {
      final before = _content([_session('A', notes: null)]);
      final after = _content([_session('A', notes: '')]);
      expect(diffRevisions(before, after).isEmpty, isTrue);
    });

    test('moving a workout between blocks names both blocks', () {
      final before = _content([_session('A', blockId: 'b1')]);
      final after = _content([_session('A', blockId: 'b2')]);

      final diff = diffRevisions(
        before,
        after,
        blockNames: {'b1': 'Accumulation', 'b2': 'Intensification'},
      );

      expect(diff.editedCount, 1);
      expect(diff.changes.single.detail,
          'block: Accumulation → Intensification');
    });

    test('an unknown block id never leaks a raw uuid into the UI', () {
      final before = _content([_session('A', blockId: 'b1')]);
      final after = _content([_session('A', blockId: null)]);

      final diff = diffRevisions(before, after);

      expect(diff.changes.single.detail, 'block: a block → no block');
    });
  });

  group('exercise edits', () {
    test('adding an exercise reports one add with its set count', () {
      final before = _content([
        _session('A', exercises: [_exercise('Ae1')])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1'),
          _exercise('Ae2', exerciseId: 'ex2', order: 2, sets: [
            _set('Ae2s1'),
            _set('Ae2s2', n: 2),
          ]),
        ])
      ]);

      final diff = diffRevisions(before, after, exerciseNames: {'ex2': 'Row'});

      final added = diff.changes.single;
      expect(added.kind, RevisionChangeKind.added);
      expect(added.entity, RevisionEntity.exercise);
      expect(added.label, 'Row');
      expect(added.detail, '2 sets');
      expect(added.sessionId, 'A');
    });

    test('swapping the lift is reported as removed + added, never an edit', () {
      // Rendering this as an edit would show a nonsense weight/reps diff
      // between two unrelated exercises.
      final before = _content([
        _session('A', exercises: [_exercise('Ae1', exerciseId: 'ex1')])
      ]);
      final after = _content([
        _session('A', exercises: [_exercise('Ae1', exerciseId: 'ex2')])
      ]);

      final diff = diffRevisions(
        before,
        after,
        exerciseNames: {'ex1': 'Bench Press', 'ex2': 'Incline Press'},
      );

      expect(diff.removedCount, 1);
      expect(diff.addedCount, 1);
      expect(diff.editedCount, 0);
      expect(diff.changes.first.label, 'Bench Press');
      expect(diff.changes.last.label, 'Incline Press');
      expect(diff.changes.last.detail, 'replaced Bench Press');
    });

    test('an exercise with no resolvable name falls back, never a raw id', () {
      final before = _content([_session('A', exercises: [_exercise('Ae1')])]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1'),
          _exercise('Ae2', exerciseId: 'ex-unknown', order: 2),
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.changes.single.label, 'Exercise');
      expect(diff.changes.single.label, isNot(contains('ex-unknown')));
    });

    test('reordering exercises inside a workout reports one move', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', exerciseId: 'ex1', order: 1),
          _exercise('Ae2', exerciseId: 'ex2', order: 2),
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae2', exerciseId: 'ex2', order: 1),
          _exercise('Ae1', exerciseId: 'ex1', order: 2),
        ])
      ]);

      final diff = diffRevisions(
        before,
        after,
        exerciseNames: {'ex1': 'Bench', 'ex2': 'Row'},
      );

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'Row');
    });

    test('removing an exercise reports one removal', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', exerciseId: 'ex1'),
          _exercise('Ae2', exerciseId: 'ex2', order: 2),
        ])
      ]);
      final after = _content([
        _session('A', exercises: [_exercise('Ae1', exerciseId: 'ex1')])
      ]);

      final diff = diffRevisions(before, after, exerciseNames: {'ex2': 'Row'});

      expect(diff.removedCount, 1);
      expect(diff.changes.single.label, 'Row');
    });
  });

  group('set edits', () {
    test('a target change shows before and after', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '60', reps: '5')])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '65', reps: '5')])
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.editedCount, 1);
      expect(diff.changes.single.entity, RevisionEntity.set);
      expect(diff.changes.single.label, 'Set 1');
      expect(diff.changes.single.detail, '60 × 5 → 65 × 5');
    });

    test('free-text targets compare as text, not numbers', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '60-70', reps: 'AMRAP')])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '65-75', reps: 'AMRAP')])
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.changes.single.detail, '60-70 × AMRAP → 65-75 × AMRAP');
    });

    test('adding a set reports one add carrying its target', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1')])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [
            _set('Ae1s1'),
            _set('Ae1s2', weight: '70', reps: '3', n: 2),
          ])
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.addedCount, 1);
      expect(diff.movedCount, 0);
      expect(diff.changes.single.label, 'Set 2');
      expect(diff.changes.single.detail, '70 × 3');
    });

    test('removing a set reports one removal with what was lost', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [
            _set('Ae1s1'),
            _set('Ae1s2', weight: '70', reps: '3', n: 2),
          ])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1')])
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.removedCount, 1);
      expect(diff.changes.single.detail, '70 × 3');
    });

    test('a variation change is its own edit', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', variation: null)])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', variation: 'v1')])
        ])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.editedCount, 1);
      expect(diff.changes.single.detail, 'variation changed');
    });

    test('set changes carry their workout and exercise context', () {
      final before = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '60')])
        ])
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1s1', weight: '65')])
        ])
      ]);

      final diff = diffRevisions(before, after, exerciseNames: {'ex1': 'Bench'});

      final change = diff.changes.single;
      expect(change.sessionId, 'A');
      expect(change.sessionName, 'A');
      expect(change.exerciseId, 'ex1');
      expect(change.exerciseName, 'Bench');
    });
  });

  group('blocks', () {
    test('a block is added, renamed and removed', () {
      final before = _content(const [], blocks: const [
        RevisionBlock(blockId: 'b1', name: 'Accumulation', blockOrder: 1),
        RevisionBlock(blockId: 'b2', name: 'Peaking', blockOrder: 2),
      ]);
      final after = _content(const [], blocks: const [
        RevisionBlock(blockId: 'b1', name: 'Base', blockOrder: 1),
        RevisionBlock(blockId: 'b3', name: 'Deload', blockOrder: 2),
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
      expect(diff.editedCount, 1);
      expect(diff.changes.first.label, 'Base');
      expect(diff.changes.first.detail, 'renamed: Accumulation → Base');
      expect(diff.changes.last.label, 'Peaking');
    });

    test('reordering blocks reports only the block that moved', () {
      final before = _content(const [], blocks: const [
        RevisionBlock(blockId: 'b1', name: 'Base', blockOrder: 1),
        RevisionBlock(blockId: 'b2', name: 'Build', blockOrder: 2),
        RevisionBlock(blockId: 'b3', name: 'Peak', blockOrder: 3),
      ]);
      final after = _content(const [], blocks: const [
        RevisionBlock(blockId: 'b3', name: 'Peak', blockOrder: 1),
        RevisionBlock(blockId: 'b1', name: 'Base', blockOrder: 2),
        RevisionBlock(blockId: 'b2', name: 'Build', blockOrder: 3),
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'Peak');
    });

    test('a target change is reported', () {
      final before = _content(const [], blocks: const [
        RevisionBlock(
            blockId: 'b1', name: 'Base', blockOrder: 1, targetWeeks: 4),
      ]);
      final after = _content(const [], blocks: const [
        RevisionBlock(
            blockId: 'b1', name: 'Base', blockOrder: 1, targetWeeks: 6),
      ]);

      expect(diffRevisions(before, after).changes.single.detail,
          'targets changed');
    });

    test('a days-only change is a target change too', () {
      // Same weeks, one more day. A comparison that looked at the week count
      // alone would call these two revisions identical — a block that gained a
      // day is a block whose phase runs a day longer, which is exactly the kind
      // of change a revision diff exists to show.
      final before = _content(const [], blocks: const [
        RevisionBlock(
          blockId: 'b1',
          name: 'Base',
          blockOrder: 1,
          targetWeeks: 8,
          targetDays: 3,
        ),
      ]);
      final after = _content(const [], blocks: const [
        RevisionBlock(
          blockId: 'b1',
          name: 'Base',
          blockOrder: 1,
          targetWeeks: 8,
          targetDays: 4,
        ),
      ]);

      expect(diffRevisions(before, after).changes.single.detail,
          'targets changed');
    });
  });

  group('ordering and grouping guarantees', () {
    test('changes for one workout stay adjacent to it', () {
      final before = _content([
        _session('A', exercises: [_exercise('Ae1')]),
        _session('B', exercises: [_exercise('Be1')]),
      ]);
      final after = _content([
        _session('A', exercises: [
          _exercise('Ae1', sets: [_set('Ae1set1', weight: '99')]),
        ]),
        _session('B', exercises: [_exercise('Be1')]),
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.changes, hasLength(1));
      expect(diff.forSession('A'), hasLength(1));
      expect(diff.forSession('B'), isEmpty);
    });

    test('a combined edit produces one line per distinct fact', () {
      final before = _content([
        _session('A', name: 'Push', exercises: [_exercise('Ae1')])
      ]);
      final after = _content([
        _session('A', name: 'Push Day', exercises: [_exercise('Ae1')])
      ]);

      final diff = diffRevisions(before, after);

      expect(diff.changes, hasLength(1));
      expect(diff.summary, '~1');
    });

    test('summary counts each kind', () {
      final before = _content([_session('A'), _session('B')]);
      final after = _content([_session('NEW'), _session('A')]);

      final diff = diffRevisions(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
      expect(diff.summary, '+1 −1');
    });
  });
}
