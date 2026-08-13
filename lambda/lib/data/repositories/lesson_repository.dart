import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/lesson.dart';

const _uuid = Uuid();
final _log = Logger('lessons');

/// Per-exercise pinnable cue notes ("lessons") — durable, cross-session
/// knowledge about an exercise, not tied to any single workout.
class LessonRepository {
  LessonRepository({PowerSyncDatabase? db}) : _db = db ?? ps.db;

  final PowerSyncDatabase _db;

  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async {
    final rows = await _db.getAll(
      '''
      SELECT * FROM dim_lesson
      WHERE user_id = ? AND custom_exercise_id = ? AND is_archived = 0
      ORDER BY pinned DESC, lesson_created_date DESC
      ''',
      [userId, exerciseId],
    );
    return rows.map((r) => Lesson.fromMap(r)).toList();
  }

  Future<Lesson> createLesson(String userId, String exerciseId, String text) async {
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await _db.execute(
      '''
      INSERT INTO dim_lesson
        (id, lesson_id, user_id, custom_exercise_id, lesson_text, pinned, is_archived, lesson_created_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, exerciseId, text, 0, 0, createdDate.toIso8601String()],
    );
    _log.info('createLesson → id=$id exercise=$exerciseId countAfter=${(await fetchLessons(userId, exerciseId)).length}');
    return Lesson(
      lessonId: id,
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: createdDate,
    );
  }

  /// Sets a lesson's pinned state. Pinning is exclusive per exercise — at most
  /// one lesson can be pinned at a time, so pinning one clears the others.
  Future<void> setPinned(
      String userId, String exerciseId, String lessonId, bool pinned) async {
    if (pinned) {
      await _db.execute(
        '''
        UPDATE dim_lesson SET pinned = 0
        WHERE user_id = ? AND custom_exercise_id = ? AND is_archived = 0
        ''',
        [userId, exerciseId],
      );
    }
    await _db.execute(
      'UPDATE dim_lesson SET pinned = ? WHERE lesson_id = ?',
      [pinned ? 1 : 0, lessonId],
    );
    _log.info('setPinned → id=$lessonId pinned=$pinned countAfter=${(await fetchLessons(userId, exerciseId)).length}');
  }

  Future<void> deleteLesson(String lessonId) async {
    await _db.execute(
      'UPDATE dim_lesson SET is_archived = 1 WHERE lesson_id = ?',
      [lessonId],
    );
    _log.info('deleteLesson → id=$lessonId');
  }
}
