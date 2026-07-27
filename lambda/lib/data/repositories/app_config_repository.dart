import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_config.dart';

class AppConfigRepository {
  final _client = Supabase.instance.client;

  /// Reads directly from Supabase (not the PowerSync local cache) — this has
  /// to work before login, and before PowerSync has synced anything down.
  Future<AppConfig?> fetchForPlatform(String platform) async {
    final data = await _client
        .from('app_config')
        .select()
        .eq('platform', platform)
        .maybeSingle();
    if (data == null) return null;
    return AppConfig.fromMap(data);
  }
}
