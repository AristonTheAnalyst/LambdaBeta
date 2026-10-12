import 'program_block.dart';
import 'program_run.dart';

/// Which block a program is on, and what is holding the rest back.
///
/// A computed value object, not a table — like [ProgramProgress], it is built
/// from rows the data layer already reads and is never persisted itself. It
/// lives here rather than in the programs feature because the layer that
/// prompts for a block start (`ProgramHistoryRepository.fetchDueItems`) has to
/// answer the question too, and a rule the data layer cannot see is a rule it
/// will eventually spell for itself.
///
/// Blocks are a sequence, not a menu. A program's phases are built to be
/// worked through in order, so block N may only be begun once every block
/// before it has been **ended** — a run of a block that is under way (current
/// or paused) is not behind you, and neither is one that was never begun.
/// Without that rule "phase 3" is a label rather than a plan: the phase you
/// skipped is the one whose adaptations the rest were built on.
///
/// Pure, and given the blocks and runs rather than reading them: the same
/// question is asked by the program screen (which block may be begun), the run
/// sheet (which block a begin will follow), and `fetchDueItems` (whether a
/// planned start is worth prompting for), and three callers answering it three
/// ways is how the app ends up prompting for a block it will then refuse.
class BlockSequence {
  BlockSequence({
    required List<ProgramBlock> blocks,
    required Iterable<ProgramRun> runs,
  })  : blocks = List.unmodifiable(blocks),
        _runs = List.unmodifiable(runs);

  /// The program's active blocks, in `block_order`. The order is the answer to
  /// "what comes next", so it is the caller's job to have sorted them — every
  /// read of them already does.
  final List<ProgramBlock> blocks;

  final List<ProgramRun> _runs;

  /// Whether a run of the program is open — current or paused.
  ///
  /// A program with one has not finished the block it is in, so nothing else
  /// in it may be begun: the move is to resume or end that run, not to start
  /// another phase beside it.
  bool get hasOpenRun => _runs.any((r) => r.endedDate == null);

  /// Whether [blockId] has been run to its end.
  ///
  /// Only an end counts. A run that was begun and never ended is a block under
  /// way, and one that was restarted did not finish the attempt it left.
  bool isDone(String blockId) =>
      _runs.any((r) => r.blockId == blockId && r.endedDate != null);

  /// The first block that has not been ended — null once every block has been.
  ///
  /// The honest "where is this program up to": null is a finished program, and
  /// the difference between that and "not started" is the whole reason
  /// [nextBlock] exists as a second answer.
  ProgramBlock? get pending {
    for (final b in blocks) {
      if (!isDone(b.blockId)) return b;
    }
    return null;
  }

  /// The block a fresh run would follow now — [pending], or the first block
  /// again when every block has been run.
  ///
  /// The wrap is what makes a program repeatable: having worked through every
  /// phase, beginning again means starting from the first one, exactly as the
  /// first time. A dead end there would leave a completed program with nothing
  /// to offer, and "run it again" with no way to say so.
  ProgramBlock? get nextBlock => pending ?? (blocks.isEmpty ? null : blocks.first);

  /// Whether [blockId] may be begun now: it is the block the sequence is on,
  /// and the program has no run open.
  ///
  /// The run half matters even for the next block: mid-phase, the affordance
  /// is Resume, and beginning over it is Restart — a different act with a
  /// different consequence for the record.
  bool canBegin(String blockId) =>
      !hasOpenRun && nextBlock?.blockId == blockId;
}
