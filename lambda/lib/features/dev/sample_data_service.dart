import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/cache/past_sets_timeline_cache.dart';
import '../../../data/repositories/exercise_repository.dart';

const _uuid = Uuid();

/// Dev-only sample data for the currently logged-in user.
///
/// Inserts 12 weeks of history (3 sessions/week on Mon/Wed/Fri, backdated so
/// Insights time-range charts show real trends):
///   * 2 exercises per session — `test1` (no variation) and `test2`
///     (variation `variation1` only)
///   * 3 sets per exercise, 5 reps, weight starting at 40kg and +2.5kg per
///     session — every session beats the previous rep-max curve, so each
///     session produces fresh PRs on both (exercise × variation) curves
///   * cycling 1–5 pre/post feelings and occasional notes so the logs
///     screens look populated
///
/// PRs are derived from the sets on read — nothing extra is inserted.
class SampleDataService {
  SampleDataService({ExerciseRepository? exerciseRepo})
      : _exerciseRepo = exerciseRepo ?? ExerciseRepository();

  final ExerciseRepository _exerciseRepo;

  static const exercise1Name = 'test1';
  static const exercise2Name = 'test2';
  static const variationName = 'variation1';

  Future<int> insertSampleData(String userId) async {
    // ── Ensure exercises + variation exist (reuse if already created) ──────
    final ex1 = await _ensureExercise(userId, exercise1Name);
    final ex2 = await _ensureExercise(userId, exercise2Name);
    final var1 = await _ensureVariation(userId, variationName);

    // ── Build the last 36 Mon/Wed/Fri dates, oldest first ──────────────────
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final dates = <DateTime>[];
    var d = day;
    while (dates.length < 36) {
      if (d.weekday == DateTime.monday ||
          d.weekday == DateTime.wednesday ||
          d.weekday == DateTime.friday) {
        dates.add(d);
      }
      d = d.subtract(const Duration(days: 1));
    }
    dates.sort();

    // ── Insert sessions + exercises + sets in one transaction ──────────────
    await ps.db.writeTransaction((tx) async {
      for (var i = 0; i < dates.length; i++) {
        final sessionId = _uuid.v4();
        final date = dates[i];
        final weight = 40 + i * 2.5;
        final preFeeling = (i % 5) + 1;
        final postFeeling = ((i + 2) % 5) + 1;
        final hasNotes = i % 6 == 0;
        final created = date.add(const Duration(hours: 18)).toUtc();

        await tx.execute(
          '''
          INSERT INTO fact_session
            (id, session_id, user_id, pre_notes, post_notes, created_datetime,
             end_datetime, pre_feeling, post_feeling)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            sessionId, sessionId, userId,
            hasNotes ? 'Sample pre-note for session ${i + 1}' : null,
            hasNotes ? 'Sample post-note for session ${i + 1}' : null,
            created.toIso8601String(),
            created.add(const Duration(hours: 1)).toIso8601String(),
            preFeeling, postFeeling,
          ],
        );

        final exerciseRow1 = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO fact_session_exercise
            (id, session_exercise_id, session_id, user_id, custom_exercise_id,
             exercise_order)
          VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [exerciseRow1, exerciseRow1, sessionId, userId, ex1, 1],
        );
        final exerciseRow2 = _uuid.v4();
        await tx.execute(
          '''
          INSERT INTO fact_session_exercise
            (id, session_exercise_id, session_id, user_id, custom_exercise_id,
             exercise_order)
          VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [exerciseRow2, exerciseRow2, sessionId, userId, ex2, 2],
        );

        // test1 — non-variated
        for (var setNo = 1; setNo <= 3; setNo++) {
          await _insertSet(tx, exerciseRow1, userId, null, setNo, weight);
        }
        // test2 — variated only
        for (var setNo = 1; setNo <= 3; setNo++) {
          await _insertSet(tx, exerciseRow2, userId, var1, setNo, weight);
        }
      }
    });
    // The seeder writes fact rows directly — same funnel rule as the
    // repository (2026-10-13).
    PastSetsTimelineCache.instance.invalidate();

    return dates.length;
  }

  Future<void> _insertSet(
    dynamic tx,
    String sessionExerciseId,
    String userId,
    String? variationId,
    int setNumber,
    double weight,
  ) async {
    final setId = _uuid.v4();
    await tx.execute(
      '''
      INSERT INTO fact_session_exercise_set
        (id, session_exercise_set_id, session_exercise_id, user_id,
         custom_variation_id, set_number, weight, reps, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        setId, setId, sessionExerciseId, userId, variationId,
        setNumber, weight, jsonEncode([5]), null,
      ],
    );
  }

  /// Hard-deletes everything tied to the sample exercises — sessions whose
  /// exercise rows reference test1/test2, and those rows' sets. Safe because
  /// these exercise names are exclusively used by the sample data.
  Future<int> deleteSampleData(String userId) async {
    final ex1 =
        await _exerciseRepo.findExerciseByName(userId, exercise1Name);
    final ex2 =
        await _exerciseRepo.findExerciseByName(userId, exercise2Name);
    final ids = [ex1?.exerciseId, ex2?.exerciseId].whereType<String>().toList();
    if (ids.isEmpty) return 0;

    var deletedSessions = 0;
    await ps.db.writeTransaction((tx) async {
      final placeholders = List.filled(ids.length, '?').join(',');
      final sessionRows = await tx.getAll(
        'SELECT DISTINCT session_id FROM fact_session_exercise WHERE user_id = ? AND custom_exercise_id IN ($placeholders)',
        [userId, ...ids],
      );
      final sessionIds =
          sessionRows.map((r) => r['session_id'] as String).toList();

      await tx.execute(
        '''
        DELETE FROM fact_session_exercise_set WHERE user_id = ?
          AND session_exercise_id IN (
            SELECT session_exercise_id FROM fact_session_exercise
            WHERE custom_exercise_id IN ($placeholders)
          )
        ''',
        [userId, ...ids],
      );
      await tx.execute(
        'DELETE FROM fact_session_exercise WHERE user_id = ? AND custom_exercise_id IN ($placeholders)',
        [userId, ...ids],
      );
      if (sessionIds.isNotEmpty) {
        final sPlaceholders = List.filled(sessionIds.length, '?').join(',');
        await tx.execute(
          'DELETE FROM fact_session WHERE user_id = ? AND session_id IN ($sPlaceholders)',
          [userId, ...sessionIds],
        );
        deletedSessions = sessionIds.length;
      }
    });
    PastSetsTimelineCache.instance.invalidate();
    return deletedSessions;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _ensureExercise(String userId, String name) async {
    final existing = await _exerciseRepo.findExerciseByName(userId, name);
    if (existing != null) {
      if (!existing.isArchived) return existing.exerciseId;
      await _exerciseRepo.reactivateExercise(existing.exerciseId);
      return existing.exerciseId;
    }
    final created = await _exerciseRepo.createExercise(userId, name);
    return created.exerciseId;
  }

  Future<String> _ensureVariation(String userId, String name) async {
    final existing = await _exerciseRepo.findVariationByName(userId, name);
    if (existing != null) {
      if (!existing.isArchived) return existing.variationId;
      await _exerciseRepo.reactivateVariation(existing.variationId);
      return existing.variationId;
    }
    final created = await _exerciseRepo.createVariation(userId, name);
    return created.variationId;
  }
}
