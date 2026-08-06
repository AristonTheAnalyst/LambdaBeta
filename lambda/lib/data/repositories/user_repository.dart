import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/powersync/database.dart' as ps;
import '../models/user_profile.dart';

const _uuid = Uuid();

class UserRepository {
  final _client = Supabase.instance.client;

  Future<UserProfile?> fetchProfile(String userId) async {
    final rows = await ps.db.getAll(
      'SELECT * FROM dim_user WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  /// Persist the on-boarding profile to Supabase directly (bypasses the local
  /// PowerSync view because INSTEAD OF triggers may not be ready during
  /// on-boarding, especially on a fresh device after a disconnectAndClear).
  /// The Postgres on_auth_user_created trigger has already created the dim_user
  /// row on sign-up, so this is always an upsert (not a blind insert).
  Future<void> upsertProfile(UserProfile profile) async {
    await _client.from('dim_user').upsert({
      'user_id': profile.userId,
      'user_name': profile.userName,
      'user_lastname': profile.userLastname,
      'user_date_of_birth':
          profile.userDateOfBirth?.toIso8601String().split('T').first,
      'user_gender': profile.userGender,
      'user_height_cm': profile.userHeightCm,
      'user_weight_kg': profile.userWeightKg,
      'onboarded': profile.onboarded,
    }, onConflict: 'user_id');
  }

  /// Logs a bodyweight entry via PowerSync so it survives offline and syncs
  /// automatically.  The `user_weight_id` column is the table's text PK (a
  /// client-generated UUID, matching every other table's PK convention).
  Future<void> logWeight(String userId, double weightKg) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await ps.db.execute(
      '''
      INSERT INTO fact_bodyweight
        (id, user_weight_id, user_id, user_weight, user_weight_date, created_date)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [id, id, userId, weightKg, dateStr, now.toIso8601String()],
    );
  }

  Future<void> deleteAccount(String userId) async {
    await _client.functions.invoke('delete-account', body: {'user_id': userId});
  }
}
