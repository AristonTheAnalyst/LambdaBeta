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
      for (final root in [
        '/session',
        '/exercises',
        '/friends',
        '/profile',
        '/dev',
      ]) {
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
        '/friends/u1',
        '/profile/detail',
        '/dev/gallery',
        '/dev/pr-history',
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
      expect(showBottomNavFor('/friendship'), isFalse);
    });

    test('the friend surfaces light the Friends tab', () {
      // The friend list sits in the shell; the friend's record is a
      // top-level route outside it, but it draws its own bar and lights the
      // tab that opened it (`navRoute: '/friends'`, 2026-10-23).
      final friends = tabIndexFor('/friends');
      expect(tabIndexFor('/friends/u1'), friends);
      expect(tabIndexFor('/friends/u1/sessions/s1'), friends);
      expect(friends, isNot(tabIndexFor('/session')));
      expect(friends, isNot(tabIndexFor('/exercises')));
    });
  });

  /// The pages that pin their floor under the keyboard: the PR Lab's stage
  /// (2026-10-21) and the session surfaces (2026-10-25). Every other page
  /// lifts its floor for the keyboard.
  group('shellResizesForKeyboard', () {
    test('the session surfaces pin their floor under the keyboard', () {
      for (final location in ['/session', '/session/anything']) {
        expect(shellResizesForKeyboard(location), isFalse, reason: location);
      }
    });

    test('every other production page lifts its floor for the keyboard', () {
      for (final location in [
        '/exercises',
        '/exercises/programs/p1/history',
        '/logs',
        '/profile',
        '/dev',
        '/dev/pr-history',
      ]) {
        expect(shellResizesForKeyboard(location), isTrue, reason: location);
      }
    });

    test('the PR Lab lets the keyboard paint over its floor', () {
      expect(shellResizesForKeyboard('/dev/pr-lab'), isFalse);
    });

    test('a path that merely starts with a pinned route still lifts', () {
      // Only the full segment counts — the same rule the bar's branches use.
      expect(shellResizesForKeyboard('/dev/pr-labs'), isTrue);
      expect(shellResizesForKeyboard('/sessions'), isTrue);
    });
  });
}
