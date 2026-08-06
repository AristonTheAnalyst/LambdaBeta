import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/powersync/database.dart' as ps;
import '../../data/repositories/user_repository.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    _session = Supabase.instance.client.auth.currentSession;
    // Fetch onboarding status for any session that's already active on startup
    if (_session != null) _fetchOnboardingStatus();

    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        _session = data.session;

        if (data.event == AuthChangeEvent.passwordRecovery) {
          _isPasswordRecovery = true;
        } else if (data.event == AuthChangeEvent.userUpdated &&
            _isPasswordRecovery) {
          _isPasswordRecovery = false;
        } else if (data.event == AuthChangeEvent.signedOut) {
          _isPasswordRecovery = false;
          _isOnboarded = null;
        }

        // Fetch onboarding status whenever a new sign-in occurs
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.tokenRefreshed) {
          _fetchOnboardingStatus();
        }

        notifyListeners();
      },
    );
  }

  Session? _session;
  bool _isPasswordRecovery = false;
  bool? _isOnboarded; // null = not yet fetched, false = needs onboarding, true = done
  late final StreamSubscription<AuthState> _subscription;
  final _userRepo = UserRepository();

  bool get isAuthenticated => _session != null;
  bool get isPasswordRecovery => _isPasswordRecovery;
  bool? get isOnboarded => _isOnboarded;

  Future<void> _fetchOnboardingStatus() async {
    if (_session == null) {
      _isOnboarded = null;
      return;
    }
    try {
      var profile = await _userRepo.fetchProfile(_session!.user.id);
      // On a fresh install/device, the local PowerSync cache may not have
      // synced this user's row down yet, even for an existing, already-
      // onboarded account. Wait for the initial sync before concluding
      // there's no profile.
      if (profile == null) {
        await ps.db.waitForFirstSync().timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
        profile = await _userRepo.fetchProfile(_session!.user.id);
      }
      // If the profile is STILL null after waiting, treat onboarding status
      // as unknown rather than assuming the user needs onboarding. A null
      // isOnboarded keeps the router from redirecting — the user stays on
      // their current screen until the sync lands. The null case typically
      // means PowerSync hasn't finished initialising (e.g. after
      // disconnectAndClear).
      if (profile == null) {
        if (_isOnboarded != null) return; // unchanged
        _isOnboarded = null;
      } else {
        final onboarded = profile.onboarded;
        if (onboarded == _isOnboarded) return;
        _isOnboarded = onboarded;
      }
    } catch (_) {
      if (_isOnboarded != null) return; // unchanged
      _isOnboarded = null;
    }
    notifyListeners();
  }

  /// Called by OnboardingScreen after the user completes onboarding.
  /// Updates the in-memory flag immediately so the router redirect fires
  /// without waiting for another profile fetch.
  void completeOnboarding() {
    _isOnboarded = true;
    notifyListeners();
  }

  void clearPasswordRecovery() {
    _isPasswordRecovery = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
