import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/friendly_error.dart';
import '../../../data/models/athlete.dart';
import '../../../data/repositories/coach_repository.dart';

/// Everything the Coach screen draws (2026-10-26): the athletes a coach has
/// been accepted by.
class CoachState {
  const CoachState({
    this.athletes = const [],
    this.isLoading = true,
    this.error,
  });

  /// Accepted athletes, ordered by the repository's watch.
  final List<Athlete> athletes;

  /// True until the first emission lands, so the list doesn't flash its empty
  /// state over a local read that is about to return rows.
  final bool isLoading;

  /// The last failure, already a sentence for the user.
  final String? error;

  CoachState copyWith({
    List<Athlete>? athletes,
    bool? isLoading,
    String? error,
  }) => CoachState(
    athletes: athletes ?? this.athletes,
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
  );
}

/// The Coach roster's ViewModel, the `ValueNotifier<State>` species: one live
/// watch over the local mirror, no commands.
///
/// Reads ride the coaching_data stream, so there is nothing to re-read after a
/// change — an acceptance (#22) lands as a new emission. A revoke drops the
/// row the same way.
class CoachViewModel {
  CoachViewModel({CoachRepository? repo, String? userId})
    : _repo = repo ?? CoachRepository(),
      _userIdOverride = userId;

  final CoachRepository _repo;
  final state = ValueNotifier(const CoachState());
  bool _disposed = false;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  StreamSubscription<List<Athlete>>? _sub;

  /// Subscribes the watch. Called from `initState`; idempotent, so a rebuild
  /// never doubles the subscription.
  void start() {
    if (_disposed || _sub != null) return;
    _sub = _repo
        .watchAthletes(_userId)
        .listen(
          (athletes) {
            if (_disposed) return;
            // A fresh state rather than copyWith: a later emission is a
            // recovery, so it also drops a failure the first read recorded.
            state.value = CoachState(athletes: athletes, isLoading: false);
          },
          onError: (Object e) {
            if (_disposed) return;
            state.value = state.value.copyWith(
              isLoading: false,
              error: friendlyError(e),
            );
          },
        );
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    state.dispose();
  }
}
