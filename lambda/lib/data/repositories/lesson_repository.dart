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

  /// One batch read for a workout's exercise slots — the editor used to
  /// query per exercise on every open (2026-10-13).
  Future<Map<String, List<Lesson>>> fetchLessonsForExercises(
    String userId,
    List<String> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) return {};
    final placeholders = List.filled(exerciseIds.length, '?').join(',');
    final rows = await _db.getAll(
      '''
      SELECT * FROM dim_lesson
      WHERE user_id = ? AND custom_exercise_id IN ($placeholders) AND is_archived = 0
      ORDER BY pinned DESC, lesson_created_date DESC
      ''',
      [userId, ...exerciseIds],
    );
    final byExercise = <String, List<Lesson>>{};
    for (final r in rows) {
      final lesson = Lesson.fromMap(r);
      byExercise.putIfAbsent(lesson.exerciseId, () => []).add(lesson);
    }
    return byExercise;
  }

  Future<Lesson> createLesson(String userId, String exerciseId, String text,
      {String? sessionId}) async {
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await _db.execute(
      '''
      INSERT INTO dim_lesson
        (id, lesson_id, user_id, custom_exercise_id, lesson_text, pinned, is_archived, lesson_created_date, session_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, exerciseId, text, 0, 0, createdDate.toIso8601String(), sessionId],
    );
    _log.info('createLesson → id=$id exercise=$exerciseId countAfter=${(await fetchLessons(userId, exerciseId)).length}');
    return Lesson(
      lessonId: id,
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: createdDate,
      sessionId: sessionId,
    );
  }

  /// Updates a lesson's text.
  Future<void> updateLesson(
      String userId, String exerciseId, String lessonId, String text) async {
    await _db.execute(
      'UPDATE dim_lesson SET lesson_text = ? WHERE lesson_id = ?',
      [text, lessonId],
    );
    _log.info('updateLesson → id=$lessonId countAfter=${(await fetchLessons(userId, exerciseId)).length}');
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
