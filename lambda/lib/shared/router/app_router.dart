import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/lambda_theme.dart';
import '../../features/auth/view/forgot_password_screen.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/auth/view/reset_password_screen.dart';
import '../../features/auth/view/signup_screen.dart';
import '../../features/coach/view/coach_screen.dart';
import '../../features/dev/lab/lab_screen.dart';
import '../../features/dev/view/dev_screen.dart';
import '../../features/dev/view/experimental_screen.dart';
import '../../features/dev/view/gallery_screen.dart';
import '../../features/dev/view/lesson_debug_screen.dart';
import '../../features/dev/view/nav_bar_demo_screen.dart';
import '../../features/dev/pr_lab/pr_lab_screen.dart';
import '../../features/dev/view/pr_history_demo_screen.dart';
import '../../features/dev/view/visual_pairings_screen.dart';
import '../../features/exercises/view/exercise_hub_screen.dart';
import '../../features/exercises/view/exercise_detail_screen.dart';
import '../../features/exercises/view/guide_screen.dart';
import '../../features/friends/view/friends_screen.dart';
import '../../features/logs/view/logs_screen.dart';
import '../../features/logs/view/session_detail_screen.dart';
import '../../features/onboarding/view/onboarding_screen.dart';
import '../../features/profile/view/appearance_screen.dart';
import '../../features/profile/view/profile_detail_screen.dart';
import '../../features/profile/view/profile_hub_screen.dart';
import '../../features/session/view/session_screen.dart';
import '../widgets/scroll_shrink_nav_bar.dart';
import 'auth_notifier.dart';

abstract final class AppRouter {
  static final _authNotifier = AuthNotifier();

  /// The `extra` a `/logs/:id` push carries when the live Training page sent
  /// it (2026-10-22). The date bar's newest record steps forward onto "today"
  /// by popping the viewer, landing on the live page still mounted underneath
  /// instead of tearing the shell down and rebuilding it.
  static const fromLiveExtra = 'session-from-live';

  /// Bumped when the **Session tab is re-tapped while the wizard is already
  /// the page on screen** (2026-10-23). A `go` to the location already
  /// showing is a no-op, so without this the tap would die silently; the
  /// wizard listens and slides itself to its Home page — the Training Logs
  /// browse — with the live session still running, and its header then
  /// offers Resume. A counter, not a flag: every tap is a fresh signal.
  static final sessionTabReselected = ValueNotifier<int>(0);

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
      final isAuth = _authNotifier.isAuthenticated;
      final isRecovery = _authNotifier.isPasswordRecovery;
      final isOnboarded = _authNotifier.isOnboarded;
      final loc = state.matchedLocation;

      final isAuthRoute =
          loc == '/login' || loc == '/signup' || loc == '/forgot-password';
      final isResetPassword = loc == '/reset-password';
      final isOnboardingRoute = loc == '/onboarding';

      // Password recovery takes highest priority
      if (isRecovery && !isResetPassword) return '/reset-password';

      // Unauthenticated users must go to login
      if (!isAuth && !isAuthRoute && !isResetPassword) return '/login';

      // Authenticated users leave auth screens
      if (isAuth && isAuthRoute) return '/session';

