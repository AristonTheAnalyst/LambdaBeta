import 'package:lambda/data/models/coach_feedback.dart';
import 'package:lambda/data/repositories/coach_repository.dart';

/// The coach side of the past-session viewer, silent by default (2026-10-26,
/// #24).
///
/// The viewer now watches `fact_coach_feedback` for whatever record it shows,
/// which reads the local mirror — a database host tests never open. Every
/// suite that is not about coaching passes this in so the subscription answers
/// an empty stream instead of touching the database; `test/coach_authoring_test
/// .dart` covers the real behaviour.
class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.feedback = const []});

  /// What the watch emits — the card's content in viewer tests.
  List<CoachFeedback> feedback;

  /// Ids [userNames] was asked to resolve, once per call.
  final nameRequests = <List<String>>[];

  @override
  Stream<List<CoachFeedback>> watchFeedback(String sessionId) =>
      Stream.value(feedback);

  @override
  Future<Map<String, String>> userNames(Iterable<String> userIds) async {
    nameRequests.add(userIds.toList());
    return const {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
