import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/viewmodel/program_history_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// How a review begins, and how it is re-entered — the two paths that must
/// never be confused with each other.
///
/// Starting writes a row over the **set** the picker returned (with its "as
/// found" baseline); resuming must write **nothing**, because a card tap that
/// inserted a second row would fork one pass into two reviews, each asking the
/// same question and cutting its own snapshot, with no way for the timeline to
/// say which was real.
///
/// Two facts the row itself cannot be trusted for are pinned here: the run a
/// review answers for is the one whose block the set sits in (so the
/// length-reached prompt and the pass cannot be about different phases), and a
/// row from before sets were stored still resolves to the workouts its old
/// scope names.
///
/// The fakes make "nothing was written" assertable rather than merely
/// unobservable: `beginReview` is recorded when called and unexercised
/// repository members throw, so a resume that reached for an insert would
/// surface as a failed resume instead of a silent second row.
void main() {
  late FakeProgramHistoryRepository history;
  late FakeProgramRunRepository runs;
  late FakeAchievementsDerivation derivation;
  late FakePlannedSessions planned;

  ProgramReview openReview({
    String id = 'r1',
    String? sessionIdsJson = '["s1"]',
    String? blockId,
    String? sessionId,
    String? programRunId,
    String? baselineContent,
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    programId: 'p1',
    blockId: blockId,
    sessionId: sessionId,
    programRunId: programRunId,
    sessionIdsJson: sessionIdsJson,
    kind: kReviewKindReview,
    baselineContent: baselineContent,
    createdDate: DateTime(2026, 1, 1),
  );

  ProgramHistoryViewModel build() => ProgramHistoryViewModel(
    userId: 'u1',
    historyRepository: history,
    exerciseRepository: FakeExercises(),
    programRepository: FakeProgramRepository(),
    runRepository: runs,
    plannedSessionRepository: planned,
    achievementsDerivation: derivation,
  );

  setUp(() {
    history = FakeProgramHistoryRepository();
    runs = FakeProgramRunRepository();
    derivation = FakeAchievementsDerivation();
    planned = FakePlannedSessions();
  });

  test('starting a review writes the row, its baseline and the set it was '
      'handed', () async {
    runs.currentRun = testRun(startedDate: DateTime(2026, 2, 1));

    final started = await build().startReview('p1', sessionIds: ['s1']);

    final call = history.beginCalls.single;
    expect(call.userId, 'u1');
    expect(call.programId, 'p1');
    expect(
      call.sessionIds,
      ['s1'],
      reason: 'the set the picker returned is the whole scope — the row '
          'stores it and nothing re-derives it',
    );
    expect(
      call.programRunId,
      'run-1',
      reason: 'the run in progress over this program is the one the review '
          'answers for, and the prompt suppression keys off exactly this id',
    );

    // `beginReview` is the row and its baseline in one move, so the row the
    // ceremony opens on already has a "before" to compare the pass against.
    expect(started!.review.hasBaseline, isTrue);
    expect(started.review.reviewId, 'begin-1');
    expect(started.sessionIds, ['s1']);
    expect(
      started.achievements,
      isNotNull,
      reason: 'read back from the reload that follows the write, not derived '
          'a second time — the sheet and the panel must tell one story',
    );
  });

  test('the run a review answers for is the one whose block the set sits in — '
      'a run in a block none of the set touches is somebody else\'s', () async {
    planned.links = [
      _link('s1', blockId: 'b1'),
      _link('s2', blockId: 'b2'),
    ];
    runs.currentRun = testRun(blockId: 'b1');

    final vm = build();
    await vm.load('p1');
    await vm.startReview('p1', sessionIds: ['s1']);
    expect(
      history.beginCalls.last.programRunId,
      'run-1',
      reason: 'the pass covers a workout of the running block, so the run '
          'prompt it stands in front of is this one',
    );

    final other = build();
    await other.load('p1');
    await other.startReview('p1', sessionIds: ['s2']);
    expect(
      history.beginCalls.last.programRunId,
      isNull,
      reason: 'a review of another block is not answering for this run — '
          'attaching it would suppress a prompt it was never about',
    );
  });

  test('resuming an open review writes nothing — it heals, reopens, and '
      'carries its own set', () async {
    runs.currentRun = testRun(startedDate: DateTime(2026, 2, 1));
    planned.links = [_link('s1', blockId: 'b1'), _link('s2', blockId: 'b1')];
    final review = openReview(sessionIdsJson: '["s1","s2"]');
    history.reviews = [review];
    final vm = build();
    await vm.load('p1');

    final resumed = await vm.resumeReview('p1', review);

    expect(
      history.beginCalls,
      isEmpty,
      reason: 'the whole point: a resume finds the row, it does not write one',
    );
    expect(
      history.baselineCalls,
      ['r1'],
      reason: 'the baseline call is a capture, idempotent by construction — it '
          'is how a review from before baselines were recorded gets one, and '
          'how every resume touches the row without changing it',
    );
    expect(resumed!.review.reviewId, 'r1');
    expect(
      resumed.sessionIds,
      ['s1', 's2'],
      reason: 'the ceremony opens on the row\'s stored set — reading the '
          'columns instead would show an empty review',
    );
    expect(
      resumed.achievements,
      isNotNull,
      reason: 'the loaded state carries the achievements the panel derived for '
          'the open review; resume passes them through rather than deriving',
    );
  });

  test('a row from before sets were stored resolves to the workouts its old '
      'scope names', () async {
    planned.links = [
      _link('s1', blockId: 'b1'),
      _link('s2', blockId: 'b1'),
      _link('s3', blockId: 'b2'),
    ];
    // A legacy block review: no stored set, one block column.
    final legacy = openReview(sessionIdsJson: null, blockId: 'b1');
    history.reviews = [legacy];
    final vm = build();
    await vm.load('p1');

    final resumed = await vm.resumeReview('p1', legacy);

    expect(
      resumed!.sessionIds,
      ['s1', 's2'],
      reason: 'the fall-through is the only reason an old review can still be '
          'walked — it is a set of the block\'s workouts now',
    );
  });

  test('a resume opens on the healed row, not the stale one it was handed',
      () async {
    runs.currentRun = testRun(startedDate: DateTime(2026, 2, 1));
    final stale = openReview();
    final healed = openReview(
      baselineContent: const ProgramContent().encode(),
    );
    history.reviews = [stale];
    history.baselineResult = healed;
    final vm = build();
    await vm.load('p1');

    final resumed = await vm.resumeReview('p1', stale);

    expect(
      resumed!.review.hasBaseline,
      isTrue,
      reason: 'the row that came back from the capture is the one the ceremony '
          'opens on — a baseline captured into the DB but not into the screen '
          'would leave Compare blind for the rest of the pass',
    );
  });
}

/// A join row as the view model reads them: the workout's membership, and the
/// block it sits in.
PlannedSessionProgram _link(String plannedSessionId, {String? blockId}) =>
    PlannedSessionProgram(
      plannedSessionProgramId: 'link-$plannedSessionId',
      programId: 'p1',
      plannedSessionId: plannedSessionId,
      userId: 'u1',
      blockId: blockId,
    );
