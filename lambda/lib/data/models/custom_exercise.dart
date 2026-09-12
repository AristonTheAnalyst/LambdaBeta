class CustomExercise {
  const CustomExercise({
    required this.exerciseId,
    required this.userId,
    required this.name,
    this.archivedDate,
  });

  final String exerciseId;
  final String userId;
  final String name;

  /// NULL = active; a timestamp = archived (sortable, latest first).
  final DateTime? archivedDate;

  bool get isArchived => archivedDate != null;

  factory CustomExercise.fromMap(Map<String, dynamic> map) => CustomExercise(
        exerciseId: map['custom_exercise_id'] as String,
        userId: map['user_id'] as String,
        name: map['exercise_name'] as String,
        archivedDate: map['date_archived'] != null
            ? DateTime.tryParse(map['date_archived'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'custom_exercise_id': exerciseId,
        'user_id': userId,
        'exercise_name': name,
        'date_archived': archivedDate?.toIso8601String(),
      };
}
