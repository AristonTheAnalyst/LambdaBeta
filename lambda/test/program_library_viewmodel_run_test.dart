import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/features/programs/viewmodel/program_library_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// The library's half of the run lifecycle.
///
/// Beginning a program here steps aside whatever was running — often a run of a
/// *different* program, since this is the only screen that shows them all. It
/// used to end that run (and, before Stage 1, end it with no record at all);
/// now it pauses it, tells the user so, and badges the card it left behind.
/// Archiving is the only thing on this screen that ends a run, and it owes that
/// run a record whether it was current or paused.
void main() {
  late FakeProgramRepository programs;
  late FakeProgramRunRepository runs;
  late FakeProgramHistoryRepository history;
  late FakeAchievementsDerivation derivation;
  late ProgramLibraryViewModel vm;

  setUp(() {
    programs = FakeProgramRepository();
    runs = FakeProgramRunRepository();
    history = FakeProgramHistoryRepository();
    derivation = FakeAchievementsDerivation();
    vm = ProgramLibraryViewModel(
      repo: programs,
      runRepo: runs,
      historyRepo: history,
      achievementsDerivation: derivation,
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  group('setCurrentProgram', () {
    test('pauses the replaced run, which usually belongs to another program',
        () async {
      runs.currentRun = testRun(programRunId: 'old-run', programId: 'p0');
      await vm.fetchAll();

      await vm.setCurrentProgram('p1');

      expect(history.closeCalls, isEmpty,
          reason: 'the library can replace a run it does not show, and that '
              'run is stepped aside rather than finished — ending it here is '
              'what made switching programs destroy an attempt');
      expect(vm.state.value.currentProgramId, 'p1');
      expect(vm.state.value.settingCurrentId, isNull);
      expect(vm.state.value.isPaused('p0'), isTrue,
          reason: 'the card for the program just left has to say it is paused '
              '— with no badge it looks like the run vanished');
      expect(vm.state.value.isPaused('p1'), isFalse);
    });

    test('publishes progress and due items for the run it just began',
        () async {
      await vm.setCurrentProgram('p1');

      expect(runs.starts.single.programId, 'p1');
      expect(vm.state.value.error, isNull);
    });

    test('a failed begin leaves an error and claims no program', () async {
      runs.failStart = true;

      await vm.setCurrentProgram('p1');

      expect(vm.state.value.currentProgramId, isNull,
          reason: 'marking the card active on a write that failed would be a '
              'lie the next reload silently corrects');
      expect(vm.state.value.error, isNotNull);
      expect(runs.starts, isEmpty);
    });

    test('a failed begin does not badge the run that stayed current', () async {
      runs.currentRun = testRun(programRunId: 'old-run', programId: 'p0');
      await vm.fetchAll();
      runs.failStart = true;

      await vm.setCurrentProgram('p1');

      expect(vm.state.value.isPaused('p0'), isFalse,
          reason: 'p0 is still running — the begin that would have paused it '
              'never landed');
    });
  });

  group('resumeProgram', () {
    test('makes the paused run current again, without a new run', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p1',
        isCurrent: false,
        blockId: 'b1',
        targetSessions: 6,
      );
      runs.pausedRuns.add(paused);
      runs.runsById[paused.programRunId] = paused;
      await vm.fetchAll();

      await vm.resumeProgram('p1');

      expect(runs.starts, isEmpty,
          reason: 'resuming is not beginning — nothing new is inserted, and '
              'the run keeps its id, config and block');
      expect(runs.resumeCalls, ['paused-1']);
      expect(runs.currentRun?.programRunId, 'paused-1',
          reason: 'the same row came back — progress, the workout cursor and '
              'session attribution all hang off this id');
      expect(runs.currentRun?.blockId, 'b1',
          reason: 'resume returns to the block the run was in; a pause that '
              'lost it would silently re-scope the run');
      expect(runs.currentRun?.targetSessions, 6);
      expect(vm.state.value.currentProgramId, 'p1');
      expect(vm.state.value.isPaused('p1'), isFalse);
      expect(vm.state.value.settingCurrentId, isNull);
      expect(vm.state.value.error, isNull);
    });

    test('pauses whatever the resume displaced', () async {
      runs.currentRun = testRun(programRunId: 'live-1', programId: 'p0');
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p1',
        isCurrent: false,
      );
      runs.pausedRuns.add(paused);
      runs.runsById[paused.programRunId] = paused;
      await vm.fetchAll();

      await vm.resumeProgram('p1');

      expect(vm.state.value.currentProgramId, 'p1');
      expect(vm.state.value.isPaused('p0'), isTrue,
          reason: 'the run that lost its place is paused, not ended — one '
              'program coming back must not destroy another');
      expect(history.closeCalls, isEmpty);
    });

    test('a resume whose run is gone re-reads the truth instead of claiming one',
        () async {
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p1',
        isCurrent: false,
      );
      runs.pausedRuns.add(paused);
      runs.runsById[paused.programRunId] = paused;
      await vm.fetchAll();
      // Between the card being drawn and the tap, the run stopped being
      // paused — and something else took the current slot.
      runs.pausedRuns.clear();
      runs.runsById.clear();
      runs.currentRun = testRun(programRunId: 'elsewhere', programId: 'p9');

      await vm.resumeProgram('p1');

      expect(runs.resumeCalls, isEmpty,
          reason: 'there was nothing to resume, so no write may be aimed at a '
              'row that is not there');
      expect(vm.state.value.currentProgramId, 'p9',
          reason: 'the card was stale; the refresh shows what is actually '
              'running instead of repeating the claim');
      expect(vm.state.value.error, isNull,
          reason: 'nothing failed — the world moved, and an error would blame '
              'the user for a race');
      expect(vm.state.value.settingCurrentId, isNull);
    });
  });

  group('what the confirmation is built from', () {
    // The three facts the dialog's wording depends on. They are read from state
    // rather than worked out in the screen, because the screen that asks has no
    // test of its own and a question asked with the wrong words is still a
    // wrong question.
    test('another program running is displaced, and named', () async {
      programs.programs = [
        testProgram(programId: 'p1', name: 'Sample Program'),
        testProgram(programId: 'p0', name: 'Lambda'),
      ];
      runs.currentRun = testRun(programRunId: 'r0', programId: 'p0');
      await vm.fetchAll();
      final s = vm.state.value;

      expect(s.displacesCurrentRun('p1'), isTrue);
      expect(s.displacedProgramName('p1'), 'Lambda');
      expect(s.displacesCurrentRun('p0'), isFalse,
          reason: 'entering the program that is already running displaces '
              'nothing, and the confirmation has to know that as surely as it '
              'knows the reverse');
    });

    test('a current run whose program row is missing is still displaced',
        () async {
      runs.currentRun = testRun(programRunId: 'r0', programId: 'gone');
      await vm.fetchAll();
      final s = vm.state.value;

      expect(s.displacesCurrentRun('p1'), isTrue,
          reason: 'the run will be paused whatever its program row says, so '
              'the answer may not depend on a name being readable');
      expect(s.displacedProgramName('p1'), isNull,
          reason: 'the unreadable name is what the dialog renders as "another '
              'program" — kept as a separate fact from the displacement so it '
              'cannot be mistaken for "nothing is displaced"');
    });

    test('a run paused elsewhere is "other", never the program being entered',
        () async {
      runs.pausedRuns.add(
          testRun(programRunId: 'r1', programId: 'p2', isCurrent: false));
      await vm.fetchAll();
      final s = vm.state.value;

      expect(s.otherRunPaused('p1'), isTrue);
      expect(s.otherRunPaused('p2'), isFalse,
          reason: 'the program being resumed is itself paused, and counting it '
              'as "other" would have the dialog promise the opposite of what '
              'it is about to do');
    });

    test('nothing current and nothing paused says nothing extra', () async {
      await vm.fetchAll();
      final s = vm.state.value;

      expect(s.displacesCurrentRun('p1'), isFalse);
      expect(s.displacedProgramName('p1'), isNull);
      expect(s.otherRunPaused('p1'), isFalse,
          reason: 'the plain begin has to stay plain — a dialog that mentioned '
              'paused programs to someone who has none is how a warning stops '
              'being read');
    });
  });

  group('deleteProgram', () {
    test('ends and closes the current run before archiving', () async {
      runs.currentRun = testRun(programRunId: 'run-live', programId: 'p1');
      await vm.fetchAll();

      await vm.deleteProgram('p1');

      expect(runs.endCalls, ['u1']);
      expect(history.closeCalls.single.runId, 'run-live',
          reason: 'a run that ends because its program was archived produced '
              'something, and the close record is the only place it survives');
      expect(programs.deletedPrograms, ['p1']);
    });

    test('ends and closes a paused run too', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p1',
        isCurrent: false,
      );
      runs.pausedRuns.add(paused);
      await vm.fetchAll();

      await vm.deleteProgram('p1');

      expect(runs.endCalls, isEmpty,
          reason: 'nothing is current here — the by-user end has nothing to '
              'end, and must not reach the run that is current elsewhere');
      expect(runs.endRunCalls, ['paused-1'],
          reason: 'a paused run left open under an archived program could '
              'never be resumed (its program is gone) nor ended again, so it '
              'would sit as a phantom pause forever');
      expect(history.closeCalls.single.runId, 'paused-1',
          reason: 'the run produced something on the way to being paused, and '
              'the close record is where it survives the archive');
      expect(programs.deletedPrograms, ['p1']);
    });

    test('archiving a program that is not running cuts no record', () async {
      runs.currentRun = testRun(programRunId: 'other', programId: 'p2');
      await vm.fetchAll();

      await vm.deleteProgram('p1');

      expect(history.closeCalls, isEmpty);
      expect(runs.endCalls, isEmpty,
          reason: 'another program\'s run must not be ended by this archive');
    });

    test('a failed close surfaces a warning, the archive still happens',
        () async {
      runs.currentRun = testRun(programRunId: 'run-live', programId: 'p1');
      await vm.fetchAll();
      history.failClose = true;

      await vm.deleteProgram('p1');

      expect(programs.deletedPrograms, ['p1']);
      expect(vm.state.value.historyWarning, isNotNull);
    });
  });

  test('a begin that replaces a run touches no history at all', () async {
    runs.currentRun = testRun(programRunId: 'old-run', programId: 'p0');
    await vm.fetchAll();
    // Where Stage 1's begin could lose a record, this one cannot: there is no
    // record to lose.
    history.failClose = true;

    await vm.setCurrentProgram('p1');

    expect(vm.state.value.currentProgramId, 'p1');
    expect(history.closeCalls, isEmpty,
        reason: 'the run being left is paused, not finished — a begin writes '
            'no review, no snapshot, no checkpoint');
    expect(vm.state.value.historyWarning, isNull,
        reason: 'the old warning existed because a begin ended the run it '
            'replaced; with pausing there is nothing that can fail to record');
  });

  test('due badges are kept per program', () async {
    history.due = [
      DueItem(
        kind: kDueReview,
        programId: 'p1',
        dueDate: DateTime(2026, 3, 1),
      ),
    ];

    await vm.fetchAll();

    expect(vm.state.value.dueFor('p1'), isNotNull);
    expect(vm.state.value.dueFor('p2'), isNull);
  });

  group('nextBlockFor', () {
    test('a blocked program answers with its first block', () async {
      programs.blocks = [
        testBlock(blockId: 'b1', name: 'Accumulation'),
        testBlock(blockId: 'b2', name: 'Intensification', order: 2),
      ];

      expect((await vm.nextBlockFor('p1'))?.blockId, 'b1');
    });

    test('a run that was ended moves the answer to the next block', () async {
      programs.blocks = [
        testBlock(blockId: 'b1'),
        testBlock(blockId: 'b2', order: 2),
      ];
      // Ended, not paused: the library's Begin is for a program that is not
      // running, and what it offers is the phase the sequence is actually on.
      runs.runsById['r1'] = testRun(
        programRunId: 'r1',
        blockId: 'b1',
        isCurrent: false,
        endedDate: DateTime(2026, 3, 1),
      );

      expect((await vm.nextBlockFor('p1'))?.blockId, 'b2');
    });

    test('a paused run keeps the answer on the block it is in', () async {
      programs.blocks = [
        testBlock(blockId: 'b1'),
        testBlock(blockId: 'b2', order: 2),
      ];
      runs.runsById['r1'] = testRun(programRunId: 'r1', blockId: 'b1');

      expect(
        (await vm.nextBlockFor('p1'))?.blockId,
        'b1',
        reason: 'resuming a program returns to the block it was in — the '
            'paused run carries its block, and nothing advances past it',
      );
    });

    test('a fully run program begins again at its first block', () async {
      programs.blocks = [testBlock(blockId: 'b1'), testBlock(blockId: 'b2', order: 2)];
      runs.runsById['r1'] = testRun(
        programRunId: 'r1',
        blockId: 'b1',
        isCurrent: false,
        endedDate: DateTime(2026, 3, 1),
      );
      runs.runsById['r2'] = testRun(
        programRunId: 'r2',
        blockId: 'b2',
        isCurrent: false,
        endedDate: DateTime(2026, 4, 1),
      );

      expect(
        (await vm.nextBlockFor('p1'))?.blockId,
        'b1',
        reason: 'a finished program is repeatable — a dead end here would '
            'leave it with nothing to offer',
      );
    });

    test('a program with no blocks answers with nothing to run', () async {
      expect(await vm.nextBlockFor('p1'), isNull);
    });
  });
}
