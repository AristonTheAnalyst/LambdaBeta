import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/friendly_error.dart';
import '../../../data/models/athlete.dart';
import '../../../data/models/coach_relationship.dart';
import '../../../data/repositories/coach_repository.dart';

/// Everything the Coach screen draws (2026-10-26, #22): the four slices of
/// the caller's coaching edges.
class CoachState {
  const CoachState({
    this.athletes = const [],
    this.coaches = const [],
    this.invitations = const [],
    this.pendingSent = const [],
    this.isLoading = true,
    this.isInviting = false,
    this.error,
  });

  /// Accepted athletes the caller coaches, by name.
  final List<Athlete> athletes;

  /// Accepted coaches of the caller, by name.
  final List<Athlete> coaches;

  /// Invitations waiting on the caller's consent, newest first.
  final List<Athlete> invitations;

  /// Invitations the caller has sent that are still pending, newest first.
  /// Nameless by design: the stream sends nothing about an unaccepted athlete.
  final List<Athlete> pendingSent;

  /// True until the first emission lands, so the list doesn't flash its empty
  /// state over a local read that is about to return rows.
  final bool isLoading;

  /// An invite is in flight (the sheet's button spins).
  final bool isInviting;

  /// The last failure, already a sentence for the user.
  final String? error;

  bool get isEmpty =>
      athletes.isEmpty &&
      coaches.isEmpty &&
      invitations.isEmpty &&
      pendingSent.isEmpty;

  CoachState copyWith({
    List<Athlete>? athletes,
    List<Athlete>? coaches,
    List<Athlete>? invitations,
    List<Athlete>? pendingSent,
    bool? isLoading,
    bool? isInviting,
    String? error,
    bool clearError = false,
  }) => CoachState(
    athletes: athletes ?? this.athletes,
    coaches: coaches ?? this.coaches,
    invitations: invitations ?? this.invitations,
    pendingSent: pendingSent ?? this.pendingSent,
    isLoading: isLoading ?? this.isLoading,
    isInviting: isInviting ?? this.isInviting,
    error: clearError ? null : error ?? this.error,
  );
}

/// The Coach screen's ViewModel, the `ValueNotifier<State>` species: one live
/// watch over the local mirror plus the three commands that reach the server.
///
/// Reads ride the local mirror — the coaching streams keep it fresh — so this
/// class never re-reads after a command; the watch emits the new lists the
/// moment the repository's local mirror lands.
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

  StreamSubscription<List<CoachRelationship>>? _sub;

  /// Subscribes the watch. Called from `initState`; idempotent, so a rebuild
  /// never doubles the subscription.
  void start() {
    if (_disposed || _sub != null) return;
    final userId = _userId;
    _sub = _repo
        .watchRelationships(userId)
        .listen(
          (rows) {
            if (_disposed) return;
            // A fresh state rather than copyWith: a later emission is a
            // recovery, so it also drops a failure the first read recorded.
            state.value = _split(rows, userId);
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

  /// Splits the caller's edges into the four lists. Accepted rows order by
  /// name (the list the screen is about); pending rows by when they were
  /// written, newest first (the action still to take).
  static CoachState _split(List<CoachRelationship> rows, String userId) {
    final athletes = <Athlete>[];
    final coaches = <Athlete>[];
    final invitations = <Athlete>[];
    final pendingSent = <Athlete>[];
    for (final row in rows) {
      if (row.coachUserId == userId) {
        if (row.isAccepted) {
          athletes.add(row.athlete);
        } else {
          pendingSent.add(row.athlete);
        }
      } else if (row.athleteUserId == userId) {
        if (row.isAccepted) {
          coaches.add(row.coach);
        } else {
          invitations.add(row.coach);
        }
      }
    }
    int byName(Athlete a, Athlete b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    int newestFirst(Athlete a, Athlete b) =>
        (b.createdDate ?? DateTime(0)).compareTo(a.createdDate ?? DateTime(0));
    athletes.sort(byName);
    coaches.sort(byName);
    invitations.sort(newestFirst);
    pendingSent.sort(newestFirst);
    return CoachState(
      athletes: athletes,
      coaches: coaches,
      invitations: invitations,
      pendingSent: pendingSent,
      isLoading: false,
    );
  }

  /// Invites the owner of [code]. Returns the RPC's report so the screen can
  /// name what landed; null means the attempt was refused and [state.error]
  /// carries the sentence to show.
  Future<CoachInvite?> invite(String code) async {
    if (_disposed || state.value.isInviting) return null;
    state.value = state.value.copyWith(isInviting: true, clearError: true);
    try {
      final invite = await _repo.inviteByCode(_userId, code);
      if (_disposed) return invite;
      state.value = state.value.copyWith(isInviting: false);
      return invite;
    } catch (e) {
      if (_disposed) return null;
      state.value = state.value.copyWith(
        isInviting: false,
        error: friendlyError(e),
      );
      return null;
    }
  }

  /// Gives [coach] the caller's consent. True when the server accepted it;
  /// false records [state.error].
  Future<bool> accept(Athlete coach) async {
    if (_disposed) return false;
    try {
      await _repo.acceptInvitation(_userId, coach.userId);
      return true;
    } catch (e) {
      if (_disposed) return false;
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
  }

  /// Ends the relationship with [other] — declining an invitation, withdrawing
  /// one sent, or revoking an accepted edge; which side the caller is on
  /// decides the wording, not the call. True when it landed; false records
  /// [state.error].
  Future<bool> remove(Athlete other) async {
    if (_disposed) return false;
    try {
      await _repo.remove(_userId, other.userId);
      return true;
    } catch (e) {
      if (_disposed) return false;
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
  }

  /// Drops a stale error (the invite sheet closing, a list retry).
  void clearError() {
    if (_disposed) return;
    state.value = state.value.copyWith(clearError: true);
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    state.dispose();
  }
}
