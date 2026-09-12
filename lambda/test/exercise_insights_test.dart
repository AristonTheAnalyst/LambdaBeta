import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/exercises/model/exercise_insights.dart';

PastSetRow _set(
  String id, {
  required String exerciseId,
  String? variationId,
  required double weight,
  required int reps,
  required DateTime date,
}) =>
    PastSetRow(
      sessionExerciseSetId: id,
      sessionExerciseId: id,
      sessionId: 'w',
      userId: 'u1',
      exerciseId: exerciseId,
      variationId: variationId,
      setNumber: 1,
      reps: [reps],
      sessionCreatedDate: date,
      weight: weight,
    );

void main() {
  final sets = [
    _set('s1', exerciseId: 'dips', weight: 0, reps: 13,
        date: DateTime(2026, 7, 1)),
    _set('s2', exerciseId: 'dips', weight: 5, reps: 8,
        date: DateTime(2026, 7, 15)),
    _set('s3', exerciseId: 'dips', variationId: 'v1', weight: 7.5, reps: 6,
        date: DateTime(2026, 7, 20)),
    _set('s4', exerciseId: 'bench', weight: 60, reps: 10,
        date: DateTime(2026, 7, 20)),
  ];

  test('setsScoped filters by exercise and variation', () {
    expect(setsScoped(sets, 'dips', null).length, 2);
    expect(setsScoped(sets, 'dips', 'v1').length, 1);
    expect(setsScoped(sets, 'bench', null).length, 1);
    expect(setsScoped(sets, 'missing', null), isEmpty);
  });

  test('variationsFor lists distinct variations in first-use order', () {
    // An exercise logged ONLY with a variation must still surface it —
    // regression for the dropdown showing nothing for variated-only data.
    final all = setsForExercise(sets, 'dips');
    final vs = variationsFor(all);
    expect(vs.map((v) => v.id), [null, 'v1']);
  });

  test('setsForExercise spans every variation; setsScoped(null) is '
      'no-variation only', () {
    final all = setsForExercise(sets, 'dips');
    expect(all.length, 3);
    expect(setsScoped(sets, 'dips', null).length, 2);
    expect(setsScoped(sets, 'dips', 'v1').length, 1);
  });

  test('prsInWindow lists every PR set in the window, newest first, one rung per set', () {
    final scoped = setsScoped(sets, 'dips', null);
    final prs = prsInWindow(
      scoped,
      DateTime(2026, 7, 1),
      DateTime(2026, 8, 1),
    );
    // One event per frontier-extending set — the journey shows ONE rung
    // per set.
    expect(prs.length, 2);
    expect(prs.first.reps, 8); // newest first
    expect(prs.first.weight, 5);
    expect(prs.last.weight, 0);
  });

  test('activeWeeksInWindow counts only weeks with training', () {
    final scoped = [
      _set('a', exerciseId: 'bench', weight: 60, reps: 5,
          date: DateTime(2026, 8, 3)), // Mon week 1
      _set('b', exerciseId: 'bench', weight: 62.5, reps: 5,
          date: DateTime(2026, 8, 5)), // same week
      _set('c', exerciseId: 'bench', weight: 65, reps: 5,
          date: DateTime(2026, 8, 11)), // week 2
      _set('d', exerciseId: 'bench', weight: 70, reps: 5,
          date: DateTime(2026, 7, 1)), // outside window
    ];
    expect(
      activeWeeksInWindow(
        scoped,
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 15),
      ),
      2,
    );
  });

  test('bestInWindow and bestOnDay pick weight then reps', () {
    final scoped = setsScoped(sets, 'dips', null);
    final best = bestInWindow(
      scoped,
      DateTime(2026, 7, 1),
      DateTime(2026, 8, 1),
    )!;
    expect(best.weight, 5);
    expect(best.reps, 8);

    final onDay = bestOnDay(scoped, DateTime(2026, 7, 15))!;
    expect(onDay.weight, 5);
    expect(bestOnDay(scoped, DateTime(2026, 7, 2)), isNull);
  });
}
