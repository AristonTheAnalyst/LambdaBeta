import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// This install's device id (2026-10-15) — a uuid minted once and kept in
/// local preferences, stamped on every session this device creates
/// (`fact_session.device_id`). It is what lets the app tell its OWN live
/// session apart from one started on another device: the own one is resumed
/// silently, the other is only ever offered with a prompt.
///
/// Cached in memory after the first read, because session creation and the
/// foreign-session watch both ask repeatedly. A read that fails (a test
/// host without the plugin, a wiped store) answers null — which the app
/// treats as "not mine", the reading that only ever prompts and never
/// adopts.
class DeviceId {
  DeviceId._();

  static const _key = 'lambda_device_id';
  static const _uuid = Uuid();

  static String? _cached;
  static bool _loaded = false;

  /// The test seam — a fixed id, no preferences I/O (mirrors the VMs'
  /// `userId` overrides).
  static void override(String? id) {
    _cached = id;
    _loaded = true;
  }

  static Future<String?> get() async {
    if (_loaded) return _cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_key);
      if (id == null || id.isEmpty) {
        id = _uuid.v4();
        await prefs.setString(_key, id);
      }
      return _cached = id;
    } catch (_) {
      return _cached = null;
    } finally {
      _loaded = true;
    }
  }
}
