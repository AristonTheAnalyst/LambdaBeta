import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/lambda_theme.dart';
import '../../features/auth/view/forgot_password_screen.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/auth/view/reset_password_screen.dart';
import '../../features/auth/view/signup_screen.dart';
import '../../features/dev/lab/lab_screen.dart';
import '../../features/dev/view/dev_screen.dart';
import '../../features/dev/view/experimental_screen.dart';
import '../../features/dev/view/gallery_screen.dart';
import '../../features/dev/view/lesson_debug_screen.dart';
import '../../features/dev/view/nav_bar_demo_screen.dart';
import '../../features/exercises/view/exercise_hub_screen.dart';
import '../../features/exercises/view/exercise_detail_screen.dart';
import '../../features/exercises/view/guide_screen.dart';
import '../../features/logs/view/logs_screen.dart';
import '../../features/logs/view/session_detail_screen.dart';
import '../../features/onboarding/view/onboarding_screen.dart';
import '../../features/programs/view/program_detail_screen.dart';
import '../../features/programs/view/program_history_screen.dart';
import '../../features/programs/view/program_library_screen.dart';
import '../../features/profile/view/profile_detail_screen.dart';
import '../../features/profile/view/profile_hub_screen.dart';
import '../../features/session/view/session_screen.dart';
import '../widgets/scroll_shrink_nav_bar.dart';
import 'auth_notifier.dart';

abstract final class AppRouter {
  static final _authNotifier = AuthNotifier();

  /// Exposed so OnboardingScreen can call authNotifier.completeOnboarding().
  static AuthNotifier get authNotifier => _authNotifier;

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final routeObserver = RouteObserver<ModalRoute<dynamic>>();

  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [routeObserver],
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

      // ── Logs (pushed from the Session tab — no nav tab) ──────────────────
      GoRoute(
        path: '/logs',
        builder: (_, _) => LogsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => SessionDetailScreen(
              sessionId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      // ── Dev-only full-screen demos ───────────────────────────────────────
      // Outside the tab shell on purpose: these pages draw their own bottom
      // bar, and the shell's bar would sit underneath it.
      if (!kReleaseMode)
        GoRoute(
          path: '/nav-bar-demo',
          builder: (_, _) => const NavBarDemoScreen(),
        ),

      // The review flow lab. Top-level for a stronger reason than the demos:
      // it swaps the app onto a sandbox database for as long as it is open, so
      // the shell — and every tab under it — must not be reachable while it
      // runs. It has no routes of its own: the review flow pushes what it
      // needs on the root navigator, exactly as it does outside the lab.
      if (!kReleaseMode)
        GoRoute(
          path: '/dev/lab',
          builder: (_, _) => const LabScreen(),
        ),

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
            path: '/exercises',
            builder: (_, _) => ExerciseHubScreen(),
            routes: [
              GoRoute(path: 'guide',    builder: (_, _) => GuideScreen()),
              GoRoute(
                path: 'exercise/:id',
                builder: (_, state) => ExerciseDetailScreen(
                  exerciseId: state.pathParameters['id']!,
                  exerciseName: state.extra as String?,
                ),
              ),
              GoRoute(
                path: 'programs',
                builder: (_, _) => ProgramLibraryScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => ProgramDetailScreen(
                      programId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'history',
                        // `?block=<id>` opens already scoped to that block —
                        // how a block editor links to its own phase's history.
                        builder: (_, state) => ProgramHistoryScreen(
                          programId: state.pathParameters['id']!,
                          initialBlockId: state.uri.queryParameters['block'],
                        ),
                      ),
                    ],
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
          // Dev routes exist only in debug/profile builds — never ship them.
          if (!kReleaseMode)
            GoRoute(
              path: '/dev',
              builder: (_, _) => DevScreen(),
              routes: [
                GoRoute(path: 'gallery',      builder: (_, _) => GalleryScreen()),
                GoRoute(path: 'experimental', builder: (_, _) => ExperimentalScreen()),
                GoRoute(path: 'lesson-debug', builder: (_, _) => const LessonDebugScreen()),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Whether the tab shell's bar belongs on [location].
///
/// Every location inside a tab's branch gets the bar — not just its root.
/// The shell is built once per branch and is not rebuilt as pages are pushed
/// within it, so in practice a pushed page keeps its branch's bar; but a `go`
/// straight to a nested location builds the shell with that deeper location,
/// and the bar must not vanish just because the user arrived by a different
/// door.
@visibleForTesting
bool showBottomNavFor(String location) =>
    _kTabRoots.any((r) => location == r || location.startsWith('$r/'));

const _kTabRoots = ['/session', '/exercises', '/profile', '/dev'];

/// One destination on the shell's bar, in tab order.
class _Tab {
  const _Tab(this.route, this.item);

  final String route;
  final ScrollShrinkNavItem item;
}

/// The shell's tabs. Dev is debug-only, the same rule the old bar used — its
/// screen can drop server-side tables.
final _tabs = <_Tab>[
  const _Tab('/session', ScrollShrinkNavItem(
    icon: Icons.play_circle_outline,
    activeIcon: Icons.play_circle,
    label: 'Session',
  )),
  const _Tab('/exercises', ScrollShrinkNavItem(
    icon: Icons.local_library_outlined,
    activeIcon: Icons.local_library,
    label: 'Library',
  )),
  const _Tab('/profile', ScrollShrinkNavItem(
    icon: Icons.person_outline,
    activeIcon: Icons.person,
    label: 'Profile',
  )),
  if (!kReleaseMode)
    const _Tab('/dev', ScrollShrinkNavItem(
      icon: Icons.code,
      activeIcon: Icons.code,
      label: 'Dev',
    )),
];

class _TabShell extends StatelessWidget {
  const _TabShell({required this.currentRoute, required this.child});

  final String currentRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showBottomNavFor(currentRoute)) {
      return Scaffold(backgroundColor: Colors.transparent, body: child);
    }
    // The bar paints over the page rather than being laid out beside it, so
    // content scrolls under the blur. Pages clear it with
    // [ScrollShrinkNavBar.contentInset].
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ScrollShrinkNavBar(
        currentIndex: _tabIndexFor(currentRoute),
        onTap: (i) => GoRouter.of(context).go(_tabs[i].route),
        items: [for (final tab in _tabs) tab.item],
        child: child,
      ),
    );
  }
}

/// Which tab a location belongs to. The whole branch counts, so a page pushed
/// inside a tab keeps that tab lit — the same rule [showBottomNavFor] uses.
@visibleForTesting
int tabIndexFor(String location) => _tabIndexFor(location);

/// The shell's bar, handed out for the screens that cover it.
///
/// The pushed full-screen editors (a program, a block, a workout) are routes
/// on the root navigator, so the shell's bar is hidden behind them and they
/// draw their own copy. They read it from here rather than repeating the list,
/// so a tab added or reordered once lands everywhere.
List<ScrollShrinkNavItem> get appTabItems =>
    [for (final tab in _tabs) tab.item];

/// The route of the tab at [index] — what a bar tap on a pushed editor
/// navigates to.
String tabRouteAt(int index) => _tabs[index].route;

/// The tab the plan editors belong to — Library. They are reached from its
/// branch, and their own bar lights it while they cover the shell.
final int libraryTabIndex = _tabIndexFor('/exercises');

int _tabIndexFor(String location) {
  for (var i = 0; i < _tabs.length; i++) {
    final route = _tabs[i].route;
    if (location == route || location.startsWith('$route/')) return i;
  }
  return 0;
}
