import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/lesson.dart';

const _uuid = Uuid();

/// Per-exercise pinnable cue notes ("lessons") — durable, cross-session
/// knowledge about an exercise, not tied to any single workout.
class LessonRepository {
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async {
    final rows = await ps.db.getAll(
      '''
      SELECT * FROM fact_lesson
      WHERE user_id = ? AND custom_exercise_id = ? AND is_active = 1
      ORDER BY pinned DESC, lesson_created_date DESC
      ''',
      [userId, exerciseId],
    );
    return rows.map((r) => Lesson.fromMap(r)).toList();
  }

  Future<Lesson> createLesson(String userId, String exerciseId, String text) async {
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await ps.db.execute(
      '''
      INSERT INTO fact_lesson
        (id, lesson_id, user_id, custom_exercise_id, lesson_text, pinned, is_active, lesson_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, exerciseId, text, 0, 1, createdDate.toIso8601String()],
    );
    return Lesson(
      lessonId: id,
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: createdDate,
    );
  }

  Future<void> toggleLessonPin(String lessonId, bool pinned) async {
    await ps.db.execute(
      'UPDATE fact_lesson SET pinned = ? WHERE lesson_id = ?',
      [pinned ? 1 : 0, lessonId],
    );
  }

  Future<void> deleteLesson(String lessonId) async {
    await ps.db.execute(
      'UPDATE fact_lesson SET is_active = 0 WHERE lesson_id = ?',
      [lessonId],
    );
  }
}
