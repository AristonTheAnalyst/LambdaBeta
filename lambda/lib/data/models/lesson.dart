class Lesson {
  const Lesson({
    required this.lessonId,
    required this.userId,
    required this.exerciseId,
    required this.text,
    required this.pinned,
    required this.createdDate,
  });

  final String lessonId;
  final String userId;
  final String exerciseId;
  final String text;
  final bool pinned;
  final DateTime createdDate;

  factory Lesson.fromMap(Map<String, dynamic> map) => Lesson(
        lessonId: map['lesson_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String,
        text: map['lesson_text'] as String,
        pinned: _toBool(map['pinned']),
        createdDate: DateTime.parse(map['lesson_created_date'] as String),
      );

  Map<String, dynamic> toMap() => {
        'lesson_id': lessonId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'lesson_text': text,
        'pinned': pinned,
        'lesson_created_date': createdDate.toIso8601String(),
      };

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }
}
