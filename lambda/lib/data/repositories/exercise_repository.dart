import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/custom_exercise.dart';
import '../models/custom_variation.dart';
import '../models/exercise_detail.dart';

const _uuid = Uuid();

class ExerciseRepository {
  final _client = Supabase.instance.client;

  Future<List<CustomExercise>> fetchExercises(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_exercise WHERE user_id = ? AND is_active = 1 ORDER BY exercise_name',
      [userId],
    );
    return rows.map((r) => CustomExercise.fromMap(r)).toList();
  }

  Future<List<CustomVariation>> fetchVariations(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_variation WHERE user_id = ? AND is_active = 1 ORDER BY variation_name',
      [userId],
    );
    return rows.map((r) => CustomVariation.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBridges(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT custom_exercise_id, custom_variation_id FROM dim_exercise_variation_bridge WHERE user_id = ? AND (deleted_locally IS NULL OR deleted_locally = 0)',
      [userId],
    );
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
      String userId) async {
    final exercises = await fetchExercises(userId);
    final variations = await fetchVariations(userId);
    final bridges = await fetchBridges(userId);

    final varMap = {for (final v in variations) v.variationId: v};
    final assignedMap = <String, List<CustomVariation>>{};
    for (final b in bridges) {
      final exId = b['custom_exercise_id'] as String;
      final varId = b['custom_variation_id'] as String;
      final variation = varMap[varId];
      if (variation != null) {
        assignedMap.putIfAbsent(exId, () => []).add(variation);
      }
    }

    return {
      for (final ex in exercises)
        ex.exerciseId: ExerciseDetail(
          exercise: ex,
          assignedVariations: assignedMap[ex.exerciseId] ?? [],
        ),
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

  Future<CustomExercise> createExercise(String userId, String name) async {
    final data = await _client
        .from('dim_exercise')
        .insert({
          'custom_exercise_id': _uuid.v4(),
          'user_id': userId,
          'exercise_name': name,
          'is_active': true,
        })
        .select()
        .single();
    return CustomExercise.fromMap(data);
  }

  Future<void> reactivateExercise(String exerciseId) async {
    await _client
        .from('dim_exercise')
        .update({'is_active': true}).eq('custom_exercise_id', exerciseId);
  }

  Future<CustomVariation> createVariation(String userId, String name) async {
    final data = await _client
        .from('dim_variation')
        .insert({
          'custom_variation_id': _uuid.v4(),
          'user_id': userId,
          'variation_name': name,
          'is_active': true,
        })
        .select()
        .single();
    return CustomVariation.fromMap(data);
  }

  Future<void> reactivateVariation(String variationId) async {
    await _client
        .from('dim_variation')
        .update({'is_active': true}).eq('custom_variation_id', variationId);
  }

  Future<void> addBridge(
      String userId, String exerciseId, String variationId) async {
    await _client.from('dim_exercise_variation_bridge').upsert({
      'user_id': userId,
      'custom_exercise_id': exerciseId,
      'custom_variation_id': variationId,
    }, onConflict: 'custom_exercise_id,custom_variation_id');
  }

  Future<void> deactivateExercise(String exerciseId) async {
    await _client
        .from('dim_exercise')
        .update({'is_active': false}).eq('custom_exercise_id', exerciseId);
  }

  Future<void> deactivateVariation(String variationId) async {
    await _client
        .from('dim_variation')
        .update({'is_active': false}).eq('custom_variation_id', variationId);
  }

  Future<void> updateExercise(String exerciseId, String name) async {
    await _client.from('dim_exercise').update({
      'exercise_name': name,
    }).eq('custom_exercise_id', exerciseId);
  }

  Future<void> updateVariation(String variationId, String name) async {
    await _client
        .from('dim_variation')
        .update({'variation_name': name}).eq('custom_variation_id', variationId);
  }

  Future<void> removeBridge(String exerciseId, String variationId) async {
    await _client
        .from('dim_exercise_variation_bridge')
        .delete()
        .eq('custom_exercise_id', exerciseId)
        .eq('custom_variation_id', variationId);
  }
}
