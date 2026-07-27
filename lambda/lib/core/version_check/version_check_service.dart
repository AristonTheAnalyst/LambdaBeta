import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import '../../data/repositories/app_config_repository.dart';

enum VersionCheckStatus {
  upToDate,
  updateRecommended,
  updateRequired,
  // The check itself couldn't complete (network error, table unreachable,
  // unparsable version, etc). Callers should fail open — treat the same as
  // upToDate rather than blocking app usage.
  unknown,
}

class VersionCheckResult {
  const VersionCheckResult({
    required this.status,
    this.installedVersion,
    this.latestVersion,
  });

  final VersionCheckStatus status;
  final String? installedVersion;
  final String? latestVersion;
}

class VersionCheckService {
  VersionCheckService({AppConfigRepository? repo})
      : _repo = repo ?? AppConfigRepository();

  final AppConfigRepository _repo;

  static const _timeout = Duration(seconds: 5);

  String? get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return null; // No app-store update gate on desktop/web builds.
  }

  Future<VersionCheckResult> check() async {
    final platform = _platform;
    if (platform == null) {
      return const VersionCheckResult(status: VersionCheckStatus.upToDate);
    }
    try {
      final packageInfo = await PackageInfo.fromPlatform().timeout(_timeout);
      final installed = Version.parse(packageInfo.version);

      final config =
          await _repo.fetchForPlatform(platform).timeout(_timeout);
      if (config == null) {
        return VersionCheckResult(
          status: VersionCheckStatus.unknown,
          installedVersion: installed.toString(),
        );
      }

      final minVersion = Version.parse(config.minVersion);
      final latestVersion = Version.parse(config.latestVersion);

      final status = installed < minVersion
          ? VersionCheckStatus.updateRequired
          : installed < latestVersion
              ? VersionCheckStatus.updateRecommended
              : VersionCheckStatus.upToDate;

      return VersionCheckResult(
        status: status,
        installedVersion: installed.toString(),
        latestVersion: latestVersion.toString(),
      );
    } catch (_) {
      return const VersionCheckResult(status: VersionCheckStatus.unknown);
    }
  }
}
