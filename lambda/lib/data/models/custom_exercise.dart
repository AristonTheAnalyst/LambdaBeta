class CustomExercise {
  const CustomExercise({
    required this.exerciseId,
    required this.userId,
    required this.name,
    required this.volumeType,
    required this.isActive,
  });

  final String exerciseId;
  final String userId;
  final String name;
  final String volumeType; // 'reps' | 'duration'
  final bool isActive;

  factory CustomExercise.fromMap(Map<String, dynamic> map) => CustomExercise(
        exerciseId: map['custom_exercise_id'] as String,
        userId: map['user_id'] as String,
        name: map['exercise_name'] as String,
        volumeType: map['exercise_volume_type'] as String? ?? 'reps',
        isActive: _toBool(map['is_active']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'custom_exercise_id': exerciseId,
        'user_id': userId,
        'exercise_name': name,
        'exercise_volume_type': volumeType,
        'is_active': isActive,
      };
}
