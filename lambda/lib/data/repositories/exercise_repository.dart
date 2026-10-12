import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../../core/utils/name_limit.dart';
import '../models/custom_exercise.dart';
import '../models/custom_variation.dart';
import '../models/exercise_detail.dart';
import '../models/exercise_usage.dart';
import 'session_repository.dart';

// lastUsedByEntity is used by fetchExerciseDetailMap below.

const _uuid = Uuid();

class ExerciseRepository {
  final _sessionRepo = SessionRepository();

  /// Aggregate per-exercise and per-variation usage across the user's history
  /// (sets, workouts, last used, and the distinct other-entity count). Derived
  /// from the past-sets timeline so it stays consistent with what the library
  /// and analytics show. Every exercise/variation gets an entry (zeros if
  /// unused) so callers can sort the full list.
  Future<Map<String, ExerciseUsage>> fetchUsage(String userId) async {
    final timeline = await _sessionRepo.loadPastSetsTimeline(userId);
    final exSets = <String, int>{};
    final exWorkouts = <String, Set<String>>{};
    final exVariations = <String, Set<String>>{};
    final exLast = <String, DateTime>{};
    final varSets = <String, int>{};
    final varWorkouts = <String, Set<String>>{};
    final varExercises = <String, Set<String>>{};
    final varLast = <String, DateTime>{};

    for (final s in timeline) {
      final d = s.sessionCreatedDate;
      // Exercise (sets with no exercise are free rows — nothing to aggregate)
      final exerciseId = s.exerciseId;
      if (exerciseId != null) {
        exSets[exerciseId] = (exSets[exerciseId] ?? 0) + 1;
        exWorkouts.putIfAbsent(exerciseId, () => {}).add(s.sessionId);
        if (s.variationId != null) {
          exVariations.putIfAbsent(exerciseId, () => {}).add(s.variationId!);
        }
        if (d.isAfter(
            exLast[exerciseId] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          exLast[exerciseId] = d;
        }
      }
      // Variation
      if (s.variationId != null) {
        final vid = s.variationId!;
        varSets[vid] = (varSets[vid] ?? 0) + 1;
        varWorkouts.putIfAbsent(vid, () => {}).add(s.sessionId);
        if (exerciseId != null) {
          varExercises.putIfAbsent(vid, () => {}).add(exerciseId);
        }
        if (d.isAfter(varLast[vid] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          varLast[vid] = d;
        }
      }
    }

    final usage = <String, ExerciseUsage>{};
    for (final e in await fetchExercises(userId)) {
      usage[e.exerciseId] = ExerciseUsage(
        sets: exSets[e.exerciseId] ?? 0,
        workouts: exWorkouts[e.exerciseId]?.length ?? 0,
        variationCount: exVariations[e.exerciseId]?.length ?? 0,
        lastUsed: exLast[e.exerciseId],
      );
    }
    for (final v in await fetchVariations(userId)) {
      usage[v.variationId] = ExerciseUsage(
        sets: varSets[v.variationId] ?? 0,
        workouts: varWorkouts[v.variationId]?.length ?? 0,
        exerciseCount: varExercises[v.variationId]?.length ?? 0,
        lastUsed: varLast[v.variationId],
      );
    }
    return usage;
  }

  Future<List<CustomExercise>> fetchArchivedExercises(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND date_archived IS NOT NULL ORDER BY date_archived DESC',
      [userId],
    );
    return rows.map((r) => CustomExercise.fromMap(r)).toList();
  }

  Future<List<CustomExercise>> fetchExercises(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND date_archived IS NULL ORDER BY exercise_name',
      [userId],
    );
    return rows.map((r) => CustomExercise.fromMap(r)).toList();
  }

