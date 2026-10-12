import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/block_sequence.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/models/program_run.dart';

/// The one rule this file exists for: **blocks are a sequence**.
///
/// Every case below is a way the app asks "which block, and why not that one" —
/// the program screen's Begin affordances, the run sheet's named block, and the
/// due prompt for a planned start. They are asserted here rather than three
/// times over because they are one answer, and the whole point of the value
/// object is that they cannot come to different ones.
ProgramBlock block(String id, {int order = 1, DateTime? startDate}) =>
    ProgramBlock(
      blockId: id,
      userId: 'u1',
      programId: 'p1',
      name: id,
      blockOrder: order,
      startDate: startDate,
    );

ProgramRun run(
  String id, {
  String? blockId,
  bool isCurrent = false,
  DateTime? endedDate,
}) =>
    ProgramRun(
      programRunId: id,
      programId: 'p1',
      userId: 'u1',
      startedDate: DateTime(2026, 2, 1),
      isCurrent: isCurrent,
      endedDate: endedDate,
      blockId: blockId,
    );

void main() {
  group('pending is the first block not yet ended', () {
    test('nothing run yet is the first block', () {
      final seq = BlockSequence(blocks: [block('a'), block('b')], runs: []);
      expect(seq.pending?.blockId, 'a');
    });

    test('an ended block is behind you', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1))],
      );
      expect(seq.pending?.blockId, 'b');
      expect(seq.isDone('a'), isTrue);
      expect(seq.isDone('b'), isFalse);
    });

    test('a run that was begun and not ended does NOT count as done', () {
      // The difference between pausing and finishing, asked of the blocks: an
      // open run means the phase it belongs to is still the one being worked.
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a', isCurrent: true)],
      );
      expect(seq.isDone('a'), isFalse);
      expect(seq.pending?.blockId, 'a');
    });

    test('every block ended leaves nothing pending', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [
          run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1)),
          run('r2', blockId: 'b', endedDate: DateTime(2026, 4, 1)),
        ],
      );
      expect(seq.pending, isNull);
    });

    test('a second, ended run of the same block is still just done', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [
          run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1)),
          run('r2', blockId: 'a', endedDate: DateTime(2026, 3, 20)),
        ],
      );
      expect(seq.pending?.blockId, 'b');
    });

    test('blocks in a different order answer in that order', () {
      final seq = BlockSequence(
        blocks: [block('b', order: 1), block('a', order: 2)],
        runs: [],
      );
      expect(seq.pending?.blockId, 'b');
    });
  });

  group('nextBlock wraps so a finished program is repeatable', () {
    test('a finished program begins again at the first block', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [
          run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1)),
          run('r2', blockId: 'b', endedDate: DateTime(2026, 4, 1)),
        ],
      );
      expect(seq.pending, isNull);
      expect(seq.nextBlock?.blockId, 'a');
    });

    test('nextBlock is pending while anything is left', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1))],
      );
      expect(seq.nextBlock?.blockId, 'b');
    });

    test('no blocks means no next block, wrapped or otherwise', () {
      final seq = BlockSequence(blocks: [], runs: []);
      expect(seq.pending, isNull);
      expect(seq.nextBlock, isNull);
    });
  });

  group('canBegin', () {
    test('the next block may be begun', () {
      final seq = BlockSequence(blocks: [block('a'), block('b')], runs: []);
      expect(seq.canBegin('a'), isTrue);
    });

    test('a later block may not, however empty its own history is', () {
      final seq = BlockSequence(blocks: [block('a'), block('b')], runs: []);
      expect(seq.canBegin('b'), isFalse);
    });

    test('a block already ended may not be begun again — that is Restart', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a', endedDate: DateTime(2026, 3, 1))],
      );
      expect(seq.canBegin('a'), isFalse);
      expect(seq.canBegin('b'), isTrue);
    });

    test('nothing may be begun while a run is open, not even the next block',
        () {
      // Mid-phase the affordance is Resume, and beginning over it is Restart:
      // a different act with a different record.
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a', isCurrent: true)],
      );
      expect(seq.canBegin('a'), isFalse);
      expect(seq.canBegin('b'), isFalse);
      expect(seq.hasOpenRun, isTrue);
    });

    test('a paused run holds the sequence exactly where a current one does', () {
      final seq = BlockSequence(
        blocks: [block('a'), block('b')],
        runs: [run('r1', blockId: 'a')],
      );
      expect(seq.hasOpenRun, isTrue);
      expect(seq.canBegin('b'), isFalse);
      expect(seq.nextBlock?.blockId, 'a');
    });

    test('an unknown block id can never be begun', () {
      final seq = BlockSequence(blocks: [block('a')], runs: []);
      expect(seq.canBegin('nope'), isFalse);
    });
  });

  test('a run of another shape — no block — opens and closes nothing', () {
    // A legacy whole-program run: it is still an open run (so nothing may be
    // begun beside it), but it marks no block as done.
    final seq = BlockSequence(
      blocks: [block('a')],
      runs: [run('r1', isCurrent: true)],
    );
    expect(seq.hasOpenRun, isTrue);
    expect(seq.isDone('a'), isFalse);
    expect(seq.canBegin('a'), isFalse);
  });
}
