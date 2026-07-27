import 'package:flutter/material.dart';
import 'core/theme/lambda_theme.dart';
import 'features/update/view/update_nudge_banner.dart';
import 'shared/router/app_router.dart';

class LambdaApp extends StatefulWidget {
  const LambdaApp({super.key, this.showUpdateNudge = false});

  final bool showUpdateNudge;

  @override
  State<LambdaApp> createState() => _LambdaAppState();
}

class _LambdaAppState extends State<LambdaApp> {
  bool _showNudge = false;

  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChange);
    _showNudge = widget.showUpdateNudge;
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onThemeChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lambda',
      debugShowCheckedModeBanner: false,
      theme: themeNotifier.colors.toThemeData(),
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return Stack(
          children: [
            ?child,
            if (_showNudge)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: UpdateNudgeBanner(
                  onDismiss: () => setState(() => _showNudge = false),
                ),
              ),
          ],
        );
      },
    );
  }
}
