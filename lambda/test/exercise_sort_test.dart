import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_usage.dart';
import 'package:lambda/features/exercises/viewmodel/exercise_viewmodel.dart';

/// The library lists' sort. The default (last used, descending) is the order
/// the lists have always had; the criteria the sort menu adds are pinned
/// here — including the rule that a never-used entry sinks in EITHER
/// direction (a missing date is no data, not a very long time ago).
///
/// Usage is written as the repository's own read shapes it: dated entries
/// carry a `lastUsed`, never-used ones are still present, with null.
ExerciseState _state({
  ExerciseSortCriterion sort = ExerciseSortCriterion.lastUsed,
  bool descending = true,
}) => ExerciseState(
  exercises: const [
    CustomExercise(exerciseId: 'ex-bench', userId: 'u1', name: 'Bench Press'),
    CustomExercise(exerciseId: 'ex-dead', userId: 'u1', name: 'Deadlift'),
    CustomExercise(exerciseId: 'ex-squat', userId: 'u1', name: 'Squat'),
    CustomExercise(exerciseId: 'ex-zerch', userId: 'u1', name: 'Zercher'),
  ],
  variations: const [
    CustomVariation(variationId: 'v-tempo', userId: 'u1', name: 'Tempo'),
    CustomVariation(variationId: 'v-pause', userId: 'u1', name: 'Paused'),
  ],
  usage: {
    // Bench and Zercher share a date, so the name tiebreak is load-bearing.
    'ex-bench': ExerciseUsage(sets: 12, lastUsed: DateTime(2026, 9, 20)),
    'ex-dead': ExerciseUsage(sets: 3, lastUsed: DateTime(2026, 8, 1)),
    'ex-zerch': ExerciseUsage(sets: 7, lastUsed: DateTime(2026, 9, 20)),
    'ex-squat': const ExerciseUsage(),
    'v-pause': ExerciseUsage(sets: 5, lastUsed: DateTime(2026, 9, 1)),
    'v-tempo': const ExerciseUsage(),
  },
  exSort: sort,
  exSortDesc: descending,
  varSort: sort,
  varSortDesc: descending,
);

List<String> _names(ExerciseState s) =>
    [for (final e in s.sortedExercises) e.name];
List<String> _varNames(ExerciseState s) =>
    [for (final v in s.sortedVariations) v.name];

void main() {
  test('last used, descending — the historical default', () {
    expect(_names(_state()), ['Bench Press', 'Zercher', 'Deadlift', 'Squat'],
        reason: 'newest first, the date tie broken by name, never-used last');
  });

  test('last used, ascending — never-used still sinks', () {
    expect(_names(_state(descending: false)),
        ['Deadlift', 'Bench Press', 'Zercher', 'Squat'],
        reason: 'oldest first among dated entries; a never-used one is not '
            '"infinitely long ago", it is absent, and absent has no place at '
            'the head of a chronology');
  });

  test('A–Z in both directions', () {
    expect(_names(_state(sort: ExerciseSortCriterion.name, descending: false)),
        ['Bench Press', 'Deadlift', 'Squat', 'Zercher']);
    expect(_names(_state(sort: ExerciseSortCriterion.name)), [
      'Zercher',
      'Squat',
      'Deadlift',
      'Bench Press',
    ]);
  });

  test('most used, descending', () {
    expect(_names(_state(sort: ExerciseSortCriterion.mostUsed)),
        ['Bench Press', 'Zercher', 'Deadlift', 'Squat'],
        reason: '12, 7, 3, then the never-used 0');
  });

  test('most used, ascending — the never-used ARE the least used', () {
    expect(_names(_state(sort: ExerciseSortCriterion.mostUsed, descending: false)),
        ['Squat', 'Deadlift', 'Zercher', 'Bench Press'],
        reason: 'unlike a missing date, a zero count is data: "least used '
            'first" leads with the one that was never used at all');
  });

  test('search filters before sorting, not after', () {
    final s = _state().copyWith(exSearch: 'e');
    expect(_names(s), ['Bench Press', 'Zercher', 'Deadlift'],
        reason: 'Squat is filtered out of view, and sorted out with it');
  });

  test('the two lists sort independently', () {
    final s = _state();
    expect(_varNames(s), ['Paused', 'Tempo'],
        reason: 'variations read the same criteria — used first, never last');
  });

  test('changing a sort lands on the state and resets that list\'s page', () {
    final vm = ExerciseViewModel();
    addTearDown(vm.dispose);
    vm.nextExPage();
    vm.nextExPage();

    vm.setExSort(ExerciseSortCriterion.name, false);

    expect(vm.state.value.exPage, 0,
        reason: 'page 3 of one ordering is not page 3 of another');
    expect(vm.state.value.exSort, ExerciseSortCriterion.name);
    expect(vm.state.value.exSortDesc, isFalse);
    expect(vm.state.value.varSort, ExerciseSortCriterion.lastUsed,
        reason: 'the variations list was not asked to change');
  });
}
