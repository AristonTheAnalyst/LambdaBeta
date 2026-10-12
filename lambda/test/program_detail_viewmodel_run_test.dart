import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_progress.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// The detail screen's half of the run lifecycle.
///
/// The screen used to mint the run itself and discard the repository's — so
/// the run id in state was never a row, and every write that addressed it
/// silently did nothing. These tests hold the state to the id the repository
/// actually returned, and to what each run state means: a superseding begin
/// pauses the run it replaced, a paused run resumes into itself, and only an
/// explicit end (or a restart) finishes one.
void main() {
  late FakeProgramRepository programs;
  late FakeProgramRunRepository runs;
  late FakeProgramHistoryRepository history;
  late FakeAchievementsDerivation derivation;
  late ProgramDetailViewModel vm;

  ProgramDetailViewModel build() => ProgramDetailViewModel(
        repo: programs,
        runRepo: runs,
        historyRepo: history,
        achievementsDerivation: derivation,
        // `load()` reads through these two; on a host they would reach the
        // real PowerSync database, which is not there.
        workoutPlanRepo: FakePlannedSessions(),
        exerciseRepo: FakeExercises(),
        // Host tests cannot default-construct LessonRepository — see
        // FakeLessons.
        lessonRepo: FakeLessons(),
        userId: 'u1',
      );

  setUp(() {
    programs = FakeProgramRepository();
    runs = FakeProgramRunRepository();
    history = FakeProgramHistoryRepository();
    derivation = FakeAchievementsDerivation();
    vm = build();
    // What `load()` publishes for a program with nothing running.
    vm.state.value = ProgramDetailState(program: testProgram());
  });

  tearDown(() => vm.dispose());

  group('setAsCurrent', () {
    test('adopts the repository\'s run id', () async {
      await vm.setAsCurrent(targetSessions: 12);

      final active = vm.state.value.activeRun;
      expect(active, isNotNull);
      expect(active!.programRunId, runs.starts.single.returned.programRunId,
          reason: 'a run id minted here would never match a row — config '
              'edits and the closing record would all miss it');
      expect(active.targetSessions, 12);
      expect(vm.state.value.isCurrent, isTrue);
      expect(vm.state.value.error, isNull);
    });

    test('pauses the run it replaced, cutting no record', () async {
      runs.currentRun = testRun(programRunId: 'old-run', programId: 'p0');

      await vm.setAsCurrent();

      expect(history.closeCalls, isEmpty,
          reason: 'the run being left is stepped aside, not finished — ending '
              'it here is what destroyed an attempt four seconds in');
      expect(runs.pausedRuns.map((r) => r.programRunId), ['old-run'],
          reason: 'it is still there to pick back up, under its own program');
      expect(runs.endCalls, isEmpty,
          reason: 'the repository\'s start steps the previous run aside; the '
              'screen must not also end it');
      expect(vm.state.value.isCurrent, isTrue);
      expect(vm.state.value.pausedRun, isNull,
          reason: 'this program is current — it cannot be paused at once');
    });

    test('a failed write rolls the screen back', () async {
      runs.failStart = true;

      await vm.setAsCurrent();

      expect(vm.state.value.isCurrent, isFalse,
          reason: 'the program must not stay marked current when nothing '
              'was persisted');
      expect(vm.state.value.activeRun, isNull);
      expect(vm.state.value.error, isNotNull);
      expect(history.closeCalls, isEmpty);
    });

    // The goals window that used to open here — at the run's start, when a
    // first run has no checkpoint — went with the screen's goals: goals are
    // standalone (2026-10-08) and this screen no longer derives them. The
    // window is still real, and `program_run_lifecycle_test.dart` holds it.
  });

  group('endCurrentRun', () {
    test('clears the run and its progress from state', () async {
      await vm.setAsCurrent();
      expect(vm.state.value.activeRun, isNotNull);

      await vm.endCurrentRun();

      expect(vm.state.value.activeRun, isNull,
          reason: 'a `??`-based copyWith cannot clear through a null argument '
              '— ending a run has to say so explicitly, or the ended run\'s '
              'config stays on screen');
      expect(vm.state.value.currentProgress, isNull);
      expect(vm.state.value.isCurrent, isFalse);
      expect(runs.endCalls, ['u1']);
      expect(history.closeCalls.single.runId, 'run-1');
    });

    test('a close that fails leaves a visible warning, not a failed end',
        () async {
      await vm.setAsCurrent();
      history.failClose = true;

      await vm.endCurrentRun();

      expect(vm.state.value.isCurrent, isFalse);
      expect(vm.state.value.activeRun, isNull);
      expect(vm.state.value.historyWarning, isNotNull,
          reason: 'the run is over either way — but a lost record must be '
              'said out loud');
      expect(vm.state.value.error, isNull);
    });
  });

  group('updateRunConfig', () {
    test('addresses the repository\'s id', () async {
      await vm.setAsCurrent(targetSessions: 6);

      await vm.updateRunConfig(targetSessions: 9);

      expect(runs.updateConfigCalls.single.programRunId,
          runs.starts.single.returned.programRunId);
      expect(vm.state.value.activeRun!.targetSessions, 9);
    });

    test('a block run keeps its block through a duration edit', () async {
      await vm.setAsCurrent(blockId: 'b1', targetSessions: 6);

      await vm.updateRunConfig(targetSessions: 9);

      expect(vm.state.value.activeRun!.blockId, 'b1',
          reason: 'dropping the block un-blocks the run: goal scoping stops '
              'and the close records a program end instead of a block end');
      expect(vm.state.value.activeRun!.programRunId, 'run-1');
    });
  });

  group('load', () {
    test('reads this program\'s paused run, with its numbers', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        isCurrent: false,
        blockId: 'b1',
      );
      runs.pausedRuns.add(paused);
      runs.progress = ProgramProgress(
        program: testProgram(),
        run: paused,
        weekNumber: 2,
        workoutsCompletedInCycle: 3,
        totalWorkoutsInCycle: 6,
        totalWorkoutsCompleted: 3,
      );

      await vm.load('p1');
      await pumpEventQueue();

      expect(vm.state.value.pausedRun?.programRunId, 'paused-1');
      expect(vm.state.value.pausedProgress?.totalWorkoutsInCycle, 6,
          reason: 'a paused run still has numbers to show — reading them '
              'through `getProgress` is what a paused program cannot do, so '
              'the paused path has its own read');
      expect(vm.state.value.activeRun, isNull,
          reason: 'activeRun stays "current only" — one meaning per field');
      expect(vm.state.value.isCurrent, isFalse);
      expect(vm.state.value.error, isNull);
    });

    test('ignores a paused run that belongs to another program', () async {
      runs.pausedRuns
          .add(testRun(programRunId: 'paused-9', programId: 'p9', isCurrent: false));

      await vm.load('p1');
      await pumpEventQueue();

      expect(vm.state.value.pausedRun, isNull,
          reason: 'the read is scoped to the program on screen; another '
              'program\'s paused run is that program\'s business');
      expect(vm.state.value.isCurrent, isFalse);
    });
  });

  group('resumeRun', () {
    test('puts the paused run back in charge, same id and block', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        isCurrent: false,
        blockId: 'b1',
        targetSessions: 6,
      );
      runs.runsById[paused.programRunId] = paused;
      runs.pausedRuns.add(paused);
      vm.state.value = vm.state.value.copyWith(pausedRun: paused);

      await vm.resumeRun();
      await pumpEventQueue();

      expect(runs.starts, isEmpty,
          reason: 'resuming is not beginning — no new row, and the run keeps '
              'its id, its config and its block');
      expect(runs.resumeCalls, ['paused-1']);
      expect(vm.state.value.isCurrent, isTrue);
      expect(vm.state.value.activeRun?.programRunId, 'paused-1');
      expect(vm.state.value.activeRun?.blockId, 'b1',
          reason: 'resume returns to the block the run was in');
      expect(vm.state.value.activeRun?.isCurrent, isTrue,
          reason: 'the row in state describes itself as current too — handing '
              'back the pre-write object would say this run is paused at the '
              'moment the screen calls it current');
      expect(vm.state.value.pausedRun, isNull);
      expect(vm.state.value.error, isNull);
      expect(history.closeCalls, isEmpty);
    });

    test('pauses whichever program was running', () async {
      runs.currentRun = testRun(programRunId: 'live-1', programId: 'p0');
      final paused = testRun(programRunId: 'paused-1', isCurrent: false);
      runs.runsById[paused.programRunId] = paused;
      runs.pausedRuns.add(paused);
      vm.state.value = vm.state.value.copyWith(pausedRun: paused);

      await vm.resumeRun();
      await pumpEventQueue();

      expect(vm.state.value.isCurrent, isTrue);
      expect(vm.state.value.anotherProgramIsCurrent, isFalse);
      expect(runs.pausedRuns.map((r) => r.programRunId), ['live-1'],
          reason: 'the run that lost its place is paused, not ended — '
              'resuming one program must not destroy another');
      expect(history.closeCalls, isEmpty);
    });

    test('a resume that did not take claims nothing', () async {
      // The row is gone by the time the write runs — the update matches
      // nothing. (The fake keeps no runs, so its resume is a no-op.)
      final paused = testRun(programRunId: 'paused-1', isCurrent: false);
      vm.state.value = vm.state.value.copyWith(pausedRun: paused);

      await vm.resumeRun();
      await pumpEventQueue();

      expect(vm.state.value.isCurrent, isFalse,
          reason: 'claiming "current" for a row that did not move is the '
              'phantom id all over again — the read-back is what makes it a '
              'fact instead of a claim');
      expect(vm.state.value.activeRun, isNull);
      expect(vm.state.value.pausedRun, isNotNull,
          reason: 'the run is still whatever it was, and the card goes on '
              'saying so');
    });
  });

  group('endPausedRun', () {
    test('ends the paused run by id and cuts its record', () async {
      final paused = testRun(programRunId: 'paused-1', isCurrent: false);
      runs.runsById[paused.programRunId] = paused;
      vm.state.value = vm.state.value.copyWith(pausedRun: paused);

      await vm.endPausedRun();
      await pumpEventQueue();

      expect(runs.endRunCalls, ['paused-1'],
          reason: 'a paused run is never the current one, so the by-user end '
              'could not reach it — ending one has to be asked for by name');
      expect(runs.endCalls, isEmpty,
          reason: 'the by-user end would have ended whatever IS current — a '
              'different program, probably');
      expect(history.closeCalls.single.runId, 'paused-1',
          reason: 'ending an attempt you are not finished with is exactly '
              'when its record matters');
      expect(vm.state.value.pausedRun, isNull);
      expect(vm.state.value.isCurrent, isFalse);
    });

    test('a close that fails leaves a warning, and the end stands', () async {
      final paused = testRun(programRunId: 'paused-1', isCurrent: false);
      runs.runsById[paused.programRunId] = paused;
      vm.state.value = vm.state.value.copyWith(pausedRun: paused);
      history.failClose = true;

      await vm.endPausedRun();
      await pumpEventQueue();

      expect(vm.state.value.pausedRun, isNull,
          reason: 'the run is over either way — a failed record must not '
              'leave it looking resumable');
      expect(vm.state.value.historyWarning, isNotNull,
          reason: 'a lost record is invisible unless it is said');
    });

    test('with no paused run it does nothing', () async {
      await vm.endPausedRun();

      expect(runs.endRunCalls, isEmpty);
      expect(runs.endCalls, isEmpty);
      expect(history.closeCalls, isEmpty);
    });
  });

  group('restartRun', () {
    test('ends the old run with its record, then adopts a fresh one',
        () async {
      final old = testRun(
        programRunId: 'live-1',
        blockId: 'b1',
        targetSessions: 8,
      );
      runs.currentRun = old;
      vm.state.value = vm.state.value.copyWith(activeRun: old, isCurrent: true);

      await vm.restartRun(targetSessions: 6);
      await pumpEventQueue();

      expect(runs.endCalls, ['u1'],
          reason: 'a current run is ended through the by-user path, which is '
              'the one that can reach it');
      expect(history.closeCalls.single.runId, 'live-1',
          reason: 'restart is the one action that ends and begins — the '
              'attempt being replaced is recorded, not discarded');
      expect(vm.state.value.activeRun?.programRunId, isNot('live-1'));
      expect(vm.state.value.activeRun?.programRunId,
          runs.starts.single.returned.programRunId,
          reason: 'the fresh run is the repository\'s, not one minted here');
      expect(vm.state.value.activeRun?.targetSessions, 6,
          reason: 'the config sheet the caller opened is what decides the new '
              'run\'s numbers');
      expect(vm.state.value.activeRun?.blockId, 'b1',
          reason: 'restarting a block restarts that block, not the program '
              'around it');
      expect(vm.state.value.isCurrent, isTrue);
      expect(vm.state.value.pausedRun, isNull,
          reason: 'the old run was ended, not paused — there is nothing to '
              'pick back up');
    });

    test('restarts a paused run without touching the current one', () async {
      runs.currentRun = testRun(programRunId: 'live-1', programId: 'p0');
      final old = testRun(programRunId: 'paused-1', isCurrent: false);
      runs.runsById[old.programRunId] = old;
      runs.pausedRuns.add(old);
      vm.state.value = vm.state.value.copyWith(pausedRun: old);

      await vm.restartRun(targetSessions: 6);
      await pumpEventQueue();

      expect(runs.endRunCalls, ['paused-1']);
      expect(runs.endCalls, isEmpty,
          reason: 'ending by user would have ended the other program\'s run');
      expect(history.closeCalls.single.runId, 'paused-1');
      expect(runs.pausedRuns.map((r) => r.programRunId), ['live-1'],
          reason: 'the begin superseded the live run — paused, never ended');
      expect(vm.state.value.activeRun?.programRunId,
          runs.starts.single.returned.programRunId);
    });

    test('a failed close still restarts, with a warning', () async {
      final old = testRun(programRunId: 'live-1');
      runs.currentRun = old;
      vm.state.value = vm.state.value.copyWith(activeRun: old, isCurrent: true);
      history.failClose = true;

      await vm.restartRun();
      await pumpEventQueue();

      expect(vm.state.value.historyWarning, isNotNull,
          reason: 'the lost record is real and invisible otherwise');
      expect(vm.state.value.activeRun, isNotNull,
          reason: 'the restart itself must not be blocked by a record that '
              'could not be written');
      expect(vm.state.value.error, isNull);
    });
  });

  group('anotherProgramIsPaused', () {
    // The one fact the confirmation cannot read from [ProgramDetailState]: it
    // is about the programs this screen is not showing.
    test('is true when a run of another program sits paused', () async {
      runs.pausedRuns.add(
          testRun(programRunId: 'theirs', programId: 'p2', isCurrent: false));

      expect(await vm.anotherProgramIsPaused(), isTrue);
    });

    test('does not count this program\'s own paused run', () async {
      runs.pausedRuns
          .add(testRun(programRunId: 'mine', programId: 'p1', isCurrent: false));

      expect(await vm.anotherProgramIsPaused(), isFalse,
          reason: 'the sentence it feeds is about what entering this program '
              'leaves alone, and this program is the one being entered');
    });

    test('a read that fails answers false rather than blocking the question',
        () async {
      runs.failFetchPaused = true;

      expect(await vm.anotherProgramIsPaused(), isFalse,
          reason: 'the paused clause is a courtesy — a question that could not '
              'be asked because a courtesy read failed would trade the real '
              'gate for a nicety');
    });
  });

  test('the close scope follows the run\'s shape', () async {
    await vm.setAsCurrent(blockId: 'b1');
    await vm.endCurrentRun();

    expect(
      history.closeCalls.single.blockId,
      'b1',
      reason:
          'a block run closes as that block\'s checkpoint — with the reason '
          'column gone, block_id is what says so',
    );
  });
}
