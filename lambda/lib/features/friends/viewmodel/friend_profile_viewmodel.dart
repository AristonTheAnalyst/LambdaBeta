import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/friendly_error.dart';
import '../../../data/models/coach_assignment.dart';
import '../../../data/models/coach_relationship.dart';
import '../../../data/models/friend.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/repositories/coach_repository.dart';
import '../../../data/repositories/friend_repository.dart';

/// Everything one friend's profile draws (2026-10-30): the friend row, the
/// coaching edge in either direction, and the workout offers the two of them
/// have exchanged.
///
/// The coaching edge is the list row's pill and the profile's verbs. Since
/// 2026-10-30 either side can ask — the athlete asks a friend to coach them,
/// or the coach offers — so a pending edge carries [CoachRelationship
/// .requestedByUserId] and only the OTHER side sees Accept.
class FriendProfileState {
  const FriendProfileState({
    this.friend,
    this.coachEdge,
    this.clientEdge,
    this.pendingEdge,
    this.assignments = const [],
    this.isLoading = true,
    this.isBusy = false,
    this.error,
  });

  /// The friend's row; null while the first emission is on its way, or when
  /// the friendship is gone (a removal this device did not make).
  final Friend? friend;

  /// The accepted edge where they are the coach; null otherwise.
  final CoachRelationship? coachEdge;

  /// The accepted edge where the caller is the coach; null otherwise.
  final CoachRelationship? clientEdge;

  /// An unaccepted edge in either direction; null when there is none.
  final CoachRelationship? pendingEdge;

  /// Offers the two of them have exchanged, newest first.
  final List<CoachAssignment> assignments;

  final bool isLoading;
  final bool isBusy;
  final String? error;

  bool get theyCoachMe => coachEdge != null;
  bool get iCoachThem => clientEdge != null;
  bool get hasCoaching => theyCoachMe || iCoachThem || pendingEdge != null;

  bool requestedByMe(String me) => pendingEdge?.requestedBy(me) ?? false;

  /// The workouts still waiting on the friend, as the athlete.
  List<CoachAssignment> get incomingAssignments => [
    for (final a in assignments)
      if (a.athleteUserId == friend?.userId && a.isPending) a,
  ];

  /// The offers the caller sent that are not declined.
  List<CoachAssignment> get sentAssignments => [
    for (final a in assignments)
      if (a.coachUserId != friend?.userId && !a.isDeclined) a,
  ];

  FriendProfileState copyWith({
    Friend? friend,
    CoachRelationship? coachEdge,
    CoachRelationship? clientEdge,
    CoachRelationship? pendingEdge,
    List<CoachAssignment>? assignments,
    bool? isLoading,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) => FriendProfileState(
    friend: friend ?? this.friend,
    coachEdge: coachEdge ?? this.coachEdge,
    clientEdge: clientEdge ?? this.clientEdge,
    pendingEdge: pendingEdge ?? this.pendingEdge,
    assignments: assignments ?? this.assignments,
    isLoading: isLoading ?? this.isLoading,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : error ?? this.error,
  );
}

/// One friend's profile, the `ValueNotifier<State>` species: three local
/// watches (the friend row, the coaching edges, the workout offers) and the
/// commands that reach the server through [FriendRepository] and
/// [CoachRepository].
class FriendProfileViewModel {
  FriendProfileViewModel({
    required this.me,
    required this.friendId,
    FriendRepository? friendRepo,
    CoachRepository? coachRepo,
  }) : _friendRepo = friendRepo ?? FriendRepository(),
       _coachRepo = coachRepo ?? CoachRepository();

  final String me;
  final String friendId;

  final FriendRepository _friendRepo;
  final CoachRepository _coachRepo;

  final state = ValueNotifier(const FriendProfileState());
  bool _disposed = false;

  StreamSubscription<List<Friend>>? _friendSub;
  StreamSubscription<List<CoachRelationship>>? _edgeSub;
  StreamSubscription<List<CoachAssignment>>? _assignmentSub;

  List<Friend> _friends = const [];
  List<CoachRelationship> _edges = const [];
  List<CoachAssignment> _assignments = const [];
  bool _friendsLoaded = false;

  /// Subscribes the three watches. Called from `initState`; idempotent.
  void start() {
    if (_disposed || _friendSub != null) return;
    _friendSub = _friendRepo
        .watchFriends(me)
        .listen(
          (friends) {
            if (_disposed) return;
            _friends = friends;
            _friendsLoaded = true;
            _emit();
          },
          onError: (Object e) {
            if (_disposed) return;
            state.value = state.value.copyWith(
              isLoading: false,
              error: friendlyError(e),
            );
          },
        );
    _edgeSub = _coachRepo
        .watchRelationships(me)
        .listen(
          (rows) {
            if (_disposed) return;
            _edges = rows;
            _emit();
          },
          onError: (Object e) {
            if (_disposed) return;
            state.value = state.value.copyWith(
              isLoading: false,
              error: friendlyError(e),
            );
          },
        );
    _assignmentSub = _coachRepo
        .watchAssignments(me)
        .listen(
          (rows) {
            if (_disposed) return;
            _assignments = [
              for (final a in rows)
                if (a.coachUserId == friendId || a.athleteUserId == friendId) a,
            ];
            _emit();
          },
          onError: (Object e) {
            // An offer read that fails leaves the section quiet; the rest of
            // the profile is unaffected.
            debugPrint('FriendProfileViewModel: assignment watch failed: $e');
          },
        );
  }

