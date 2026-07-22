import 'custom_exercise.dart';
import 'custom_variation.dart';

class ExerciseDetail {
  const ExerciseDetail({
    required this.exercise,
    required this.assignedVariations,
  });

  final CustomExercise exercise;
  final List<CustomVariation> assignedVariations;

  String get exerciseId => exercise.exerciseId;
  String get name => exercise.name;
  String get volumeType => exercise.volumeType;
}
