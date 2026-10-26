import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/athlete.dart';
import 'package:lambda/data/models/coach_relationship.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:lambda/features/coach/viewmodel/coach_viewmodel.dart';

/// A repository that answers with fixed rows and records every command — the
/// ViewModel's contract without a database or a Supabase client.
class _FakeCoachRepository extends Fake implements CoachRepository {
  _FakeCoachRepository(this.rows);

  final List<CoachRelationship> rows;
  final invites = <String>[];
  final accepted = <String>[];
  final removed = <String>[];
  Object? inviteError;
  Object? acceptError;

  @override
  Stream<List<CoachRelationship>> watchRelationships(String userId) =>
      Stream.value(rows);

  @override
  Future<CoachInvite> inviteByCode(String userId, String rawCode) async {
    invites.add(rawCode);
    final error = inviteError;
    if (error != null) throw error;
    return const CoachInvite(athleteUserId: 'a-new', created: true);
  }

  @override
  Future<void> acceptInvitation(String userId, String coachId) async {
    final error = acceptError;
    if (error != null) throw error;
    accepted.add(coachId);
  }

  @override
  Future<void> remove(String userId, String otherId) async {
    removed.add(otherId);
  }
}

CoachRelationship _row({
  required String coach,
  required String athlete,
  String? coachName,
  String? athleteName,
  DateTime? created,
  DateTime? accepted,
}) => CoachRelationship(
  coachUserId: coach,
  athleteUserId: athlete,
  coachFirstName: coachName,
  athleteFirstName: athleteName,
  createdDate: created ?? DateTime.utc(2026, 10, 20, 12),
  acceptedDate: accepted,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = 'me';

  group('CoachViewModel — the four slices', () {
    test('splits by side and consent, and sorts each list', () async {
      final repo = _FakeCoachRepository([
        // Accepted: I coach Zed and Amy (name order wins).
        _row(
          coach: me,
          athlete: 'zed',
          athleteName: 'Zed',
          accepted: DateTime.utc(2026, 10, 1),
        ),
        _row(
          coach: me,
          athlete: 'amy',
          athleteName: 'Amy',
          accepted: DateTime.utc(2026, 10, 2),
        ),
        // Pending, sent by me — nameless by design.
        _row(
          coach: me,
          athlete: 'pending-a',
          created: DateTime.utc(2026, 10, 5),
        ),
        _row(
          coach: me,
          athlete: 'pending-b',
          created: DateTime.utc(2026, 10, 4),
        ),
        // Invitation waiting on me — coach's name is present.
        _row(
          coach: 'coach-1',
          athlete: me,
          coachName: 'Jamie',
          created: DateTime.utc(2026, 10, 6),
        ),
        // Accepted coach of mine.
        _row(
          coach: 'coach-2',
          athlete: me,
          coachName: 'Rivera',
          accepted: DateTime.utc(2026, 10, 3),
        ),
      ]);
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final state = vm.state.value;
      expect(state.isLoading, isFalse);
      expect(state.athletes.map((a) => a.userId), [
        'amy',
        'zed',
      ], reason: 'accepted athletes order by name');
      expect(state.pendingSent.map((a) => a.userId), [
        'pending-a',
        'pending-b',
      ], reason: 'pending invitations order newest first');
      expect(
        state.invitations.single.userId,
        'coach-1',
        reason: 'an incoming invitation names the coach',
      );
      expect(state.invitations.single.displayName, 'Jamie');
      expect(state.coaches.single.userId, 'coach-2');
      expect(state.coaches.single.displayName, 'Rivera');
      expect(state.isEmpty, isFalse);
    });

    test('no relationships is the empty state, not a loading one', () async {
      final repo = _FakeCoachRepository([]);
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      expect(vm.state.value.isLoading, isFalse);
      expect(vm.state.value.isEmpty, isTrue);
    });
  });

  group('CoachViewModel — commands', () {
    test('invite reports the RPC result and drops isInviting', () async {
      final repo = _FakeCoachRepository([]);
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final result = await vm.invite('ABCDEFGH');
      expect(repo.invites, ['ABCDEFGH']);
      expect(result?.athleteUserId, 'a-new');
      expect(result?.created, isTrue);
      expect(vm.state.value.isInviting, isFalse);
      expect(vm.state.value.error, isNull);
    });

    test('a refused invite records the sentence and answers null', () async {
      final repo = _FakeCoachRepository([])
        ..inviteError = Exception('no such code');
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final result = await vm.invite('ABCDEFGH');
      expect(result, isNull);
      expect(vm.state.value.isInviting, isFalse);
      expect(vm.state.value.error, isNotNull);
    });

    test('accept calls the acceptance for the coach on the card', () async {
      final repo = _FakeCoachRepository([]);
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final ok = await vm.accept(const Athlete(userId: 'coach-1'));
      expect(ok, isTrue);
      expect(repo.accepted, ['coach-1']);
    });

    test('a refused accept records the sentence and answers false', () async {
      final repo = _FakeCoachRepository([])..acceptError = Exception('gone');
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final ok = await vm.accept(const Athlete(userId: 'coach-1'));
      expect(ok, isFalse);
      expect(vm.state.value.error, isNotNull);
    });

    test('remove ends the edge for whichever person it is given', () async {
      final repo = _FakeCoachRepository([]);
      final vm = CoachViewModel(repo: repo, userId: me);
      addTearDown(vm.dispose);
      vm.start();
      await pumpEventQueue();

      final ok = await vm.remove(const Athlete(userId: 'other'));
      expect(ok, isTrue);
      expect(repo.removed, ['other']);
    });
  });
}