  Future<List<CustomVariation>> fetchArchivedVariations(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND date_archived IS NOT NULL ORDER BY date_archived DESC',
      [userId],
    );
    return rows.map((r) => CustomVariation.fromMap(r)).toList();
  }

  Future<List<CustomVariation>> fetchVariations(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND date_archived IS NULL ORDER BY variation_name',
      [userId],
    );
    return rows.map((r) => CustomVariation.fromMap(r)).toList();
  }

  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
      String userId) async {
    final exercises = await fetchExercises(userId);

    // Exercises and variations are independent since schema v2 (no bridge) —
    // variation assignment is gone, so each detail is just its exercise.
    return {
      for (final ex in exercises)
        ex.exerciseId: ExerciseDetail(
          exercise: ex,
        ),
    };
  }

  /// `custom_exercise_id → exercise_name` for EVERY exercise, archived ones
  /// included.
  ///
  /// [fetchExercises] filters `date_archived IS NULL`, which is right for the
  /// library and wrong for anything historical: a version cut while an exercise
  /// was active must still name it after that exercise has been archived, and
  /// blanking the label defeats the point of a screen whose whole job is
  /// showing what the program used to contain.
  Future<Map<String, String>> fetchExerciseNameMap(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT custom_exercise_id, exercise_name FROM dim_exercise WHERE user_id = ?',
      [userId],
    );
    return {
      for (final r in rows)
        if (r['custom_exercise_id'] != null)
          r['custom_exercise_id'] as String:
              (r['exercise_name'] as String?) ?? '',
    };
  }

  /// `custom_variation_id → variation_name` for EVERY variation, archived ones
  /// included. Same reasoning as [fetchExerciseNameMap] — a target that named a
  /// variation must keep naming it after the variation is retired.
  Future<Map<String, String>> fetchVariationNameMap(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT custom_variation_id, variation_name FROM dim_variation WHERE user_id = ?',
      [userId],
    );
    return {
      for (final r in rows)
        if (r['custom_variation_id'] != null)
          r['custom_variation_id'] as String:
              (r['variation_name'] as String?) ?? '',
    };
  }

  Future<CustomExercise?> findExerciseByName(
      String userId, String name) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND LOWER(exercise_name) = LOWER(?)',
      [userId, name],
    );
    if (rows.isEmpty) return null;
    return CustomExercise.fromMap(rows.first);
  }

  Future<CustomVariation?> findVariationByName(
      String userId, String name) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND LOWER(variation_name) = LOWER(?)',
      [userId, name],
    );
    if (rows.isEmpty) return null;
    return CustomVariation.fromMap(rows.first);
  }

  /// Refuses an over-long name rather than shortening it.
  ///
  /// The PowerSync mirror is a plain `Column.text` with no CHECK support, so a
  /// 25-character name would write locally, render in the picker, survive a
  /// restart — and then fail to upload (`23514`, quarantined in
  /// `upload_failures`) with nothing shown to the user. Clamping is worse than
  /// failing: it would store a different name than the user typed.
  void _assertNameFits(String name) {
    if (nameTooLong(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'exceeds $kMaxExerciseNameLength characters',
      );
    }
  }

  Future<CustomExercise> createExercise(String userId, String name) async {
    _assertNameFits(name);
    final id = _uuid.v4();
    await ps.db.execute(
      'INSERT INTO dim_exercise (id, custom_exercise_id, user_id, exercise_name) VALUES (?, ?, ?, ?)',
      [id, id, userId, name],
    );
    return CustomExercise(exerciseId: id, userId: userId, name: name);
  }

  Future<void> reactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET date_archived = NULL WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<CustomVariation> createVariation(String userId, String name) async {
    _assertNameFits(name);
    final id = _uuid.v4();
    await ps.db.execute(
      'INSERT INTO dim_variation (id, custom_variation_id, user_id, variation_name) VALUES (?, ?, ?, ?)',
      [id, id, userId, name],
    );
    return CustomVariation(variationId: id, userId: userId, name: name);
  }

  Future<void> reactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET date_archived = NULL WHERE custom_variation_id = ?',
      [variationId],
    );
  }

  Future<void> deactivateExercise(String exerciseId) async {
    await ps.db.execute(
      'UPDATE dim_exercise SET date_archived = ? WHERE custom_exercise_id = ?',
      [DateTime.now().toUtc().toIso8601String(), exerciseId],
    );
  }

  /// How many rows across all tables bind this exercise — > 0 means it has
  /// been "used" and can only be archived (the FKs are the server backstop).
  Future<int> exerciseUsageCount(String exerciseId) async {
    final queries = [
      'SELECT COUNT(*) c FROM fact_session_exercise WHERE custom_exercise_id = ?',
      'SELECT COUNT(*) c FROM dim_planned_session_exercise WHERE custom_exercise_id = ?',
      'SELECT COUNT(*) c FROM dim_lesson WHERE custom_exercise_id = ?',
      'SELECT COUNT(*) c FROM fact_goal WHERE custom_exercise_id = ?',
    ];
    var total = 0;
    for (final q in queries) {
      final rows = await ps.db.getAll(q, [exerciseId]);
      total += _rowCount(rows);
    }
    return total;
  }

  /// Hard-deletes a never-used exercise. Callers MUST check
  /// [exerciseUsageCount] first.
  Future<void> hardDeleteExercise(String exerciseId) async {
    // View settings FK the exercise — clear them before the row goes.
    await ps.db.execute(
      'DELETE FROM dim_pr_view_setting WHERE exercise_id = ?',
      [exerciseId],
    );
    await ps.db.execute(
      'DELETE FROM dim_exercise WHERE custom_exercise_id = ?',
      [exerciseId],
    );
  }

  Future<void> deactivateVariation(String variationId) async {
    await ps.db.execute(
      'UPDATE dim_variation SET date_archived = ? WHERE custom_variation_id = ?',
      [DateTime.now().toUtc().toIso8601String(), variationId],
    );
  }

  /// How many rows across all tables bind this variation — > 0 means it has
  /// been "used" and can only be archived (the FKs are the server backstop).
  Future<int> variationUsageCount(String variationId) async {
    final queries = [
      'SELECT COUNT(*) c FROM fact_session_exercise_set WHERE custom_variation_id = ?',
      'SELECT COUNT(*) c FROM dim_planned_session_exercise_set WHERE custom_variation_id = ?',
    ];
    var total = 0;
    for (final q in queries) {
      final rows = await ps.db.getAll(q, [variationId]);
      total += _rowCount(rows);
    }
    return total;
  }

  /// Hard-deletes a never-used variation. Callers MUST check
  /// [variationUsageCount] first.
  Future<void> hardDeleteVariation(String variationId) async {
    await ps.db.execute(
      'DELETE FROM dim_variation WHERE custom_variation_id = ?',
      [variationId],
    );
  }

  static int _rowCount(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0;
    final v = rows.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  Future<void> updateExercise(String exerciseId, String name) async {
    _assertNameFits(name);
    await ps.db.execute(
      'UPDATE dim_exercise SET exercise_name = ? WHERE custom_exercise_id = ?',
      [name, exerciseId],
    );
  }

  Future<void> updateVariation(String variationId, String name) async {
    _assertNameFits(name);
    await ps.db.execute(
      'UPDATE dim_variation SET variation_name = ? WHERE custom_variation_id = ?',
      [name, variationId],
    );
  }
}
