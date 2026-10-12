import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_usage.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/features/exercises/viewmodel/exercise_viewmodel.dart';

/// The library's read economy (2026-10-13): one load is three reads —
/// exercises, variations, usage (with the catalog passed in, never
/// re-read) — and mutations patch state in place instead of re-reading
/// everything.
class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  int exerciseReads = 0;
  int variationReads = 0;
  int usageReads = 0;

  final exercises = <CustomExercise>[
    const CustomExercise(exerciseId: 'ex1', userId: 'u1', name: 'Bench Press'),
  ];
  final variations = <CustomVariation>[
    const CustomVariation(variationId: 'v1', userId: 'u1', name: 'Paused'),
  ];

  @override
  Future<List<CustomExercise>> fetchExercises(String userId) async {
    exerciseReads++;
    return List.of(exercises);
  }

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async {
    variationReads++;
    return List.of(variations);
  }

  @override
  Future<Map<String, ExerciseUsage>> fetchUsage(
    String userId, {
    List<CustomExercise>? exercises,
    List<CustomVariation>? variations,
  }) async {
    usageReads++;
    return {
      for (final e in exercises ?? this.exercises)
        e.exerciseId: const ExerciseUsage(),
      for (final v in variations ?? this.variations)
        v.variationId: const ExerciseUsage(),
    };
  }

  @override
  Future<void> updateExercise(String exerciseId, String name) async {
    final i = exercises.indexWhere((e) => e.exerciseId == exerciseId);
    exercises[i] = exercises[i].copyWith(name: name);
  }

  @override
  Future<int> exerciseUsageCount(String exerciseId) async => 0;

  @override
  Future<void> hardDeleteExercise(String exerciseId) async {
    exercises.removeWhere((e) => e.exerciseId == exerciseId);
  }

  @override
  Future<void> deactivateExercise(String exerciseId) async {
    exercises.removeWhere((e) => e.exerciseId == exerciseId);
  }

  @override
  Future<CustomExercise> createExercise(String userId, String name) async {
    final ex = CustomExercise(
      exerciseId: 'ex-${exercises.length + 1}',
      userId: userId,
      name: name,
    );
    exercises.add(ex);
    return ex;
  }

  @override
  Future<CustomExercise?> findExerciseByName(String userId, String name) async {
    for (final e in exercises) {
      if (e.name == name) return e;
    }
    return null;
  }

  @override
  Future<void> reactivateExercise(String exerciseId) async {}

  @override
  Future<void> updateVariation(String variationId, String name) async {}

  @override
  Future<int> variationUsageCount(String variationId) async => 0;

  @override
  Future<void> hardDeleteVariation(String variationId) async {
    variations.removeWhere((v) => v.variationId == variationId);
  }

  @override
  Future<void> deactivateVariation(String variationId) async {
    variations.removeWhere((v) => v.variationId == variationId);
  }

  @override
  Future<CustomVariation> createVariation(String userId, String name) async {
    final v = CustomVariation(
      variationId: 'v-${variations.length + 1}',
      userId: userId,
      name: name,
    );
    variations.add(v);
    return v;
  }

  @override
  Future<CustomVariation?> findVariationByName(
    String userId,
    String name,
  ) async => null;

  @override
  Future<void> reactivateVariation(String variationId) async {}
}

void main() {
  late _FakeExerciseRepo repo;

  setUp(() => repo = _FakeExerciseRepo());

  test('fetchAll is exactly three reads', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();

    expect(repo.exerciseReads, 1);
    expect(repo.variationReads, 1);
    expect(repo.usageReads, 1,
        reason: 'the catalog is passed into the usage read — it must not '
            're-read exercises and variations inside');
    expect(vm.state.value.exerciseDetailMap['ex1']?.exercise.name,
        'Bench Press',
        reason: 'the detail map derives from the list, not a third read');
    vm.dispose();
  });

  test('a second fetchAll is a no-op once loaded', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();
    await vm.fetchAll();

    expect(repo.exerciseReads, 1,
        reason: 'the load-once guard stops the hub\'s re-entry from '
            're-reading the catalog');
    vm.dispose();
  });

  test('a rename patches the list without re-reading', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();
    final readsBefore = repo.exerciseReads + repo.variationReads + repo.usageReads;

    await vm.renameExercise('ex1', 'Incline Bench');

    expect(repo.exerciseReads + repo.variationReads + repo.usageReads,
        readsBefore,
        reason: 'renaming must not rescan the catalog or the timeline');
    expect(vm.state.value.exercises.single.name, 'Incline Bench');
    expect(vm.state.value.exerciseDetailMap['ex1']?.exercise.name,
        'Incline Bench');
    vm.dispose();
  });

  test('a delete removes the row locally without re-reading', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();
    final readsBefore = repo.exerciseReads + repo.variationReads + repo.usageReads;

    await vm.deleteExercise('ex1');

    expect(repo.exerciseReads + repo.variationReads + repo.usageReads,
        readsBefore);
    expect(vm.state.value.exercises, isEmpty);
    expect(vm.state.value.exerciseDetailMap, isEmpty);
    vm.dispose();
  });

  test('a create inserts the new row locally without re-reading', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();
    final readsBefore = repo.exerciseReads + repo.variationReads + repo.usageReads;

    vm.setCreateExName('Squat');
    final id = await vm.submitCreateExercise();

    expect(id, isNotNull);
    expect(repo.exerciseReads + repo.variationReads + repo.usageReads,
        readsBefore);
    expect(
      vm.state.value.exercises.map((e) => e.name),
      contains('Squat'),
    );
    vm.dispose();
  });

  test('refreshExercisesOnly reads the list, not the catalog twice', () async {
    final vm = ExerciseViewModel(repo: repo, userId: 'u1');
    await vm.fetchAll();
    await vm.refreshExercisesOnly();

    expect(repo.exerciseReads, 2, reason: 'one list re-read for the pop');
    expect(repo.variationReads, 1, reason: 'variations untouched');
    expect(repo.usageReads, 1, reason: 'usage untouched');
    vm.dispose();
  });
}
