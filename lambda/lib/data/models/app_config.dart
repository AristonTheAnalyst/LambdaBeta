class AppConfig {
  const AppConfig({
    required this.platform,
    required this.minVersion,
    required this.latestVersion,
  });

  final String platform;
  final String minVersion;
  final String latestVersion;

  factory AppConfig.fromMap(Map<String, dynamic> map) => AppConfig(
        platform: map['platform'] as String,
        minVersion: map['min_version'] as String,
        latestVersion: map['latest_version'] as String,
      );
}