  /// Rebuilds from the three lists. A later emission also drops a failure the
  /// first read recorded.
  void _emit() {
    if (_disposed) return;
    Friend? friend;
    for (final f in _friends) {
      if (f.userId == friendId) {
        friend = f;
        break;
      }
    }
    CoachRelationship? coachEdge;
    CoachRelationship? clientEdge;
    CoachRelationship? pendingEdge;
    for (final edge in _edges) {
      final involvesThem =
          edge.coachUserId == friendId || edge.athleteUserId == friendId;
      if (!involvesThem) continue;
      if (!edge.isAccepted) {
        pendingEdge ??= edge;
      } else if (edge.coachUserId == friendId) {
        coachEdge ??= edge;
      } else {
        clientEdge ??= edge;
      }
    }
    state.value = FriendProfileState(
      friend: friend,
      coachEdge: coachEdge,
      clientEdge: clientEdge,
      pendingEdge: pendingEdge,
      assignments: _assignments,
      isLoading: !_friendsLoaded,
      isBusy: state.value.isBusy,
    );
  }

  // ── Coaching ───────────────────────────────────────────────────────────────

  Future<bool> requestCoaching() =>
      _command(() => _coachRepo.requestCoaching(me, friendId));

  Future<bool> offerCoaching() =>
      _command(() => _coachRepo.offerCoaching(me, friendId));

  Future<bool> acceptCoaching() =>
      _command(() => _coachRepo.acceptRequest(me, friendId));

  /// Declines a pending ask, withdraws the caller's own, or ends an accepted
  /// edge — one verb, because the RPC has one.
  Future<bool> endCoaching() =>
      _command(() => _coachRepo.remove(me, friendId));

  // ── Assignments ────────────────────────────────────────────────────────────

  Future<bool> acceptAssignment(CoachAssignment assignment) =>
      _command(() => _coachRepo.acceptAssignment(me, assignment));

  Future<bool> declineAssignment(CoachAssignment assignment) =>
      _command(() => _coachRepo.declineAssignment(me, assignment));

  Future<bool> withdrawAssignment(CoachAssignment assignment) =>
      _command(() => _coachRepo.withdrawAssignment(me, assignment));

  /// The caller's workouts for the assign sheet; null when the read failed.
  Future<List<PlannedSession>?> loadWorkouts() async {
    if (_disposed) return null;
    try {
      return await _coachRepo.assignableWorkouts(me);
    } catch (e) {
      if (_disposed) return null;
      state.value = state.value.copyWith(error: friendlyError(e));
      return null;
    }
  }

  Future<bool> assign(PlannedSession workout, {String? note}) => _command(
    () => _coachRepo.createAssignment(
      coachId: me,
      athleteId: friendId,
      workout: workout,
      note: note,
    ),
  );

  // ── The friendship ─────────────────────────────────────────────────────────

  Future<bool> setNickname(String? nickname) =>
      _command(() => _friendRepo.setNickname(me, friendId, nickname));

  Future<bool> setShareNotes(bool value) =>
      _command(() => _friendRepo.setShareNotes(me, friendId, value));

  Future<bool> unfriend() =>
      _command(() => _friendRepo.removeFriend(me, friendId));

  /// Runs one write, marking the state busy and recording a failure the
  /// command threw.
  Future<bool> _command(Future<void> Function() write) async {
    if (_disposed || state.value.isBusy) return false;
    state.value = state.value.copyWith(isBusy: true, clearError: true);
    try {
      await write();
      if (_disposed) return true;
      state.value = state.value.copyWith(isBusy: false);
      return true;
    } catch (e) {
      if (_disposed) return false;
      state.value = state.value.copyWith(
        isBusy: false,
        error: friendlyError(e),
      );
      return false;
    }
  }

  void clearError() {
    if (_disposed) return;
    state.value = state.value.copyWith(clearError: true);
  }

  void dispose() {
    _disposed = true;
    _friendSub?.cancel();
    _edgeSub?.cancel();
    _assignmentSub?.cancel();
    state.dispose();
  }
}

/// The signed-in user's id — the profile's host-test seam reads it through a
/// supplied view model, never this.
String currentUserId() => Supabase.instance.client.auth.currentUser!.id;
