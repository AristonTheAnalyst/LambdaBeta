import 'package:flutter/material.dart';
import 'core/theme/lambda_theme.dart';
import 'shared/router/app_router.dart';

class LambdaApp extends StatefulWidget {
  const LambdaApp({super.key});

  @override
  State<LambdaApp> createState() => _LambdaAppState();
}

class _LambdaAppState extends State<LambdaApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChange);
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
    );
  }
}
