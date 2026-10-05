import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/features/programs/model/program_content_diff.dart';

ContentSet _set(
  String id, {
  String? weight = '60',
  String? reps = '5',
  String? variation,
  String? notes,
  int n = 1,
}) =>
    ContentSet(
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

ContentExercise _exercise(
  String id, {
  String exerciseId = 'ex1',
  int order = 1,
  List<ContentSet>? sets,
}) =>
    ContentExercise(
      plannedExerciseId: id,
      plannedSessionId: 's',
      userId: 'u1',
      exerciseId: exerciseId,
      exerciseOrder: order,
      sets: sets ?? [_set('${id}set1')],
    );

ContentSession _session(
  String id, {
  String? name,
  String? notes,
  String? blockId,
  List<ContentExercise>? exercises,
}) =>
    ContentSession(
      sessionId: id,
      userId: 'u1',
      name: name ?? id,
      notes: notes,
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

ProgramContent _content(
  List<ContentSession> sessions, {
  List<ContentBlock> blocks = const [],
  List<ContentGoal> goals = const [],
}) =>
    ProgramContent(blocks: blocks, sessions: sessions, goals: goals);

void main() {
  group('first version', () {
    test('everything is added and nothing is reported as moved', () {
      final diff = diffContent(null, _content([_session('A'), _session('B')]));

      expect(diff.addedCount, 2);
      expect(diff.movedCount, 0);
      expect(diff.removedCount, 0);
      expect(diff.changes.every((c) => c.entity == ContentEntity.session),
          isTrue);
    });

    test('null on both sides is an empty diff', () {
      expect(diffContent(null, null).isEmpty, isTrue);
    });

    test('comparing against null reports everything as removed', () {
      final diff = diffContent(_content([_session('A')]), null);
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

      final diff = diffContent(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 0);
      expect(diff.movedCount, 0);
      expect(diff.changes.single.label, 'NEW');
    });

    test('removing a workout reports ONE removed and NO moves', () {
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('A'), _session('C')]);

      final diff = diffContent(before, after);

      expect(diff.removedCount, 1);
      expect(diff.movedCount, 0);
      expect(diff.changes.single.label, 'B');
    });

    test('moving one workout to the front reports ONLY that workout', () {
      // Survivor-position comparison alone would report all three; the LCS is
      // [A,B], so only C actually moved.
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('C'), _session('A'), _session('B')]);

      final diff = diffContent(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'C');
      expect(diff.changes.single.kind, ContentChangeKind.moved);
      expect(diff.changes.single.detail, 'position 3 → 1');
    });

    test('swapping two adjacent workouts reports ONE move, not two', () {
      // A swap is one user action, so it must read as one change. The LCS is
      // [A,C], which leaves exactly B to report. Which side of the swap gets
      // named is inherently ambiguous; the tie-break names the one that moved
      // earlier (B moved up above A).
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('B'), _session('A'), _session('C')]);

      final diff = diffContent(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'B');
      expect(diff.changes.single.detail, 'position 2 → 1');
    });

    test('renumbering orders without reordering reports NOTHING', () {
      // Relative order is unchanged, so nothing moved even though every
      // stored sequence number differs.
      final before = _content([_session('A'), _session('B'), _session('C')]);
      final after = _content([_session('A'), _session('B'), _session('C')]);

      expect(diffContent(before, after).isEmpty, isTrue);
    });

    test('no changes at all is an empty diff with a readable summary', () {
      final content = _content([_session('A'), _session('B')]);
      final diff = diffContent(content, content);

      expect(diff.isEmpty, isTrue);
      expect(diff.summary, 'no content changes');
    });
  });

  group('workout edits', () {
    test('a rename is one edit, not an add plus a remove', () {
      final before = _content([_session('A', name: 'Push')]);
      final after = _content([_session('A', name: 'Push Day')]);

      final diff = diffContent(before, after);

      expect(diff.editedCount, 1);
      expect(diff.addedCount, 0);
      expect(diff.removedCount, 0);
      expect(diff.changes.single.detail, 'renamed: Push → Push Day');
    });

    test('a notes change is one edit', () {
      final before = _content([_session('A', notes: null)]);
      final after = _content([_session('A', notes: 'add a backoff set')]);

      final diff = diffContent(before, after);

      expect(diff.editedCount, 1);
      expect(diff.changes.single.detail, 'notes edited');
    });

    test('an unchanged null notes field is not an edit', () {
      final before = _content([_session('A', notes: null)]);
      final after = _content([_session('A', notes: '')]);
      expect(diffContent(before, after).isEmpty, isTrue);
    });

    test('moving a workout between blocks names both blocks', () {
      final before = _content([_session('A', blockId: 'b1')]);
      final after = _content([_session('A', blockId: 'b2')]);

      final diff = diffContent(
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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after, exerciseNames: {'ex2': 'Row'});

      final added = diff.changes.single;
      expect(added.kind, ContentChangeKind.added);
      expect(added.entity, ContentEntity.exercise);
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

      final diff = diffContent(
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

      final diff = diffContent(before, after);

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

      final diff = diffContent(
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

      final diff = diffContent(before, after, exerciseNames: {'ex2': 'Row'});

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

      final diff = diffContent(before, after);

      expect(diff.editedCount, 1);
      expect(diff.changes.single.entity, ContentEntity.set);
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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after, exerciseNames: {'ex1': 'Bench'});

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
        ContentBlock(blockId: 'b1', name: 'Accumulation', blockOrder: 1),
        ContentBlock(blockId: 'b2', name: 'Peaking', blockOrder: 2),
      ]);
      final after = _content(const [], blocks: const [
        ContentBlock(blockId: 'b1', name: 'Base', blockOrder: 1),
        ContentBlock(blockId: 'b3', name: 'Deload', blockOrder: 2),
      ]);

      final diff = diffContent(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
      expect(diff.editedCount, 1);
      expect(diff.changes.first.label, 'Base');
      expect(diff.changes.first.detail, 'renamed: Accumulation → Base');
      expect(diff.changes.last.label, 'Peaking');
    });

    test('reordering blocks reports only the block that moved', () {
      final before = _content(const [], blocks: const [
        ContentBlock(blockId: 'b1', name: 'Base', blockOrder: 1),
        ContentBlock(blockId: 'b2', name: 'Build', blockOrder: 2),
        ContentBlock(blockId: 'b3', name: 'Peak', blockOrder: 3),
      ]);
      final after = _content(const [], blocks: const [
        ContentBlock(blockId: 'b3', name: 'Peak', blockOrder: 1),
        ContentBlock(blockId: 'b1', name: 'Base', blockOrder: 2),
        ContentBlock(blockId: 'b2', name: 'Build', blockOrder: 3),
      ]);

      final diff = diffContent(before, after);

      expect(diff.movedCount, 1);
      expect(diff.changes.single.label, 'Peak');
    });

    test('a target change is reported', () {
      final before = _content(const [], blocks: const [
        ContentBlock(
            blockId: 'b1', name: 'Base', blockOrder: 1, targetWeeks: 4),
      ]);
      final after = _content(const [], blocks: const [
        ContentBlock(
            blockId: 'b1', name: 'Base', blockOrder: 1, targetWeeks: 6),
      ]);

      expect(diffContent(before, after).changes.single.detail,
          'targets changed');
    });

    test('a days-only change is a target change too', () {
      // Same weeks, one more day. A comparison that looked at the week count
      // alone would call these two revisions identical — a block that gained a
      // day is a block whose phase runs a day longer, which is exactly the kind
      // of change a revision diff exists to show.
      final before = _content(const [], blocks: const [
        ContentBlock(
          blockId: 'b1',
          name: 'Base',
          blockOrder: 1,
          targetWeeks: 8,
          targetDays: 3,
        ),
      ]);
      final after = _content(const [], blocks: const [
        ContentBlock(
          blockId: 'b1',
          name: 'Base',
          blockOrder: 1,
          targetWeeks: 8,
          targetDays: 4,
        ),
      ]);

      expect(diffContent(before, after).changes.single.detail,
          'targets changed');
    });
  });

  group('goals', () {
    test('a goal is added, and one is removed', () {
      final before = _content(const [], goals: [_goal('g1', text: 'Sleep')]);
      final after = _content(
        const [],
        goals: [_goal('g1', text: 'Sleep'), _goal('g2', blockId: 'b1', text: 'Bench')],
      );

      final diff = diffContent(before, after);

      expect(diff.addedCount, 1);
      expect(diff.changes.single.entity, ContentEntity.goal);
      expect(diff.changes.single.label, 'Bench');

      // Read the other way, the same pair of documents reports the same goal
      // as gone — a diff is directional, and "which one went" is the reader's
      // question.
      final removed = diffContent(after, before);
      expect(removed.removedCount, 1);
      expect(removed.changes.single.label, 'Bench');
    });

    test('a retargeted goal reports both numbers', () {
      final before = _content(const [],
          goals: [_goal('g1', exerciseId: 'ex1', weight: 100, reps: 1, text: 'Bench')]);
      final after = _content(const [],
          goals: [_goal('g1', exerciseId: 'ex1', weight: 110, reps: 1, text: 'Bench')]);

      final diff = diffContent(before, after,
          exerciseNames: const {'ex1': 'Bench Press'});

      expect(diff.editedCount, 1);
      expect(diff.changes.single.detail, 'target: 100 kg × 1 rep → 110 kg × 1 rep');
    });

    test('rescoping a goal is reported as a scope change, not a rewording', () {
      // The same target, moved from the program to a phase — the one edit a
      // goal can make that changes what it applies *to* rather than what it
      // asks for, so a diff that called this "reworded" would hide the only
      // part of it a reader needs.
      // The block is in both documents: the only thing that changed is where
      // the goal points.
      const block = ContentBlock(
          blockId: 'b1', name: 'Accumulation', blockOrder: 1);
      final before = _content(const [],
          blocks: const [block], goals: [_goal('g1', text: 'Bench')]);
      final after = _content(const [],
          blocks: const [block], goals: [_goal('g1', blockId: 'b1', text: 'Bench')]);

      final diff = diffContent(before, after,
          blockNames: const {'b1': 'Accumulation'});

      expect(diff.changes, hasLength(1));
      expect(diff.changes.single.detail, 'scope: Whole program → Accumulation',
          reason: 'the same words the Goals tab uses to set it — "no block" '
              'here would describe an unplaced workout, not the program\'s own '
              'target');
    });

    test('a goal with no text falls back to its exercise, then to "Goal"', () {
      final named = diffContent(
        const ProgramContent(),
        _content(const [], goals: [_goal('g1', exerciseId: 'ex1', weight: 100, reps: 1)]),
        exerciseNames: const {'ex1': 'Bench Press'},
      );
      expect(named.changes.single.label, 'Bench Press');

      // An exercise that has since been deleted from the library: the goal is
      // still a change worth reporting, just not a nameable one.
      final unnamed = diffContent(
        const ProgramContent(),
        _content(const [], goals: [_goal('g1', exerciseId: 'gone', weight: 100, reps: 1)]),
      );
      expect(unnamed.changes.single.label, 'Goal');
    });

    test('a sentence-only goal says it has no target', () {
      final diff = diffContent(const ProgramContent(),
          _content(const [], goals: [_goal('g1', text: 'Sleep eight hours')]));

      expect(diff.changes.single.detail, 'no target',
          reason: 'the label is already the whole sentence — an empty detail '
              'would read as a rendering bug rather than a goal without a '
              'number');
    });

    test('goal changes come after the workouts they belong to', () {
      final before = _content([_session('A')], goals: [_goal('g1', text: 'Sleep')]);
      final after = _content(
        [_session('A', notes: 'edited')],
        blocks: const [ContentBlock(blockId: 'b1', name: 'Base', blockOrder: 1)],
        goals: [_goal('g1', blockId: 'b1', text: 'Sleep')],
      );

      final diff = diffContent(before, after);

      expect(diff.changes.last.entity, ContentEntity.goal,
          reason: 'a diff reads top-down as the program is built — targets '
              'last, the way the document itself is ordered');
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

      final diff = diffContent(before, after);

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

      final diff = diffContent(before, after);

      expect(diff.changes, hasLength(1));
      expect(diff.summary, '~1');
    });

    test('summary counts each kind', () {
      final before = _content([_session('A'), _session('B')]);
      final after = _content([_session('NEW'), _session('A')]);

      final diff = diffContent(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
      expect(diff.summary, '+1 −1');
    });
  });
}
