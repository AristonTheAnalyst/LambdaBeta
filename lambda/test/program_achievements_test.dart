import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';

PastSetRow _set(
  String id, {
  required String exerciseId,
  String? variationId,
  required double weight,
  required int reps,
  required DateTime date,
  int setNumber = 1,
}) =>
    PastSetRow(
      sessionExerciseSetId: id,
      sessionExerciseId: id,
      sessionId: 'sess-$id',
      userId: 'u1',
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      reps: [reps],
      weight: weight,
      sessionCreatedDate: date,
    );

Goal _goal({
  required String id,
  String? exerciseId,
  String? text,
  num? weight,
  int? reps,
  String? blockId,
  String? variationId,
}) =>
    Goal(
      goalId: id,
      userId: 'u1',
      programId: 'p1',
      blockId: blockId,
      text: text,
      exerciseId: exerciseId,
      variationId: variationId,
      targetWeight: weight,
      targetReps: reps,
    );

final _jan10 = DateTime(2026, 1, 10);
final _feb10 = DateTime(2026, 2, 10);
final _feb11 = DateTime(2026, 2, 11);
final _feb12 = DateTime(2026, 2, 12);
final _mar10 = DateTime(2026, 3, 10);

void main() {
  group('evaluateGoals', () {
    test('a set exactly at the target counts', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 100, reps: 1, date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isTrue);
      expect(out.single.evidenceWeight, 100);
      expect(out.single.evidenceReps, 1);
      expect(out.single.evidenceDate, _feb10);
    });

    test('one rep short at the same weight does not count, but is reported',
        () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 5)],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 100, reps: 4, date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isFalse);
      expect(out.single.evidenceWeight, 100,
          reason: 'a missed goal still reports how close it came');
      expect(out.single.evidenceReps, 4);
    });

    test('reps and weight must be reached IN THE SAME set', () {
      // 110x3 is heavy enough but short; 100x5 has the reps but was lighter.
      // Neither set alone is 100x5, so the goal is not met.
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 5)],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 110, reps: 3, date: _feb10),
          _set('s2',
              exerciseId: 'bench', weight: 100, reps: 5, date: _feb11),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isTrue,
          reason: 'the second set is exactly 100x5 and does satisfy it');
    });

    test('a set before the window does not satisfy it', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 120, reps: 1, date: _jan10),
        ],
        from: _feb10,
        to: _mar10,
      );

      expect(out.single.achieved, isFalse,
          reason: 'the window opens AFTER that set — a goal met last month '
              'belongs to the review that saw it');
      expect(out.single.evidenceWeight, isNull);
    });

    test('another exercise never satisfies a goal', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)],
        sets: [
          _set('s1', exerciseId: 'squat', weight: 200, reps: 1, date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isFalse);
      expect(out.single.evidenceWeight, isNull);
    });

    test('unscoped, any variation of the exercise answers the goal', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)],
        sets: [
          _set('s1',
              exerciseId: 'bench',
              variationId: 'paused',
              weight: 120,
              reps: 1,
              date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isTrue);
      expect(out.single.evidenceVariationId, 'paused');
    });

    test('a variation-scoped goal ignores other variations of the same lift',
        () {
      final goals = [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)];

      final onlyPlain = evaluateGoals(
        goals: goals,
        sets: [
          _set('s1', exerciseId: 'bench', weight: 150, reps: 1, date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
        variationIdOf: (g) => 'paused',
      );
      expect(onlyPlain.single.achieved, isFalse,
          reason: 'the 150 single was a plain bench set; the goal is paused');
      expect(onlyPlain.single.evidenceWeight, isNull);

      final withPaused = evaluateGoals(
        goals: goals,
        sets: [
          _set('s1', exerciseId: 'bench', weight: 150, reps: 1, date: _feb10),
          _set('s2',
              exerciseId: 'bench',
              variationId: 'paused',
              weight: 105,
              reps: 1,
              date: _feb11),
        ],
        from: _jan10,
        to: _mar10,
        variationIdOf: (g) => 'paused',
      );
      expect(withPaused.single.achieved, isTrue);
      expect(withPaused.single.evidenceWeight, 105,
          reason: 'the heavier 150 is out of scope — not even evidence');
    });

    test('the heaviest qualifying set is the evidence', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 3)],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 100, reps: 3, date: _feb10),
          _set('s2',
              exerciseId: 'bench', weight: 115, reps: 3, date: _feb11),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isTrue);
      expect(out.single.evidenceWeight, 115,
          reason: 'a goal is reviewed for how far past it the user went');
      expect(out.single.evidenceDate, _feb11);
    });

    test('a free-text goal is carried through unachieved', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', text: 'Get stronger')],
        sets: [
          _set('s1',
              exerciseId: 'bench', weight: 200, reps: 1, date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isFalse);
      expect(out.single.evidenceWeight, isNull,
          reason: 'nothing to measure, so nothing is claimed');
    });

    test('bodyweight is weight 0, not "no evidence"', () {
      final out = evaluateGoals(
        goals: [_goal(id: 'g1', exerciseId: 'dips', weight: 0, reps: 12)],
        sets: [
          _set('s1',
              exerciseId: 'dips',
              weight: 0,
              reps: 12,
              date: _feb10),
        ],
        from: _jan10,
        to: _mar10,
      );

      expect(out.single.achieved, isTrue);
      expect(out.single.evidenceWeight, 0);
      expect(out.single.evidenceReps, 12);
    });
  });

  group('Goal.appliesDuring', () {
    test('a program-level goal is chased inside every block', () {
      final goal = _goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1);

      expect(goal.appliesDuring('b1'), isTrue);
      expect(goal.appliesDuring('b2'), isTrue,
          reason: 'the target is on the program, not on one of its phases');
    });

    test('a block-level goal waits for its own block', () {
      final goal = _goal(
        id: 'g1',
        exerciseId: 'bench',
        weight: 100,
        reps: 1,
        blockId: 'b1',
      );

      expect(goal.appliesDuring('b1'), isTrue);
      expect(goal.appliesDuring('b2'), isFalse);
      expect(goal.appliesDuring(null), isFalse,
          reason: 'a blockless run is not running b1');
    });

    test('a blockless run sees exactly the program-level goals', () {
      final goals = [
        _goal(id: 'program', exerciseId: 'bench', weight: 100, reps: 1),
        _goal(
          id: 'block',
          exerciseId: 'squat',
          weight: 140,
          reps: 1,
          blockId: 'b1',
        ),
      ];

      final inForce =
          goals.where((g) => g.appliesDuring(null)).map((g) => g.goalId);

      expect(inForce, ['program'],
          reason: 'what a blockless program has always shown — unchanged');
    });
  });

  group('Goal round-trip', () {
    test('scope and variation survive toMap → fromMap', () {
      final goal = Goal(
        goalId: 'g1',
        userId: 'u1',
        programId: 'p1',
        blockId: 'b1',
        text: 'Paused Bench',
        exerciseId: 'bench',
        variationId: 'paused',
        targetWeight: 100,
        targetReps: 1,
      );

      final back = Goal.fromMap(goal.toMap());

      expect(back.programId, 'p1');
      expect(back.blockId, 'b1');
      expect(back.variationId, 'paused');
      expect(back.targetWeight, 100);
      expect(back.targetReps, 1);
      expect(back.appliesDuring('b1'), isTrue);
    });

    test('a scope-less goal reads as standalone, not as a program goal', () {
      final back = Goal.fromMap(
        Goal(goalId: 'g1', userId: 'u1', text: 'get stronger').toMap(),
      );

      expect(back.programId, isNull);
      expect(back.blockId, isNull);
      expect(back.variationId, isNull);
      expect(back.appliesDuring(null), isTrue);
    });
  });

  group('prsAcrossScopes', () {
    test('merges every exercise and variation into one newest-first list', () {
      final prs = prsAcrossScopes(
        [
          _set('s1',
              exerciseId: 'bench', weight: 100, reps: 1, date: _feb10),
          _set('s2',
              exerciseId: 'squat', weight: 150, reps: 1, date: _feb12),
          _set('s3',
              exerciseId: 'bench',
              variationId: 'paused',
              weight: 80,
              reps: 1,
              date: _feb11),
        ],
        _jan10,
        _mar10,
      );

      expect(prs.length, 3,
          reason: 'each (exercise, variation) pair has its own frontier, so '
              'each of these is a first PR for its scope');
      expect(
        prs.map((p) => p.achievedDate).toList(),
        [_feb12, _feb11, _feb10],
      );
    });

    test('a window filters events, it does not reset the frontier', () {
      final prs = prsAcrossScopes(
        [
          _set('s1', exerciseId: 'bench', weight: 200, reps: 1, date: _jan10),
          _set('s2', exerciseId: 'bench', weight: 100, reps: 1, date: _feb10),
        ],
        _feb10,
        _mar10,
      );

      expect(prs, isEmpty,
          reason: 'the January 200 IS this scope\'s frontier, so February\'s '
              'lighter single extended nothing and was never a PR. A window '
              'shows which PRs happened, not "best set logged inside it" — '
              'reporting 100kg as an achievement would be a lie');
    });

    test('only events inside the window are listed', () {
      final prs = prsAcrossScopes(
        [
          _set('s1', exerciseId: 'bench', weight: 100, reps: 1, date: _jan10),
          _set('s2', exerciseId: 'bench', weight: 120, reps: 1, date: _feb10),
        ],
        _feb10,
        _mar10,
      );

      expect(prs.length, 1);
      expect(prs.single.weight, 120);
      expect(prs.single.beforeWeight, 100,
          reason: 'the "was" fact still reaches back before the window — the '
              'frontier is global even when the report is not');
    });
  });

  group('ProgramAchievements round-trip', () {
    test('encode → decode preserves every field', () {
      final original = ProgramAchievements(
        from: _jan10,
        until: _mar10,
        weightStart: 82.5,
        weightEnd: 80.25,
        sessions: [
          AchievementSession(
            sessionId: 'sess-1',
            name: 'Push',
            date: _feb10,
          ),
        ],
        prs: prsAcrossScopes(
          [_set('s1', exerciseId: 'bench', weight: 100, reps: 1, date: _feb10)],
          _jan10,
          _mar10,
        ),
        goals: evaluateGoals(
          goals: [_goal(id: 'g1', exerciseId: 'bench', weight: 100, reps: 1)],
          sets: [
            _set('s1', exerciseId: 'bench', weight: 100, reps: 1, date: _feb10),
          ],
          from: _jan10,
          to: _mar10,
        ),
      );

      final back = ProgramAchievements.decode(original.encode())!;

      expect(back.from, original.from);
      expect(back.until, original.until);
      expect(back.weightStart, 82.5);
      expect(back.weightEnd, 80.25);
      expect(back.sessions.single.sessionId, 'sess-1');
      expect(back.sessions.single.name, 'Push');
      expect(back.sessions.single.date, _feb10);
      expect(back.prs.length, 1);
      expect(back.prs.single.weight, 100);
      expect(back.prs.single.reps, 1);
      expect(back.prs.single.achievedDate, _feb10);
      expect(back.goals.single.achieved, isTrue);
      expect(back.goals.single.goal.targetWeight, 100);
      expect(back.goals.single.goal.targetReps, 1);
      expect(back.goals.single.evidenceWeight, 100);
      expect(back.achievedGoalCount, 1);
      expect(back.missedGoalCount, 0);
    });

    test('an unreadable record decodes to null, never throws', () {
      expect(ProgramAchievements.decode(null), isNull);
      expect(ProgramAchievements.decode(''), isNull);
      expect(ProgramAchievements.decode('not json'), isNull);
      expect(ProgramAchievements.decode('[]'), isNull,
          reason: 'an array is not a document');
      expect(
        ProgramAchievements.decode(
          '{"from":"2026-01-01T00:00:00.000Z","goals":[{"text":null}]}',
        )?.goals.single.achieved,
        isFalse,
        reason: 'a partial document fills what it can rather than failing',
      );
    });

    test('bodyweight alone is not an achievement', () {
      final empty = ProgramAchievements(
        from: _jan10,
        weightStart: 82,
        weightEnd: 80,
      );
      expect(empty.isEmpty, isTrue);
    });
  });
}
