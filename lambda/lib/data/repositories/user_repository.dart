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

  Future<void> upsertProfile(UserProfile profile) async {
    await _client
        .from('dim_user')
        .upsert(profile.toJson(), onConflict: 'user_id');
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
