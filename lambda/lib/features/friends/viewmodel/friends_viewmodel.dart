import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/friendly_error.dart';
import '../../../data/models/friend.dart';
import '../../../data/repositories/friend_repository.dart';

/// Everything the Friends tab draws (2026-10-23): the caller's own code, the
/// friends list, and the state of an in-flight add.
class FriendsState {
  const FriendsState({
    this.myCode,
    this.friends = const [],
    this.isLoading = true,
    this.isAdding = false,
    this.error,
  });

  /// The caller's shareable code; null until its row first syncs (a fresh
  /// account's code is minted server-side and arrives with the next round).
  final String? myCode;

  /// Named friends, ordered by name — the repository's watch decides.
  final List<Friend> friends;

  /// True until the first friends emission lands, so the list doesn't flash
  /// its empty state over a local read that is about to return rows.
  final bool isLoading;

  /// An add is in flight (the sheet's button spins).
  final bool isAdding;

  /// The last failure, already a sentence for the user.
  final String? error;

  FriendsState copyWith({
    String? myCode,
    List<Friend>? friends,
    bool? isLoading,
    bool? isAdding,
    String? error,
    bool clearError = false,
  }) => FriendsState(
    myCode: myCode ?? this.myCode,
    friends: friends ?? this.friends,
    isLoading: isLoading ?? this.isLoading,
    isAdding: isAdding ?? this.isAdding,
    error: clearError ? null : error ?? this.error,
  );
}

/// The Friends tab's ViewModel, the `ValueNotifier<State>` species: two live
/// watches (own code, friends list) plus two commands that reach the server.
///
/// Reads ride the local mirror — the friends_data stream keeps it fresh — so
/// this class never re-reads after a command; the watch emits the new list
/// the moment the repository's local mirror lands.
class FriendsViewModel {
  FriendsViewModel({FriendRepository? repo, String? userId})
    : _repo = repo ?? FriendRepository(),
      _userIdOverride = userId;

  final FriendRepository _repo;
  final state = ValueNotifier(const FriendsState());
  bool _disposed = false;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  StreamSubscription<List<Friend>>? _friendsSub;
  StreamSubscription<String?>? _codeSub;

  /// Subscribes both watches. Called from `initState`; idempotent, so a
  /// rebuild or a second call never doubles the subscriptions.
  void start() {
    if (_disposed || _friendsSub != null) return;
    final userId = _userId;
    _friendsSub = _repo
        .watchFriends(userId)
        .listen(
          (friends) {
            if (_disposed) return;
            state.value = state.value.copyWith(
              friends: friends,
              isLoading: false,
            );
          },
          onError: (Object e) {
            if (_disposed) return;
            state.value = state.value.copyWith(
              isLoading: false,
              error: friendlyError(e),
            );
          },
        );
    _codeSub = _repo
        .watchMyCode(userId)
        .listen(
          (code) {
            if (_disposed) return;
            state.value = state.value.copyWith(myCode: code);
          },
          onError: (Object e) {
            // A code that fails to read leaves the card's `—` in place; the
            // list itself is unaffected, so this stays out of [error].
            debugPrint('FriendsViewModel: code watch failed: $e');
          },
        );
  }

  /// Adds the owner of [code]. Returns the result so the screen can toast
  /// which name landed (and whether it was new); null means the attempt was
  /// refused and [state.error] carries the sentence to show.
  Future<AddFriendResult?> add(String code) async {
    if (_disposed || state.value.isAdding) return null;
    state.value = state.value.copyWith(isAdding: true, clearError: true);
    try {
      final result = await _repo.addByCode(_userId, code);
      if (_disposed) return result;
      state.value = state.value.copyWith(isAdding: false);
      return result;
    } catch (e) {
      if (_disposed) return null;
      state.value = state.value.copyWith(
        isAdding: false,
        error: friendlyError(e),
      );
      return null;
    }
  }

  /// Removes [friend]. True when the server-side cut succeeded and the local
  /// row is gone; false records [state.error].
  Future<bool> remove(Friend friend) async {
    if (_disposed) return false;
    try {
      await _repo.removeFriend(_userId, friend.userId);
      return true;
    } catch (e) {
      if (_disposed) return false;
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
  }

  /// Drops a stale error (the add sheet closing, a list retry).
  void clearError() {
    if (_disposed) return;
    state.value = state.value.copyWith(clearError: true);
  }

  void dispose() {
    _disposed = true;
    _friendsSub?.cancel();
    _codeSub?.cancel();
    state.dispose();
  }
}
