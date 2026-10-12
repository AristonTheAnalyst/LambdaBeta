import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/router/app_router.dart';

/// Where the tab shell's bar appears.
///
/// The rule is deliberately "the whole tab branch", because the shell is
/// built once per branch and hands its bar down to everything pushed inside
/// it — a `go` straight to a nested location must land on the same screen as
/// a push would, not a barless one.
void main() {
  group('showBottomNavFor', () {
    test('every tab root carries the bar', () {
      for (final root in ['/session', '/exercises', '/profile', '/dev']) {
        expect(showBottomNavFor(root), isTrue, reason: root);
      }
    });

    test('nested locations carry the bar with their tab', () {
      for (final nested in [
        '/exercises/programs',
        '/exercises/programs/p1',
        '/exercises/programs/p1/history',
        '/exercises/guide',
        '/exercises/exercise/e1',
        '/profile/detail',
        '/dev/gallery',
      ]) {
        expect(showBottomNavFor(nested), isTrue, reason: nested);
      }
    });

    test('screens outside the shell have no bar', () {
      for (final outside in [
        '/logs',
        '/logs/s1',
        '/login',
        '/signup',
        '/onboarding',
        '/reset-password',
        '/',
      ]) {
        expect(showBottomNavFor(outside), isFalse, reason: outside);
      }
    });

    test('a tab name that is only a prefix of a path is not a branch', () {
      // `/exerciseshelf` starts with `/exercises` but is not inside the
      // Library branch — only the full segment counts.
      expect(showBottomNavFor('/exerciseshelf'), isFalse);
      expect(showBottomNavFor('/profiles'), isFalse);
    });
  });
}
