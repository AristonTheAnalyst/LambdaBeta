import 'dart:async';

import 'package:flutter/material.dart';
import 'app.dart';
import 'core/theme/lambda_theme.dart';
import 'core/version_check/version_check_service.dart';
import 'core/version_check/version_check_store.dart';
import 'features/update/view/update_required_screen.dart';

/// Root widget — the app-store version check, cached-first (2026-10-13).
///
/// The old flow awaited the network check before building anything, so
/// every cold start paid up to 2×5s on a spinner. Now the last persisted
/// result decides the first frame: a cached `updateRequired` shows the
/// update screen immediately while the live check re-verifies in the
/// background (and a live result that clears it swaps to the app — a
/// post-update false-block self-heals in one round); anything else renders
/// the app optimistically, and a live `updateRequired` swaps to the update
/// screen once it lands. The live check itself is capped at 3s, failing
/// open.
class VersionGateApp extends StatefulWidget {
  const VersionGateApp({
    super.key,
    this.checkService,
    this.store,
    this.appBuilder,
  });

  /// Test seams — the defaults are the live check, the persisted store, and
  /// the real [LambdaApp] shell (2026-10-13).
  final VersionCheckService? checkService;
  final VersionCheckStore? store;
  final Widget Function(bool showUpdateNudge)? appBuilder;

  @override
  State<VersionGateApp> createState() => _VersionGateAppState();
}

class _VersionGateAppState extends State<VersionGateApp> {
  VersionCheckStore get _store => widget.store ?? _defaultStore;

  /// The live check's answer; null while it runs (or before it starts).
  VersionCheckResult? _result;

  /// The persisted last answer, read before the first frame.
  VersionCheckResult? _cached;

  static final _defaultStore = VersionCheckStore();

  @override
  void initState() {
    super.initState();
    _restoreCached();
    _runCheck();
  }

  Future<void> _restoreCached() async {
    try {
      final cached = await _store.read();
      if (mounted) setState(() => _cached = cached);
    } catch (_) {}
  }

  Future<void> _runCheck() async {
    try {
      final result = await (widget.checkService ?? VersionCheckService())
          .check()
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () =>
                const VersionCheckResult(status: VersionCheckStatus.unknown),
          );
      await _store.write(result);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _result = const VersionCheckResult(
            status: VersionCheckStatus.unknown,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final cached = _cached;

    final status = result?.status ?? cached?.status;
    final blocked =
        result != null
            ? result.status == VersionCheckStatus.updateRequired
            : cached?.status == VersionCheckStatus.updateRequired;

    if (blocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeNotifier.colors.toThemeData(),
        home: const UpdateRequiredScreen(),
      );
    }

    // upToDate, updateRecommended, unknown (failed-open), and no result at
    // all proceed to the app — the nudge reads the best answer we have.
    final buildApp = widget.appBuilder ??
        (showUpdateNudge) => LambdaApp(showUpdateNudge: showUpdateNudge);
    return buildApp(status == VersionCheckStatus.updateRecommended);
  }
}
