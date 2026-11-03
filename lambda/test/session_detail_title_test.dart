import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';

/// The header's one title owner (2026-10-23): the record's plan-name
/// snapshot, or Freestyle when it followed no plan. The live Training page
/// publishes this for the record its SESSION walk hosts; the past-session
/// viewer reads it directly — so both surfaces name the same record the
/// same way.
void main() {
  Session session({String? plannedSessionName}) => Session(
    sessionId: 's1',
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 20, 18),
    endDatetime: DateTime(2026, 10, 20, 19),
    plannedSessionName: plannedSessionName,
  );

  test('no record loaded reads as no title — the caller keeps its own name',
      () {
    const state = SessionDetailState();
    expect(state.sessionTitle, isNull);
  });

  test('a planned record is named by the plan it followed at the time', () {
    final state = SessionDetailState(
      session: session(plannedSessionName: 'Power Clean - Training B'),
    );
    expect(state.sessionTitle, 'Power Clean - Training B');
  });

  test('a record that followed no plan is a Freestyle Session', () {
    final state = SessionDetailState(session: session());
    expect(state.sessionTitle, 'Freestyle Session');
  });
}
