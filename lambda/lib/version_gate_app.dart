import 'package:flutter/material.dart';
import 'app.dart';
import 'core/styles/app_colors.dart';
import 'core/theme/lambda_theme.dart';
import 'core/version_check/version_check_service.dart';
import 'features/update/view/update_required_screen.dart';

/// Root widget — runs the app-store version check before anything else.
/// Auth state, PowerSync, and the router (AppRouter.router / AuthNotifier)
/// aren't built until this resolves, since LambdaApp (which owns all of
/// that) is only constructed once the check clears.
class VersionGateApp extends StatefulWidget {
  const VersionGateApp({super.key});

  @override
  State<VersionGateApp> createState() => _VersionGateAppState();
}

class _VersionGateAppState extends State<VersionGateApp> {
  VersionCheckResult? _result;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    final result = await VersionCheckService().check();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    if (result == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeNotifier.colors.toThemeData(),
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
        ),
      );
    }

    if (result.status == VersionCheckStatus.updateRequired) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeNotifier.colors.toThemeData(),
        home: const UpdateRequiredScreen(),
      );
    }

    // upToDate, updateRecommended, and unknown (failed-open) all proceed.
    return LambdaApp(
      showUpdateNudge: result.status == VersionCheckStatus.updateRecommended,
    );
  }
}
