import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_run.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/features/programs/model/achievements_derivation.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';
import 'package:lambda/features/programs/model/program_run_lifecycle.dart';

import 'support/fake_program_repos.dart';

/// The run lifecycle's contract, in one place.
///
/// This file is the spec for the defect that made runs unaddressable: the id a
/// screen mints is never the id the repository stores, so every later write —
/// a config edit, the closing record — addresses a run that does not exist.
/// The lifecycle only ever returns and re-uses the repository's run, and these
/// tests hold it to that.
void main() {
  late FakeProgramRunRepository runs;
  late FakeProgramHistoryRepository history;
  late FakeAchievementsDerivation derivation;
  late ProgramRunLifecycle lifecycle;

  setUp(() {
    runs = FakeProgramRunRepository();
    history = FakeProgramHistoryRepository();
    derivation = FakeAchievementsDerivation();
    lifecycle = ProgramRunLifecycle(
      runRepo: runs,
      historyRepo: history,
      derivation: derivation,
    );
  });

  group('begin', () {
    test('returns the repository\'s run, never one minted above it', () async {
      final result = await lifecycle.begin(userId: 'u1', programId: 'p1');

      expect(
        result.run.programRunId,
        'run-1',
        reason:
            'the id must be the one the repository inserted — a caller '
            'keeping its own id is what silently broke every later write',
      );
      expect(
        identical(result.run, runs.starts.single.returned),
        isTrue,
        reason: 'the returned object IS the repository\'s run',
      );
      expect(
        result.pausedRun,
        isNull,
        reason: 'nothing was running, so nothing was stepped aside',
      );
    });

    test('pauses the run it replaced, and cuts no record', () async {
      runs.currentRun = testRun(programRunId: 'old-run', programId: 'p0');

      final result = await lifecycle.begin(userId: 'u1', programId: 'p1');

      expect(
        history.closeCalls,
        isEmpty,
        reason:
            'a superseded run is stepped aside, not finished — ending it '
            'here is what made switching destroy an attempt four seconds in',
      );
      expect(
        result.pausedRun?.programRunId,
        'old-run',
        reason:
            'the caller needs to know which run was left behind so it '
            'can say so ("pick it back up any time")',
      );
      expect(result.pausedRun?.isPaused, isTrue);
      expect(
        result.pausedRun?.programId,
        'p0',
        reason:
            'it can belong to a different program than the one that '
            'replaced it',
      );
    });

    test('a replaced block run keeps its block while paused', () async {
      runs.currentRun = testRun(
        programRunId: 'old-run',
        programId: 'p0',
        blockId: 'b1',
        targetSessions: 6,
      );

      final result = await lifecycle.begin(userId: 'u1', programId: 'p1');

      expect(
        result.pausedRun?.blockId,
        'b1',
        reason:
            'resuming has to return to the block it was in — a pause '
            'that dropped the block would silently un-block the run',
      );
      expect(
        result.pausedRun?.targetSessions,
        6,
        reason: 'the config survives a pause; that is the point of one',
      );
      expect(history.closeCalls, isEmpty);
    });

    test(
      'beginning onto the run that is already current pauses nothing',
      () async {
        // A retry that got as far as inserting and is being re-run. Stepping it
        // aside would leave the same run both current and paused.
        final existing = testRun(programRunId: 'run-1');
        runs.currentRun = existing;
        runs.startReturns = existing;

        final result = await lifecycle.begin(userId: 'u1', programId: 'p1');

        expect(result.pausedRun, isNull);
        expect(runs.pausedRuns, isEmpty);
      },
    );

    test('a failed start pauses nothing and cuts no record', () async {
      runs.currentRun = testRun(programRunId: 'old-run');
      final throwing = _ThrowingRuns();

      final lifecycle = ProgramRunLifecycle(
        runRepo: throwing,
        historyRepo: history,
        derivation: derivation,
      );

      await expectLater(
        lifecycle.begin(userId: 'u1', programId: 'p1'),
        throwsA(isA<StateError>()),
        reason:
            'the caller rolls the UI back on a failed begin — it must not '
            'be told the begin happened',
      );
      expect(
        history.closeCalls,
        isEmpty,
        reason: 'nothing started, so nothing was replaced',
      );
      expect(
        runs.pausedRuns,
        isEmpty,
        reason:
            'the pause rides on the start; a start that never landed '
            'must leave the running program running',
      );
    });
  });

  group('end', () {
    test('ends the current run and closes it with the same id', () async {
      runs.currentRun = testRun(programRunId: 'run-9', blockId: 'b2');

      final warning = await lifecycle.end(userId: 'u1');

      expect(runs.endCalls, ['u1']);
      expect(warning, isNull);
      final call = history.closeCalls.single;
      expect(call.runId, 'run-9');
      expect(
        call.blockId,
        'b2',
        reason:
            'a block run closes as that block\'s checkpoint — with the reason '
            'column gone, block_id is the only thing that says so',
      );
    });

    test('with nothing running is a quiet no-op', () async {
      final warning = await lifecycle.end(userId: 'u1');

      expect(
        runs.endCalls,
        ['u1'],
        reason:
            'the end still runs — it is what guarantees nothing is left '
            'current',
      );
      expect(warning, isNull);
      expect(history.closeCalls, isEmpty);
    });

    test('a close that fails still ends the run, and says so', () async {
      runs.currentRun = testRun(programRunId: 'run-9');
      history.failClose = true;

      final warning = await lifecycle.end(userId: 'u1');

      expect(
        runs.endCalls,
        ['u1'],
        reason:
            'the run is over — a record that failed afterwards must not '
            'leave it looking active',
      );
      expect(
        warning,
        isNotNull,
        reason: 'the lost record is real; the caller surfaces this',
      );
    });
  });

  group('endRun', () {
    test('ends a paused run by id and records what it got to', () async {
      final paused = testRun(programRunId: 'paused-1', isCurrent: false);
      runs.runsById[paused.programRunId] = paused;

      final warning = await lifecycle.endRun(paused, userId: 'u1');

      expect(
        runs.endRunCalls,
        ['paused-1'],
        reason:
            'a paused run is never the current one, so [end] can never '
            'reach it — ending one has to be asked for by name',
      );
      expect(warning, isNull);
      final call = history.closeCalls.single;
      expect(
        call.runId,
        'paused-1',
        reason: 'the record belongs to the attempt being ended',
      );
      expect(
        call.blockId,
        isNull,
        reason:
            'a program close carries no block — NULL block_id IS the program '
            'scope',
      );
      expect(
        runs.pausedRuns,
        isEmpty,
        reason: 'an ended run is history, not something to pick back up',
      );
    });

    test('a paused block run records a block end, block named', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        isCurrent: false,
        blockId: 'b2',
      );

      await lifecycle.endRun(paused, userId: 'u1');

      expect(
        history.closeCalls.single.blockId,
        'b2',
        reason: 'the end is scoped to the block that ran',
      );
    });

    test('leaves the current run alone', () async {
      final current = testRun(programRunId: 'live-1');
      runs.currentRun = current;
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p0',
        isCurrent: false,
      );
      runs.runsById[paused.programRunId] = paused;

      await lifecycle.endRun(paused, userId: 'u1');

      expect(
        runs.currentRun?.programRunId,
        'live-1',
        reason:
            'ending a paused run is not a reason to disturb the one you '
            'are actually doing',
      );
      expect(
        runs.endCalls,
        isEmpty,
        reason: 'the by-user end would have ended the live run instead',
      );
    });
  });

  group('resume', () {
    test('makes the paused run current again, same id and config', () async {
      final paused = testRun(
        programRunId: 'paused-1',
        isCurrent: false,
        blockId: 'b1',
        targetSessions: 6,
      );
      runs.runsById[paused.programRunId] = paused;
      runs.pausedRuns.add(paused);

      await lifecycle.resume(paused, userId: 'u1');

      expect(runs.resumeCalls, ['paused-1']);
      expect(
        runs.currentRun?.programRunId,
        'paused-1',
        reason:
            'resuming is returning to the same run, not beginning a new '
            'one — progress and the workout cursor come back with it',
      );
      expect(runs.currentRun?.blockId, 'b1');
      expect(runs.currentRun?.targetSessions, 6);
      expect(runs.pausedRuns, isEmpty);
      expect(
        history.closeCalls,
        isEmpty,
        reason: 'nothing ends when a run is picked back up',
      );
    });

    test(
      'pauses whatever was current first, so only one run is current',
      () async {
        runs.currentRun = testRun(programRunId: 'live-1', programId: 'p0');
        final paused = testRun(
          programRunId: 'paused-1',
          programId: 'p1',
          isCurrent: false,
        );
        runs.runsById[paused.programRunId] = paused;
        runs.pausedRuns.add(paused);

        await lifecycle.resume(paused, userId: 'u1');

        expect(runs.currentRun?.programRunId, 'paused-1');
        expect(
          runs.pausedRuns.map((r) => r.programRunId),
          ['live-1'],
          reason:
              'the run that lost its place is paused, not ended — resuming '
              'one program must not destroy another',
        );
      },
    );
  });

  group('restart', () {
    test('ends the old run with its record, then begins a fresh one', () async {
      final old = testRun(
        programRunId: 'live-1',
        targetSessions: 8,
        blockId: 'b1',
      );
      runs.currentRun = old;

      final result = await lifecycle.restart(
        oldRun: old,
        userId: 'u1',
        targetSessions: 8,
      );

      expect(
        runs.endCalls,
        ['u1'],
        reason:
            'a current run is ended through the by-user path, which is '
            'the one that can reach it',
      );
      expect(
        history.closeCalls.single.runId,
        'live-1',
        reason:
            'the attempt being replaced is recorded — a restart is the '
            'one action that ends and begins, so nothing is lost by it',
      );
      expect(
        result.run.programRunId,
        isNot('live-1'),
        reason: 'a restart is a new run, with nothing carried over',
      );
      expect(
        runs.starts.single.blockId,
        'b1',
        reason:
            'restarting a block restarts that block, not the program '
            'around it',
      );
      expect(result.run.isCurrent, isTrue);
      expect(runs.currentRun?.programRunId, result.run.programRunId);
      expect(
        result.pausedRun,
        isNull,
        reason:
            'the old run was ended, not paused — it is not something to '
            'pick back up',
      );
      expect(result.warning, isNull);
    });

    test('restarts a paused run without touching the current one', () async {
      runs.currentRun = testRun(programRunId: 'live-1', programId: 'p0');
      final paused = testRun(
        programRunId: 'paused-1',
        programId: 'p1',
        isCurrent: false,
        blockId: 'b1',
      );
      runs.runsById[paused.programRunId] = paused;
      runs.pausedRuns.add(paused);

      final result = await lifecycle.restart(oldRun: paused, userId: 'u1');

      expect(runs.endRunCalls, ['paused-1']);
      expect(
        runs.endCalls,
        isEmpty,
        reason: 'ending the paused run by user would have ended the live one',
      );
      expect(history.closeCalls.single.runId, 'paused-1');
      // b1 is paused-1's block, and p1's new run carries it.
      expect(result.run.programId, 'p1');
      expect(result.run.blockId, 'b1');
      expect(runs.pausedRuns.map((r) => r.programRunId), [
        'live-1',
      ], reason: 'the begin superseded the live run — paused, never ended');
    });

    test('a failed close still starts the new run, with a warning', () async {
      final old = testRun(programRunId: 'live-1');
      runs.currentRun = old;
      history.failClose = true;

      final result = await lifecycle.restart(oldRun: old, userId: 'u1');

      expect(
        result.warning,
        isNotNull,
        reason: 'the lost record is real and invisible otherwise',
      );
      expect(
        result.run.programRunId,
        isNot('live-1'),
        reason:
            'the restart itself must not be blocked by a record that '
            'could not be written',
      );
      expect(runs.currentRun?.programRunId, result.run.programRunId);
    });
  });

  group('close', () {
    test('derives from the run\'s start when there is no checkpoint', () async {
      // A first-ever run: no reviews, no revisions. The window used to open at
      // `now`, so the record of everything the run produced was empty.
      final run = testRun(startedDate: DateTime(2026, 2, 1, 9));

      await lifecycle.close(run, userId: 'u1');

      expect(
        history.fallbacks.single,
        run.startedDate,
        reason: 'the fallback is the run\'s own start',
      );
      expect(derivation.calls.single.from, run.startedDate);
    });

    test('an existing checkpoint wins over the run start', () async {
      history.checkpoint = DateTime(2026, 2, 20);
      final run = testRun(startedDate: DateTime(2026, 2, 1, 9));

      await lifecycle.close(run, userId: 'u1');

      expect(
        derivation.calls.single.from,
        DateTime(2026, 2, 20),
        reason:
            'the window opens at the last checkpoint, not the run — '
            'achievements already reported must not be claimed again',
      );
    });

    test('scopes the derivation and the record to the run\'s block', () async {
      final run = testRun(programRunId: 'run-3', blockId: 'b1');

      await lifecycle.close(run, userId: 'u1');

      // The scope reaches the window as well as the derivation: a block's
      // record opens at that block's last checkpoint, so a program-level
      // review taken mid-block cannot swallow the block's training into a
      // report that was about something else.
      expect(history.scopes.single, 'b1');
      expect(
        derivation.calls.single.blockId,
        'b1',
        reason:
            'a block\'s record names the goals that were in force for '
            'it',
      );
      expect(history.closeCalls.single.blockId, 'b1');
    });

    test('a failing derivation is a warning, not a throw', () async {
      final run = testRun();

      final lifecycle = ProgramRunLifecycle(
        runRepo: runs,
        historyRepo: history,
        derivation: _ThrowingDerivation(),
      );

      final warning = await lifecycle.close(run, userId: 'u1');

      expect(warning, isNotNull);
    });
  });

  group('updateConfig', () {
    test(
      'writes against the repository\'s id and preserves the block',
      () async {
        final run = testRun(
          programRunId: 'run-4',
          blockId: 'b1',
          targetSessions: 8,
        );

        final updated = await lifecycle.updateConfig(run, targetSessions: 12);

        expect(runs.updateConfigCalls.single.programRunId, 'run-4');
        expect(runs.updateConfigCalls.single.values['targetSessions'], 12);
        expect(updated.targetSessions, 12);
        expect(
          updated.blockId,
          'b1',
          reason:
              'editing the duration must not un-block a block run — the '
              'rebuilt run kept only the fields it was handed, which silently '
              'dropped the block',
        );
        expect(updated.programRunId, 'run-4');
        expect(updated.startedDate, run.startedDate);
      },
    );

    test('withConfig clears only what the caller asked to clear', () {
      final run = testRun(
        programRunId: 'run-5',
        blockId: 'b3',
        targetSessions: 6,
        targetWeeks: 4,
        endDate: DateTime(2026, 6, 1),
        progressionMode: 'frequency',
      );

      final updated = ProgramRunLifecycle.withConfig(
        run,
        targetSessions: 10,
        clearWeeks: true,
      );

      expect(updated.targetSessions, 10);
      expect(updated.targetWeeks, isNull);
      expect(
        updated.endDate,
        DateTime(2026, 6, 1),
        reason: 'not mentioned, so untouched',
      );
      expect(updated.progressionMode, 'frequency');
      expect(updated.blockId, 'b3');
      expect(updated.isCurrent, run.isCurrent);
      expect(updated.endedDate, run.endedDate);
    });
  });
}

class _ThrowingRuns implements ProgramRunRepository {
  @override
  Future<ProgramRun?> getCurrentRun(String userId) async => null;

  @override
  Future<ProgramRun> startProgramRun(
    String userId,
    String programId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async => throw StateError('insert failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingDerivation implements AchievementsDerivation {
  @override
  Future<ProgramAchievements> derive({
    required String userId,
    required DateTime from,
    required String programId,
    DateTime? until,
    String? blockId,
    String? sessionId,
  }) async => throw StateError('derive failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
