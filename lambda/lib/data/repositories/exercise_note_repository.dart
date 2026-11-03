import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/exercise_note.dart';

const _uuid = Uuid();
final _log = Logger('notes');

/// Per-exercise pinnable cue notes — durable, cross-session knowledge about
/// an exercise, not tied to any single workout. The UI's word is **exercise
/// notes**; the row is `dim_exercise_note`.
class ExerciseNoteRepository {
  ExerciseNoteRepository({PowerSyncDatabase? db}) : _db = db ?? ps.db;

  final PowerSyncDatabase _db;

  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async {
    final rows = await _db.getAll(
      '''
      SELECT * FROM dim_exercise_note
      WHERE user_id = ? AND custom_exercise_id = ? AND is_archived = 0
      ORDER BY pinned DESC, note_created_date DESC
      ''',
      [userId, exerciseId],
    );
    return rows.map((r) => ExerciseNote.fromMap(r)).toList();
  }

  /// One batch read for a workout's exercise slots — the editor used to
  /// query per exercise on every open (2026-10-13).
  Future<Map<String, List<ExerciseNote>>> fetchNotesForExercises(
    String userId,
    List<String> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) return {};
    final placeholders = List.filled(exerciseIds.length, '?').join(',');
    final rows = await _db.getAll(
      '''
      SELECT * FROM dim_exercise_note
      WHERE user_id = ? AND custom_exercise_id IN ($placeholders) AND is_archived = 0
      ORDER BY pinned DESC, note_created_date DESC
      ''',
      [userId, ...exerciseIds],
    );
    final byExercise = <String, List<ExerciseNote>>{};
    for (final r in rows) {
      final note = ExerciseNote.fromMap(r);
      byExercise.putIfAbsent(note.exerciseId, () => []).add(note);
    }
    return byExercise;
  }

  Future<ExerciseNote> createNote(
    String userId,
    String exerciseId,
    String text, {
    String? sessionId,
  }) async {
    final id = _uuid.v4();
    final createdDate = DateTime.now().toUtc();
    await _db.execute(
      '''
      INSERT INTO dim_exercise_note
        (id, exercise_note_id, user_id, custom_exercise_id, note_text, pinned, is_archived, note_created_date, session_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        id,
        userId,
        exerciseId,
        text,
        0,
        0,
        createdDate.toIso8601String(),
        sessionId,
      ],
    );
    _log.info(
      'createNote → id=$id exercise=$exerciseId countAfter=${(await fetchNotes(userId, exerciseId)).length}',
    );
    return ExerciseNote(
      exerciseNoteId: id,
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: createdDate,
      sessionId: sessionId,
    );
  }

  /// Updates a note's text.
  Future<void> updateNote(
    String userId,
    String exerciseId,
    String exerciseNoteId,
    String text,
  ) async {
    await _db.execute(
      'UPDATE dim_exercise_note SET note_text = ? WHERE exercise_note_id = ?',
      [text, exerciseNoteId],
    );
    _log.info(
      'updateNote → id=$exerciseNoteId countAfter=${(await fetchNotes(userId, exerciseId)).length}',
    );
  }

  /// Sets a note's pinned state. Pinning is exclusive per exercise — at most
  /// one note can be pinned at a time, so pinning one clears the others.
  Future<void> setPinned(
    String userId,
    String exerciseId,
    String exerciseNoteId,
    bool pinned,
  ) async {
    if (pinned) {
      await _db.execute(
        '''
        UPDATE dim_exercise_note SET pinned = 0
        WHERE user_id = ? AND custom_exercise_id = ? AND is_archived = 0
        ''',
        [userId, exerciseId],
      );
    }
    await _db.execute('UPDATE dim_exercise_note SET pinned = ? WHERE exercise_note_id = ?', [
      pinned ? 1 : 0,
      exerciseNoteId,
    ]);
    _log.info(
      'setPinned → id=$exerciseNoteId pinned=$pinned countAfter=${(await fetchNotes(userId, exerciseId)).length}',
    );
  }

  Future<void> deleteNote(String exerciseNoteId) async {
    await _db.execute(
      'UPDATE dim_exercise_note SET is_archived = 1 WHERE exercise_note_id = ?',
      [exerciseNoteId],
    );
    _log.info('deleteNote → id=$exerciseNoteId');
  }
}
