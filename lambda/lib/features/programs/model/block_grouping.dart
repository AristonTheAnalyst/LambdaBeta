import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_program.dart';
import '../../../data/models/program_block.dart';

/// One section of a program's ordered workout view: a block and the workouts
/// assigned to it, or — when [block] is null — the workouts assigned to none.
class ProgramBlockGroup {
  const ProgramBlockGroup({required this.block, required this.workouts});

  /// Null is the unassigned group: a blockless program's single section, or
  /// the leftovers of a program that has blocks.
  final ProgramBlock? block;

  final List<PlannedSession> workouts;

  bool get isUnassigned => block == null;
}

/// Splits a program's workouts into its blocks, in order.
///
/// Membership lives on the join rows, so this is an id-keyed join, never a
/// positional one — the same reason the session screen anchors ghost targets
/// by id. Workout order within a group follows the incoming order, which is
/// the program-global `sequence_order`.
///
/// A program with no blocks comes back as exactly one unassigned group, so
/// blockless rendering is the same list it has always been.
List<ProgramBlockGroup> groupWorkoutsByBlock({
  required List<ProgramBlock> blocks,
  required List<PlannedSession> workouts,
  required List<PlannedSessionProgram> links,
}) {
  if (blocks.isEmpty) {
    return [ProgramBlockGroup(block: null, workouts: workouts)];
  }

  final blockIdBySession = <String, String?>{};
  for (final link in links) {
    blockIdBySession[link.plannedSessionId] = link.blockId;
  }

  final byBlock = <String, List<PlannedSession>>{
    for (final b in blocks) b.blockId: [],
  };
  final unassigned = <PlannedSession>[];

  for (final workout in workouts) {
    final blockId = blockIdBySession[workout.sessionId];
    // A link naming a block this list doesn't hold (archived between the two
    // reads) reads as unassigned, which is what archiving does to it anyway.
    final list = blockId == null ? null : byBlock[blockId];
    (list ?? unassigned).add(workout);
  }

  return [
    for (final block in blocks)
      ProgramBlockGroup(block: block, workouts: byBlock[block.blockId]!),
    if (unassigned.isNotEmpty)
      ProgramBlockGroup(block: null, workouts: unassigned),
  ];
}

/// Rewrites the global order so [orderedSessionIds] occupies the positions its
/// members already hold, leaving every other workout where it is.
///
/// `sequence_order` is program-global by design — that is what keeps block
/// reordering from cascading a renumber through the workouts. The cost is that
/// reordering inside one block is a permutation of *slots*, not a rewrite of
/// the block's numbers: the block's members swap among the positions they
/// already occupy, and nothing else moves.
List<String> permuteWithinSlots({
  required List<String> globalOrder,
  required List<String> orderedSessionIds,
  required Set<String> slotSessionIds,
}) {
  final slots = <int>[];
  for (var i = 0; i < globalOrder.length; i++) {
    if (slotSessionIds.contains(globalOrder[i])) slots.add(i);
  }
  final reordered = List<String>.from(globalOrder);
  for (var k = 0; k < slots.length && k < orderedSessionIds.length; k++) {
    reordered[slots[k]] = orderedSessionIds[k];
  }
  return reordered;
}
