import 'package:shared_preferences/shared_preferences.dart';

import 'version_check_service.dart';

/// The version check's last result, persisted locally (2026-10-13).
///
/// The gate's cached-first policy leans on this: a cached `updateRequired`
/// blocks the app immediately while the live check re-verifies in the
/// background (a re-check that clears it swaps to the app — the rare
/// post-update false-block self-heals in one round), and anything else
/// renders the app optimistically from the cache while the live check
/// runs.
class VersionCheckStore {
  static const _statusKey = 'version_check_status';
  static const _installedKey = 'version_check_installed';
  static const _latestKey = 'version_check_latest';

  Future<VersionCheckResult?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final statusName = prefs.getString(_statusKey);
    if (statusName == null) return null;
    final status = VersionCheckStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => VersionCheckStatus.unknown,
    );
    return VersionCheckResult(
      status: status,
      installedVersion: prefs.getString(_installedKey),
      latestVersion: prefs.getString(_latestKey),
    );
  }

  Future<void> write(VersionCheckResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusKey, result.status.name);
    if (result.installedVersion != null) {
      await prefs.setString(_installedKey, result.installedVersion!);
    }
    if (result.latestVersion != null) {
      await prefs.setString(_latestKey, result.latestVersion!);
    }
  }
}
