import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/viewmodel/program_history_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// What a checkpoint's digest says it changed — and, more to the point, what
/// it refuses to compare.
///
/// The Versions tab used to answer "how has this program drifted" by numbering
/// snapshots along one line. Reviews replaced that, and the property that has
/// to survive the move is that a diff only ever means **the same question,
/// asked twice**: a workout review's changes are against the last time *that
/// workout* was reviewed, never against a block checkpoint that happened to
/// land in between. Bridging scopes would produce a diff that reads as real
/// and answers nothing — "Set 1 changed 60 → 65" where the 60 came from a
/// different workout entirely.
///
/// These are unit-level: the fake hands the view model already-ordered rows
/// (newest first, the repository's contract), so the file pins the pairing
/// rule, not the SQL that orders the list.
void main() {
  /// A workout with one set — the smallest thing a snapshot can hold.
  ContentSession session(String id, {String weight = '60'}) => ContentSession(
    sessionId: id,
    userId: 'u1',
    name: id == 's1' ? 'Push A' : 'Pull A',
    exercises: [
      ContentExercise(
        plannedExerciseId: '$id-x',
        plannedSessionId: id,
        userId: 'u1',
        exerciseOrder: 1,
        exerciseId: 'e1',
        sets: [
          ContentSet(
            plannedSetId: '$id-x-1',
            plannedExerciseId: '$id-x',
            plannedSessionId: id,
            userId: 'u1',
            setNumber: 1,
            targetWeight: weight,
            targetReps: '5',
          ),
        ],
      ),
    ],
  );

  ProgramContent content({List<ContentSession>? sessions}) =>
      ProgramContent(sessions: sessions ?? [session('s1')]);

  ProgramBlock block(String id, String name, int order) => ProgramBlock(
    blockId: id,
    userId: 'u1',
    programId: 'p1',
    name: name,
    blockOrder: order,
  );

  /// A checkpoint of [snapshot] at a scope. Completed and carrying its
  /// snapshot unless a case deliberately says otherwise.
  ProgramReview checkpoint(
    String id, {
    ProgramContent? snapshot,
    String? blockId,
    String? sessionId,
    DateTime? completed,
    String? outcome,
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    programId: 'p1',
    blockId: blockId,
    sessionId: sessionId,
    kind: kReviewKindReview,
    createdDate: DateTime(2026, 1, 1),
    completedDate: completed ?? DateTime(2026, 1, 1),
    outcome: outcome ?? kOutcomeReviewed,
    snapshotContent: snapshot?.encode(),
    snapshotHash: snapshot?.contentHash,
  );

  /// Loads a history timeline from [reviews] (newest first, as the repository
  /// hands them over) and returns the loaded view model.
  Future<ProgramHistoryViewModel> load(
    List<ProgramReview> reviews, {
    List<ProgramBlock> blocks = const [],
  }) async {
    final vm = ProgramHistoryViewModel(
      userId: 'u1',
      historyRepository: FakeProgramHistoryRepository()..reviews = reviews,
      exerciseRepository: FakeExercises(),
      programRepository: FakeProgramRepository(
        programs: [testProgram(usesBlocks: blocks.isNotEmpty)],
      )..blocks = blocks,
      runRepository: FakeProgramRunRepository(),
      plannedSessionRepository: FakePlannedSessions(),
    );
    await vm.load('p1');
    return vm;
  }

  test('the counts are the snapshot’s own, so a card can say what a checkpoint '
      'holds without decoding it again', () async {
    final vm = await load([checkpoint('r1', snapshot: content())]);

    final digest = vm.state.value.digestFor('r1');
    expect(digest.sessionCount, 1);
    expect(digest.exerciseCount, 1);
    expect(digest.setCount, 1);
  });

  test('the first checkpoint at a scope has nothing to compare against, so it '
      'claims no change', () async {
    final vm = await load([checkpoint('r1', snapshot: content())]);

    // Null, not an empty diff: "no changes" is a statement about a comparison
    // that never happened, and the card would print it as a fact.
    expect(vm.state.value.digestFor('r1').vsPrevious, isNull);
  });

  test('a later checkpoint diffs against the one before it at the same scope', () async {
    final vm = await load([
      // Newest first: r2 was taken after the 60 → 65 edit.
      checkpoint('r2', snapshot: content(sessions: [session('s1', weight: '65')])),
      checkpoint('r1', snapshot: content()),
    ]);

    final diff = vm.state.value.digestFor('r2').vsPrevious;
    expect(diff, isNotNull);
    expect(diff!.summary, contains('~1'));
    expect(diff.changes.single.detail, '60 × 5 → 65 × 5');

    // The oldest one still has no predecessor — the walk must not wrap.
    expect(vm.state.value.digestFor('r1').vsPrevious, isNull);
  });

  test('workouts do not compare across scopes: a workout review answers to the '
      'last review of that workout, not to the block checkpoint in between', () async {
    final vm = await load(
      blocks: [block('b1', 'Accumulation', 1)],
      [
        // Newest first. s1 was reviewed, then the block was, then s1 again.
        checkpoint(
          'r3',
          sessionId: 's1',
          blockId: 'b1',
          snapshot: content(sessions: [session('s1', weight: '65')]),
        ),
        checkpoint(
          'r2',
          blockId: 'b1',
          snapshot: content(sessions: [session('s1', weight: '90')]),
        ),
        checkpoint('r1', sessionId: 's1', blockId: 'b1', snapshot: content()),
      ],
    );

    final digests = vm.state.value.digests;

    // r3's predecessor is r1 — the last time THIS workout was reviewed. Against
    // the block checkpoint it would have read 90 → 65, an edit nobody made.
    expect(digests['r3']!.vsPrevious, isNotNull);
    expect(digests['r3']!.vsPrevious!.changes.single.detail, '60 × 5 → 65 × 5');

    // And the block's own stream starts fresh: it has never been reviewed
    // before, however many workout checkpoints came first.
    expect(digests['r2']!.vsPrevious, isNull);
    expect(digests['r1']!.vsPrevious, isNull);
  });

  test('a block review and a program review never see each other either',
      () async {
    final vm = await load(
      blocks: [block('b1', 'Accumulation', 1)],
      [
        checkpoint('r2', snapshot: content(sessions: [session('s1', weight: '65')])),
        checkpoint(
          'r1',
          blockId: 'b1',
          snapshot: content(sessions: [session('s1', weight: '90')]),
        ),
      ],
    );

    final digests = vm.state.value.digests;
    expect(digests['r2']!.vsPrevious, isNull, reason: 'the program was never reviewed');
    expect(digests['r1']!.vsPrevious, isNull, reason: 'nor was the block');
  });

  test('two blocks are two streams: one block’s checkpoint is not the other’s '
      'predecessor', () async {
    final vm = await load(
      blocks: [block('b1', 'Accumulation', 1), block('b2', 'Intensification', 2)],
      [
        checkpoint('r3', blockId: 'b1', snapshot: content(sessions: [session('s1', weight: '65')])),
        checkpoint('r2', blockId: 'b2', snapshot: content(sessions: [session('s1', weight: '90')])),
        checkpoint('r1', blockId: 'b1', snapshot: content()),
      ],
    );

    final digests = vm.state.value.digests;
    expect(digests['r3']!.vsPrevious!.changes.single.detail, '60 × 5 → 65 × 5');
    expect(digests['r2']!.vsPrevious, isNull);
  });

  test('a dismissal is not a predecessor — it recorded nothing to compare '
      'against', () async {
    final vm = await load([
      checkpoint('r3', snapshot: content(sessions: [session('s1', weight: '65')])),
      // Dismissed: completed, no snapshot. It sits between the two real ones.
      checkpoint('r2', outcome: kOutcomeDismissed, completed: DateTime(2026, 1, 2)),
      checkpoint('r1', snapshot: content()),
    ]);

    final digests = vm.state.value.digests;

    // Skipped over, not compared against: a dismissal means "not now", so
    // diffing against the document it never froze would be diffing against
    // nothing — and treating it as an empty program would report every set as
    // added.
    expect(digests['r3']!.vsPrevious!.changes.single.detail, '60 × 5 → 65 × 5');
    expect(digests['r2']!.vsPrevious, isNull);
    expect(digests['r2']!.sessionCount, 0);
  });

  test('an open review has no snapshot yet, so it diffs against nothing and '
      'blocks nothing', () async {
    final vm = await load([
      // Open: no completed date at all.
      checkpoint('r3', completed: null, outcome: null),
      checkpoint('r2', snapshot: content(sessions: [session('s1', weight: '65')])),
      checkpoint('r1', snapshot: content()),
    ]);

    final digests = vm.state.value.digests;
    expect(digests['r3']!.vsPrevious, isNull);
    expect(digests['r3']!.sessionCount, 0);
    expect(digests['r2']!.vsPrevious!.changes.single.detail, '60 × 5 → 65 × 5');
  });

  test('digestFor answers an unknown id with an empty digest rather than '
      'throwing', () async {
    final vm = await load([checkpoint('r1', snapshot: content())]);

    final digest = vm.state.value.digestFor('nope');
    expect(digest.sessionCount, 0);
    expect(digest.vsPrevious, isNull);
  });
}
