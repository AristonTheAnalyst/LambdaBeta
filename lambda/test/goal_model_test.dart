import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/goal.dart';

/// A goal's deadline and its adjustment history (2026-10-19): both round-trip
/// through the row's map, and both read as absent from a row written before
/// the columns existed — the shape every synced client will meet on first
/// launch after the migration.
void main() {
  Goal goalWith({
    DateTime? targetDate,
    List<GoalTargetDateChange> history = const [],
    DateTime? createdDate,
  }) => Goal(
    goalId: 'g1',
    userId: 'u1',
    text: 'Bench',
    exerciseId: 'e1',
    targetWeight: 100,
    targetReps: 5,
    targetDate: targetDate,
    targetDateHistory: history,
    createdDate: createdDate,
  );

  test('a deadline and its history survive the row map', () {
    final goal = goalWith(
      targetDate: DateTime(2026, 11, 1),
      createdDate: DateTime(2026, 10, 19, 9),
      history: [
        GoalTargetDateChange(
          from: null,
          to: DateTime(2026, 11, 1),
          changedAt: DateTime(2026, 10, 19, 9, 30),
        ),
        GoalTargetDateChange(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 12, 1),
          changedAt: DateTime(2026, 10, 25, 8),
        ),
      ],
    );

    final back = Goal.fromMap(goal.toMap());

    expect(back.targetDate, DateTime(2026, 11, 1));
    expect(back.targetDateHistory, hasLength(2));
    // Oldest first, and a NULL side stays NULL — "there was no deadline" and
    // "the deadline was cleared" both need to read as themselves.
    expect(back.targetDateHistory.first.from, isNull);
    expect(back.targetDateHistory.first.to, DateTime(2026, 11, 1));
    expect(back.targetDateHistory.last.from, DateTime(2026, 11, 1));
    expect(back.targetDateHistory.last.to, DateTime(2026, 12, 1));
    expect(back.targetDateHistory.last.changedAt, DateTime(2026, 10, 25, 8));
    // When the goal was said round-trips like any other date.
    expect(back.createdDate, DateTime(2026, 10, 19, 9));
  });

  test('a goal with neither writes NULL columns and reads them as absent', () {
    final map = goalWith().toMap();
    expect(map['target_date'], isNull);
    expect(
      map['target_date_history_json'],
      isNull,
      reason: 'never adjusted has one spelling on the row',
    );

    final back = Goal.fromMap(map);
    expect(back.targetDate, isNull);
    expect(back.targetDateHistory, isEmpty);
  });

  test('a row written before the columns existed reads as a goal with no '
      'deadline', () {
    // The map a pre-2026-10-19 row would produce — the keys simply absent.
    final back = Goal.fromMap({
      'goal_id': 'g1',
      'user_id': 'u1',
      'goal_text': 'Bench',
      'target_weight': 100,
      'target_reps': 5,
    });

    expect(back.targetDate, isNull);
    expect(back.targetDateHistory, isEmpty);
    expect(
      back.createdDate,
      isNull,
      reason: 'a document without the column reads as no creation date',
    );
  });

  test(
    'unreadable history reads as no history rather than failing the goal',
    () {
      expect(decodeGoalTargetDateHistory('not json'), isEmpty);
      expect(decodeGoalTargetDateHistory('{"a": 1}'), isEmpty);
      expect(decodeGoalTargetDateHistory(''), isEmpty);
      // A list holding junk keeps the entries it can read and drops the rest.
      expect(
        decodeGoalTargetDateHistory('[1, {"to": "2026-11-01T00:00:00.000"}]'),
        hasLength(1),
      );
    },
  );

  test('copyWith moves the deadline and carries the rest', () {
    final goal = goalWith(
      targetDate: DateTime(2026, 11, 1),
      createdDate: DateTime(2026, 10, 19),
    );

    final moved = goal.copyWith(
      targetDate: DateTime(2026, 12, 1),
      targetDateHistory: [
        GoalTargetDateChange(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 12, 1),
          changedAt: DateTime(2026, 10, 25),
        ),
      ],
    );
    expect(moved.targetDate, DateTime(2026, 12, 1));
    expect(moved.targetDateHistory, hasLength(1));
    expect(moved.exerciseId, 'e1', reason: 'everything else is carried');
    expect(moved.description, isNull);
    expect(
      moved.createdDate,
      DateTime(2026, 10, 19),
      reason: 'the creation date is stamped once and never rewritten',
    );

    final cleared = moved.copyWith(clearTargetDate: true);
    expect(cleared.targetDate, isNull);
    expect(
      cleared.targetDateHistory,
      hasLength(1),
      reason:
          'clearing the deadline is an adjustment, not an erasure — the '
          'history is passed explicitly and stays otherwise',
    );
  });

  test('dateOnly zeroes the clock so a day is a day', () {
    expect(dateOnly(DateTime(2026, 11, 1, 23, 59, 59)), DateTime(2026, 11, 1));
    expect(dateOnly(DateTime(2026, 11, 1)), DateTime(2026, 11, 1));
  });
}
