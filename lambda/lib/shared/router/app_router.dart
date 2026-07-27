import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/lambda_theme.dart';
import '../../features/auth/view/forgot_password_screen.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/auth/view/reset_password_screen.dart';
import '../../features/auth/view/signup_screen.dart';
import '../../features/dev/view/dev_screen.dart';
import '../../features/dev/view/experimental_screen.dart';
import '../../features/dev/view/gallery_screen.dart';
import '../../features/exercises/view/exercise_hub_screen.dart';
import '../../features/exercises/view/exercise_library_screen.dart';
import '../../features/exercises/view/guide_screen.dart';
import '../../features/logs/view/logs_screen.dart';
import '../../features/logs/view/workout_detail_screen.dart';
import '../../features/onboarding/view/onboarding_screen.dart';
import '../../features/programs/view/program_detail_screen.dart';
import '../../features/programs/view/program_library_screen.dart';
import '../../features/profile/view/profile_detail_screen.dart';
import '../../features/profile/view/profile_hub_screen.dart';
import '../../features/session/view/session_screen.dart';
import '../../features/statistics/view/statistics_screen.dart';
import '../widgets/bottom_nav_bar.dart';
import 'auth_notifier.dart';

abstract final class AppRouter {
  static final _authNotifier = AuthNotifier();

  /// Exposed so OnboardingScreen can call authNotifier.completeOnboarding().
  static AuthNotifier get authNotifier => _authNotifier;

  static final router = GoRouter(
    initialLocation: '/session',
    // Merge auth + theme so route builders re-run (and pick up new AppColors)
    // whenever either changes.
    refreshListenable: Listenable.merge([_authNotifier, themeNotifier]),
    redirect: (context, state) {
      final isAuth       = _authNotifier.isAuthenticated;
      final isRecovery   = _authNotifier.isPasswordRecovery;
      final isOnboarded  = _authNotifier.isOnboarded;
      final loc          = state.matchedLocation;

      final isAuthRoute = loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password';
      final isResetPassword  = loc == '/reset-password';
      final isOnboardingRoute = loc == '/onboarding';

      // Password recovery takes highest priority
      if (isRecovery && !isResetPassword) return '/reset-password';

      // Unauthenticated users must go to login
      if (!isAuth && !isAuthRoute && !isResetPassword) return '/login';

      // Authenticated users leave auth screens
      if (isAuth && isAuthRoute) return '/session';

      // Redirect unboarded users to onboarding (isOnboarded == null means
      // still fetching — hold position; false means explicitly not done)
      if (isAuth && !isRecovery && isOnboarded == false && !isOnboardingRoute && !isResetPassword) {
        return '/onboarding';
      }

      // Already-onboarded users cannot revisit the onboarding screen
      if (isAuth && isOnboarded == true && isOnboardingRoute) {
        return '/session';
      }

      return null;
    },
    routes: [
      // ── Auth ─────────────────────────────────────────────────────────────
      GoRoute(path: '/login',           builder: (_, _) => LoginScreen()),
      GoRoute(path: '/signup',          builder: (_, _) => SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => ForgotPasswordScreen()),
      GoRoute(path: '/reset-password',  builder: (_, _) => ResetPasswordScreen()),
      GoRoute(path: '/onboarding',      builder: (_, _) => OnboardingScreen()),

      // ── Tab shell ─────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => _TabShell(
          currentRoute: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/session',
            builder: (_, _) => SessionScreen(),
          ),
          GoRoute(
            path: '/logs',
            builder: (_, _) => LogsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => WorkoutDetailScreen(
                  workoutId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/exercises',
            builder: (_, _) => ExerciseHubScreen(),
            routes: [
              GoRoute(path: 'library',  builder: (_, _) => ExerciseLibraryScreen()),
              GoRoute(path: 'guide',    builder: (_, _) => GuideScreen()),
              GoRoute(
                path: 'programs',
                builder: (_, _) => ProgramLibraryScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => ProgramDetailScreen(
                      programId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => ProfileHubScreen(),
            routes: [
              GoRoute(path: 'detail', builder: (_, _) => ProfileDetailScreen()),
            ],
          ),
          GoRoute(path: '/statistics', builder: (_, _) => StatisticsScreen()),
          GoRoute(
            path: '/dev',
            builder: (_, _) => DevScreen(),
            routes: [
              GoRoute(path: 'gallery',      builder: (_, _) => GalleryScreen()),
              GoRoute(path: 'experimental', builder: (_, _) => ExperimentalScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}

class _TabShell extends StatelessWidget {
  const _TabShell({required this.currentRoute, required this.child});

  final String currentRoute;
  final Widget child;

  static const _tabRoots = [
    '/session', '/logs', '/exercises', '/profile', '/statistics', '/dev',
  ];

  bool get _showBottomNav => _tabRoots.contains(currentRoute);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
      bottomNavigationBar: _showBottomNav
          ? BottomNavBar(
              currentRoute: currentRoute,
              onTap: (route) => GoRouter.of(context).go(route),
            )
          : null,
    );
  }
}
