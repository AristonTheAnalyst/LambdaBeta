import 'custom_exercise.dart';

/// Exercises and variations are independent since schema v2 (no bridge) —
/// this is a thin wrapper kept so the exercise-picker call sites keep their
/// map shape; variations are a flat per-user library fetched separately.
class ExerciseDetail {
  const ExerciseDetail({
    required this.exercise,
  });

  final CustomExercise exercise;

  String get exerciseId => exercise.exerciseId;
  String get name => exercise.name;
}