      // Redirect unboarded users to onboarding (isOnboarded == null means
      // still fetching — hold position; false means explicitly not done)
      if (isAuth &&
          !isRecovery &&
          isOnboarded == false &&
          !isOnboardingRoute &&
          !isResetPassword) {
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
      GoRoute(path: '/login', builder: (_, _) => LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => ResetPasswordScreen(),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => OnboardingScreen()),

      // ── Logs (pushed from the Session tab — no nav tab) ──────────────────
      GoRoute(
        path: '/logs',
        builder: (_, _) => LogsScreen(),
        routes: [
          GoRoute(
            path: ':id',
            // `?exercise=<id>` selects the exercise on open — the goal
            // sheet's completion row (2026-10-20). `?tab=` is accepted but
            // no longer moves anywhere: the viewer draws the sets, the PRs,
            // the lessons and the bookends at once (2026-10-22).
            builder: (_, state) => SessionDetailScreen(
              sessionId: state.pathParameters['id']!,
              initialTab: state.uri.queryParameters['tab'],
              initialExerciseId: state.uri.queryParameters['exercise'],
              fromLive: state.extra == AppRouter.fromLiveExtra,
            ),
          ),
        ],
      ),

      // ── A friend's record (2026-10-23) ───────────────────────────────────
      // Top-level, beside /logs, for the same reason: the viewer draws its
      // own bar rather than sitting under the shell's. The bar lights the
      // Friends tab (`navRoute`), and the page is read-only throughout —
      // no edit, no Restore, no lessons composer.
      GoRoute(
        path: '/friends/:userId/sessions/:sessionId',
        builder: (_, state) => SessionDetailScreen(
          sessionId: state.pathParameters['sessionId']!,
          userId: state.pathParameters['userId'],
          readOnly: true,
          navRoute: '/friends',
        ),
      ),

      // ── An athlete's record (2026-10-26) ─────────────────────────────────
      // The coach's viewer, the same read-only page as the friend's. Top
      // level for the same reason, but its bar lights Profile — the tab the
      // roster hangs off; the list itself is /profile/coach/:athleteId.
      GoRoute(
        path: '/coach/:athleteId/sessions/:sessionId',
        builder: (_, state) => SessionDetailScreen(
          sessionId: state.pathParameters['sessionId']!,
          userId: state.pathParameters['athleteId'],
          readOnly: true,
          // The coach may not touch the athlete's sets, but they are the one
          // reader who writes on this page: their feedback (2026-10-26, #24).
          canCoach: true,
          navRoute: '/profile',
        ),
      ),

      // ── Dev-only full-screen demos ───────────────────────────────────────
      // Outside the tab shell on purpose: these pages draw their own bottom
      // bar, and the shell's bar would sit underneath it.
      // `kDebugMode`, not `!kReleaseMode`: a profile build is for measuring
      // the shipping app, so it must not carry the dev surfaces either
      // (2026-10-22). Both flags are const, so the routes are compiled out of
      // the binary in profile and release alike.
      if (kDebugMode)
        GoRoute(
          path: '/nav-bar-demo',
          builder: (_, _) => const NavBarDemoScreen(),
        ),

      // The review flow lab. Top-level for a stronger reason than the demos:
      // it swaps the app onto a sandbox database for as long as it is open, so
      // the shell — and every tab under it — must not be reachable while it
      // runs. It has no routes of its own: the review flow pushes what it
      // needs on the root navigator, exactly as it does outside the lab.
      if (kDebugMode)
        GoRoute(path: '/dev/lab', builder: (_, _) => const LabScreen()),

      // ── Tab shell ─────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            _TabShell(currentRoute: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/session', builder: (_, _) => SessionScreen()),
          GoRoute(
            path: '/exercises',
            builder: (_, _) => ExerciseHubScreen(),
            routes: [
              GoRoute(path: 'guide', builder: (_, _) => GuideScreen()),
              GoRoute(
                path: 'exercise/:id',
                builder: (_, state) => ExerciseDetailScreen(
                  exerciseId: state.pathParameters['id']!,
                  exerciseName: state.extra as String?,
                ),
              ),
              // Programs are out of the UI for now (2026-10-26): no route
              // leads to a program, its blocks, its runs or its history. The
              // tables, repositories and screens stay in place, unreachable,
              // so the data can come back later without a migration.
            ],
          ),
          GoRoute(
            path: '/friends',
            builder: (_, _) => const FriendsScreen(),
            routes: [
              // A friend's completed sessions — the Training Logs list
              // pointed at their history, read-only (2026-10-23). The name
              // rides `extra` so the header reads "Jamie" without a query;
              // a deep link falls back to the word.
              GoRoute(
                path: ':userId',
                builder: (context, state) => LogsScreen(
                  userId: state.pathParameters['userId'],
                  readOnly: true,
                  headerTitle: state.extra as String? ?? 'Sessions',
                  onBack: () =>
                      context.canPop() ? context.pop() : context.go('/friends'),
                  emptyMessage: 'No sessions yet',
                  emptyHint: 'This friend has no completed sessions.',
                  sessionRouteBuilder: (id) =>
                      '/friends/${state.pathParameters['userId']}/sessions/$id',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => ProfileHubScreen(),
            routes: [
              GoRoute(path: 'detail', builder: (_, _) => ProfileDetailScreen()),
              // Profile → Appearance: the theme picker sits with the other
              // user preferences, not in the dev demos (2026-10-22).
              GoRoute(
                path: 'appearance',
                builder: (_, _) => const AppearanceScreen(),
              ),
              // Profile → Coach: the coach's roster, then an athlete's
              // completed history in the same read-only list and viewer the
              // Friends tab uses (2026-10-26). Nested under /profile so the
              // pushed pages keep the Profile tab lit and the bar visible.
              GoRoute(
                path: 'coach',
                builder: (_, _) => const CoachScreen(),
                routes: [
                  GoRoute(
                    path: ':athleteId',
                    builder: (context, state) => LogsScreen(
                      userId: state.pathParameters['athleteId'],
                      readOnly: true,
                      headerTitle: state.extra as String? ?? 'Athlete',
                      onBack: () => context.canPop()
                          ? context.pop()
                          : context.go('/profile/coach'),
                      emptyMessage: 'No sessions yet',
                      emptyHint: 'This athlete has no completed sessions.',
                      sessionRouteBuilder: (id) =>
                          '/coach/${state.pathParameters['athleteId']}/sessions/$id',
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Dev routes exist in debug builds only — a profile build measures
          // the shipping app, so it drops them along with the release build.
          if (kDebugMode)
            GoRoute(
              path: '/dev',
              builder: (_, _) => DevScreen(),
              routes: [
                GoRoute(path: 'gallery', builder: (_, _) => GalleryScreen()),
                GoRoute(
                  path: 'experimental',
                  builder: (_, _) => ExperimentalScreen(),
                ),
                GoRoute(
                  path: 'lesson-debug',
                  builder: (_, _) => const LessonDebugScreen(),
                ),
                GoRoute(
                  path: 'pr-history',
                  builder: (_, _) => const PrHistoryDemoScreen(),
                ),
                GoRoute(path: 'pr-lab', builder: (_, _) => const PrLabScreen()),
                GoRoute(
                  path: 'visual-pairings',
                  builder: (_, _) => const VisualPairingsScreen(),
                ),
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

/// Whether a location's page lets the keyboard push the shell's floor up.
///
/// True everywhere but the pages that pin their floor and let the keyboard
/// paint over it: the PR Lab's stage, which keeps the date changer, the action
/// bar and the nav bar exactly where they are (2026-10-21), and the session
/// surfaces — the live wizard's floor bar carries the date selector and the
/// PR/notes doors, and a keyboard that lifted it would move the page under
/// the user's hands mid-set (2026-10-25). Each page opts out on its own
/// Scaffold; this is the shell opting out with it — a body that still resized
/// would carry the nav bar up anyway, and the floor with it.
@visibleForTesting
bool shellResizesForKeyboard(String location) {
  const pinned = ['/dev/pr-lab', '/session'];
  return !pinned.any((r) => location == r || location.startsWith('$r/'));
}

/// The location actually on screen, pushed pages included.
///
/// The shell learns the location its branch was built at; a page pushed
/// inside the branch (`context.push`) is a Navigator push, not a new shell
/// state, so the shell's own [GoRouterState] can be one page behind. The
/// router's match list still carries the pushed page, as an
/// [ImperativeRouteMatch] beside the branch's match — that is where the top
/// is read from (2026-10-21).
String _topLocation(String location) {
  final matches = AppRouter.router.routerDelegate.currentConfiguration.matches;
  if (matches.isEmpty) return location;
  final branch = matches.first;
  if (branch is ShellRouteMatch && branch.matches.isNotEmpty) {
    final leaf = branch.matches.last;
    if (leaf is ImperativeRouteMatch) return leaf.matchedLocation;
  }
  return location;
}

const _kTabRoots = ['/session', '/exercises', '/friends', '/profile', '/dev'];

/// One destination on the shell's bar, in tab order.
class _Tab {
  const _Tab(this.route, this.item);

  final String route;
  final ScrollShrinkNavItem item;
}

/// The shell's tabs. Dev is debug-only, the same rule the old bar used — its
/// screen can drop server-side tables.
final _tabs = <_Tab>[
  const _Tab(
    '/session',
    ScrollShrinkNavItem(
      icon: Icons.play_circle_outline,
      activeIcon: Icons.play_circle,
      label: 'Session',
    ),
  ),
  const _Tab(
    '/exercises',
    ScrollShrinkNavItem(
      icon: Icons.local_library_outlined,
      activeIcon: Icons.local_library,
      label: 'Library',
    ),
  ),
  const _Tab(
    '/friends',
    ScrollShrinkNavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Friends',
    ),
  ),
  const _Tab(
    '/profile',
    ScrollShrinkNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ),
  if (kDebugMode)
    const _Tab(
      '/dev',
      ScrollShrinkNavItem(
        icon: Icons.code,
        activeIcon: Icons.code,
        label: 'Dev',
      ),
    ),
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
      // The PR Lab asks for the keyboard to cover its floor instead of
      // lifting it — the page's own Scaffold opts out, and the shell has to
      // agree or the bar rides the inset up with it. The rule reads the top
      // page, because the lab is opened with a push.
      resizeToAvoidBottomInset: shellResizesForKeyboard(
        _topLocation(currentRoute),
      ),
      // A storey floating above the bar (2026-10-27): the another-device
      // notice, which the Session wizard publishes through
      // [sessionAboveBarNotice] because this shell cannot see its VM. The
      // slot is why the notice is one: whatever stands there also counts in
      // [ScrollShrinkNavBar.contentInset], so every page clears it with the
      // bar.
      body: ValueListenableBuilder<Widget?>(
        valueListenable: sessionAboveBarNotice,
        builder: (context, aboveBar, _) => ScrollShrinkNavBar(
          currentIndex: _tabIndexFor(currentRoute),
          onTap: (i) {
            final tab = _tabs[i];
            // A tap on the tab whose page is already on screen is the PAGE's
            // own business, not a navigation — `go` there would change
            // nothing. The Session wizard answers it by showing the browse
            // without ending the live session (2026-10-23).
            if (tab.route == '/session' &&
                _topLocation(currentRoute) == '/session') {
              AppRouter.sessionTabReselected.value++;
            }
            GoRouter.of(context).go(tab.route);
          },
          items: [for (final tab in _tabs) tab.item],
          aboveBar: aboveBar,
          child: child,
        ),
      ),
    );
  }
}

/// Which tab a location belongs to. The whole branch counts, so a page pushed
/// inside a tab keeps that tab lit — the same rule [showBottomNavFor] uses.
///
/// Production callers: the pushed editors that draw their own bar, and the
/// session viewer, whose bar lights whichever tab opened it (`navRoute`) —
/// Session for the user's own record, Friends when reading a friend's.
int tabIndexFor(String location) => _tabIndexFor(location);

/// The shell's bar, handed out for the screens that cover it.
///
/// The pushed full-screen editors (a program, a block, a workout) are routes
/// on the root navigator, so the shell's bar is hidden behind them and they
/// draw their own copy. They read it from here rather than repeating the list,
/// so a tab added or reordered once lands everywhere.
List<ScrollShrinkNavItem> get appTabItems => [
  for (final tab in _tabs) tab.item,
];

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
