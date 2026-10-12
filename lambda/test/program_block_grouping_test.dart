import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/features/programs/model/block_grouping.dart';

/// Pure grouping logic — no PowerSync, so it runs on the host.
void main() {
  group('groupWorkoutsByBlock', () {
    test('a program with no blocks is one unassigned group', () {
      final groups = groupWorkoutsByBlock(
        blocks: const [],
        workouts: [_workout('w1'), _workout('w2')],
        links: [_link('w1'), _link('w2')],
      );

      expect(groups.length, 1);
      expect(groups.single.isUnassigned, isTrue);
      expect(groups.single.workouts.map((w) => w.sessionId), ['w1', 'w2']);
    });

    test('workouts nest under their block, unassigned last', () {
      final groups = groupWorkoutsByBlock(
        blocks: [_block('b1', 'Accumulation', 1), _block('b2', 'Peak', 2)],
        workouts: [_workout('w1'), _workout('w2'), _workout('w3')],
        links: [
          _link('w1', blockId: 'b1'),
          _link('w2', blockId: 'b2'),
          _link('w3'),
        ],
      );

      expect(groups.length, 3);
      expect(groups[0].block!.blockId, 'b1');
      expect(groups[0].workouts.map((w) => w.sessionId), ['w1']);
      expect(groups[1].block!.blockId, 'b2');
      expect(groups[1].workouts.map((w) => w.sessionId), ['w2']);
      expect(groups[2].isUnassigned, isTrue);
      expect(groups[2].workouts.map((w) => w.sessionId), ['w3']);
    });

    test('an empty block still gets a section, a full program has no '
        'unassigned group', () {
      final groups = groupWorkoutsByBlock(
        blocks: [_block('b1', 'Accumulation', 1), _block('b2', 'Peak', 2)],
        workouts: [_workout('w1')],
        links: [_link('w1', blockId: 'b1')],
      );

      expect(groups.length, 2, reason: 'no unassigned section to show');
      expect(groups[0].workouts.length, 1);
      expect(groups[1].block!.blockId, 'b2');
      expect(groups[1].workouts, isEmpty,
          reason: 'an empty block must still render, or it cannot be filled');
    });

    test('a link naming a block this list does not hold reads as unassigned',
        () {
      final groups = groupWorkoutsByBlock(
        blocks: [_block('b1', 'Accumulation', 1)],
        workouts: [_workout('w1'), _workout('w2')],
        links: [_link('w1', blockId: 'b1'), _link('w2', blockId: 'archived')],
      );

      expect(groups.length, 2);
      expect(groups[1].isUnassigned, isTrue);
      expect(groups[1].workouts.map((w) => w.sessionId), ['w2'],
          reason: 'a workout must never vanish because its block did');
    });

    test('order within a group follows the incoming order', () {
      final groups = groupWorkoutsByBlock(
        blocks: [_block('b1', 'Accumulation', 1)],
        workouts: [_workout('w3'), _workout('w1'), _workout('w2')],
        links: [
          _link('w1', blockId: 'b1'),
          _link('w2', blockId: 'b1'),
          _link('w3', blockId: 'b1'),
        ],
      );

      expect(groups.single.workouts.map((w) => w.sessionId), ['w3', 'w1', 'w2']);
    });
  });

  group('permuteWithinSlots', () {
    test('the block swaps among the positions it already holds', () {
      // Program order: a b c d e. Block holds b and d (slots 1 and 3).
      final result = permuteWithinSlots(
        globalOrder: ['a', 'b', 'c', 'd', 'e'],
        orderedSessionIds: ['d', 'b'],
        slotSessionIds: {'b', 'd'},
      );

      expect(result, ['a', 'd', 'c', 'b', 'e'],
          reason: 'the workouts outside the block must not move');
    });

    test('the unassigned group is permuted the same way', () {
      final result = permuteWithinSlots(
        globalOrder: ['a', 'b', 'c', 'd'],
        orderedSessionIds: ['d', 'a'],
        slotSessionIds: {'a', 'd'},
      );

      expect(result, ['d', 'b', 'c', 'a']);
    });

    test('a full-length permutation is an ordinary reorder', () {
      final result = permuteWithinSlots(
        globalOrder: ['a', 'b', 'c'],
        orderedSessionIds: ['c', 'a', 'b'],
        slotSessionIds: {'a', 'b', 'c'},
      );

      expect(result, ['c', 'a', 'b']);
    });
  });
}

PlannedSession _workout(String id) => PlannedSession(
  sessionId: id,
  userId: 'u1',
  name: id,
);

PlannedSessionProgram _link(String sessionId, {String? blockId}) =>
    PlannedSessionProgram(
      plannedSessionProgramId: 'l-$sessionId',
      programId: 'p1',
      plannedSessionId: sessionId,
      userId: 'u1',
      blockId: blockId,
    );

ProgramBlock _block(String id, String name, int order) => ProgramBlock(
  blockId: id,
  userId: 'u1',
  programId: 'p1',
  name: name,
  blockOrder: order,
);
