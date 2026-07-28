import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/user_profile.dart';

class UserRepository {
  final _client = Supabase.instance.client;

  Future<UserProfile?> fetchProfile(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_user WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return UserProfile.fromJson(rows.first);
  }

  /// The dim_user row already exists by the time this runs (created by the
  /// on_auth_user_created Postgres trigger on signup), but a real upsert
  /// guards against the rare case where that trigger-created row hasn't
  /// synced down to the local cache yet. id and user_id hold the same value
  /// for this table, so ON CONFLICT(id) is equivalent to ON CONFLICT(user_id).
  Future<void> upsertProfile(UserProfile profile) async {
    await ps.db.execute(
      '''
      INSERT INTO dim_user
        (id, user_id, user_name, user_lastname, user_date_of_birth, user_gender,
         user_height_cm, user_weight_kg, onboarded)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        user_name = excluded.user_name,
        user_lastname = excluded.user_lastname,
        user_date_of_birth = excluded.user_date_of_birth,
        user_gender = excluded.user_gender,
        user_height_cm = excluded.user_height_cm,
        user_weight_kg = excluded.user_weight_kg,
        onboarded = excluded.onboarded
      ''',
      [
        profile.userId,
        profile.userId,
        profile.userName,
        profile.userLastname,
        profile.userDateOfBirth?.toIso8601String().split('T').first,
        profile.userGender,
        profile.userHeightCm,
        profile.userWeightKg,
        profile.onboarded ? 1 : 0,
      ],
    );
  }

  Future<void> logWeight(String userId, double weightKg) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await _client.from('fact_bodyweight').insert({
      'user_id': userId,
      'user_weight': weightKg,
      'user_weight_date': dateStr,
    });
  }

  Future<void> deleteAccount(String userId) async {
    await _client.functions.invoke('delete-account', body: {'user_id': userId});
  }
}
