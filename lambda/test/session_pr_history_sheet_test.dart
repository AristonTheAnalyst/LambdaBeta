import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/session/model/pr_engine.dart';
import 'package:lambda/features/session/view/pr_history_sheet.dart';

/// The production PR History sheet (2026-10-22) — the PR Lab's feed behind
/// the session surfaces' trophy.
///
/// The sheet renders whatever feed it is handed: [sessionSetIds] lifts the
/// session's own PRs into `THIS SESSION`, and — when the caller also names
/// the session's start — the rest splits into `PREVIOUSLY` and `AFTER`
/// (2026-10-23), so a past record read from Logs never files a later
/// PR under "previously". The feed itself is newest first with the three
/// filters narrowing every group alike.

PrEvent _event({
  required String setId,
  required num weight,
  required num reps,
  required DateTime date,
  num? beforeWeight,
  num? beforeReps,
  String? variationId,
  String? variationName,
}) => PrEvent(
  exerciseId: 'ex1',
  exerciseName: 'Ring Pushup',
  weight: weight,
  reps: reps,
  achievedDate: date,
  sessionId: 'session-$setId',
  sessionExerciseSetId: setId,
  beforeWeight: beforeWeight,
  beforeReps: beforeReps,
  variationId: variationId,
  variationName: variationName,
);

final _prs = [
  _event(setId: 's0', weight: 50, reps: 5, date: DateTime(2026, 9, 1)),
  _event(
    setId: 's1',
    weight: 60,
    reps: 5,
    date: DateTime(2026, 10, 20),
    beforeWeight: 50,
  ),
  _event(
    setId: 's2',
    weight: 60,
    reps: 8,
    date: DateTime(2026, 10, 20),
    beforeReps: 5,
  ),
  // Same day as the session, but not one of its sets: the split is the set
  // ids' answer, never the date's.
  _event(
    setId: 's9',
    weight: 65,
    reps: 3,
    date: DateTime(2026, 10, 20),
    beforeWeight: 50,
  ),
];

Future<void> _openSheet(
  WidgetTester tester, {
  List<PrEvent>? prs,
  Set<String> sessionSetIds = const {'s1', 's2'},
  DateTime? sessionStartedAt,
  bool sessionIsLive = false,
  DateTime? sinceLastReviewAt,
  // The third group needs a taller stage than the 0.7 sheet offers at the
  // default phone height, or its entries sit past the list's viewport and
  // never lay out for the order assertions.
  double physicalHeight = 2622,
}) async {
  tester.view.physicalSize = Size(1206, physicalHeight);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPrHistorySheet(
                context,
                exerciseName: 'Ring Pushup',
                prs: prs ?? _prs,
                sessionSetIds: sessionSetIds,
                sessionStartedAt: sessionStartedAt,
                sessionIsLive: sessionIsLive,
                sinceLastReviewAt: sinceLastReviewAt,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the feed names the exercise and splits on the session\'s set '
      'ids — not on the date', (tester) async {
    await _openSheet(tester);

    expect(find.byKey(const ValueKey('pr-history-sheet')), findsOneWidget);
    expect(find.text('PR History'), findsOneWidget);
    expect(find.text('RING PUSHUP'), findsOneWidget);
    expect(find.text('4 PRs'), findsOneWidget);

    // Both groups draw, and the same-day outsider sits under PREVIOUSLY.
    expect(find.text('THIS SESSION'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    final thisSession = tester.getTopLeft(find.text('THIS SESSION')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(thisSession, lessThan(previously));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s9'))).dy,
      greaterThan(previously),
      reason: 's9 shares the date but not the session\'s ids',
    );
  });

  testWidgets('a past session reads newest first — after it, its own date, '
      'then previously', (tester) async {
    // A PR landed five days after the session on the desk — reading that
    // record from Logs must not file it under "previously" (2026-10-23),
    // and the feed runs chronologically: later shelf on top, older below.
    final later = _event(
      setId: 's10',
      weight: 70,
      reps: 3,
      date: DateTime(2026, 10, 25),
      beforeWeight: 65,
    );

    await _openSheet(
      tester,
      prs: [..._prs, later],
      sessionStartedAt: DateTime(2026, 10, 20),
      physicalHeight: 5622,
    );

    expect(find.text('5 PRs'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    // A record's middle shelf is dated — it is not the reader's session.
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('THIS SESSION'), findsNothing);
    expect(find.text('PREVIOUSLY'), findsOneWidget);

    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously), reason: 'before and after never mix');

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s10'))).dy,
      greaterThan(after),
      reason: 'a PR achieved after the record read is not "previously"',
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s10'))).dy,
      lessThan(middle),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s9'))).dy,
      greaterThan(previously),
      reason: 's9 shares the session\'s day but landed before it',
    );
  });

  testWidgets('a review checkpoint splits the after-group — since the last '
      'pass above what came before it', (tester) async {
    final beforeReview = _event(
      setId: 's10',
      weight: 68,
      reps: 3,
      date: DateTime(2026, 10, 21),
      beforeWeight: 65,
    );
    final sinceReview = _event(
      setId: 's11',
      weight: 70,
      reps: 3,
      date: DateTime(2026, 10, 25),
      beforeWeight: 68,
    );

    await _openSheet(
      tester,
      prs: [..._prs, beforeReview, sinceReview],
      sessionStartedAt: DateTime(2026, 10, 20),
      sinceLastReviewAt: DateTime(2026, 10, 22),
      physicalHeight: 6622,
    );

    expect(find.text('6 PRs'), findsOneWidget);
    expect(find.text('SINCE LAST REVIEW'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);

    final since = tester.getTopLeft(find.text('SINCE LAST REVIEW')).dy;
    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(since, lessThan(after), reason: 'the newer half leads the feed');
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously));

    final sinceEntry = tester
        .getTopLeft(find.byKey(const ValueKey('pr-history-entry-s11')))
        .dy;
    final beforeEntry = tester
        .getTopLeft(find.byKey(const ValueKey('pr-history-entry-s10')))
        .dy;
    expect(sinceEntry, greaterThan(since));
    expect(sinceEntry, lessThan(after));
    expect(beforeEntry, greaterThan(after));
    expect(beforeEntry, lessThan(middle));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s9'))).dy,
      greaterThan(previously),
      reason: 'a PR from before the session is never "since the last review"',
    );
  });

  testWidgets('the middle shelf says THIS SESSION only for the live session', (
    tester,
  ) async {
    await _openSheet(
      tester,
      sessionStartedAt: DateTime(2026, 10, 20),
      sessionIsLive: true,
    );

    expect(find.text('THIS SESSION'), findsOneWidget);
    expect(find.text('20 OCT 2026'), findsNothing);
  });

  testWidgets('without the session start the lab\'s two groups stand', (
    tester,
  ) async {
    final later = _event(
      setId: 's10',
      weight: 70,
      reps: 3,
      date: DateTime(2026, 10, 25),
      beforeWeight: 65,
    );
    await _openSheet(tester, prs: [..._prs, later], physicalHeight: 5622);

    expect(find.text('AFTER'), findsNothing);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s10'))).dy,
      greaterThan(tester.getTopLeft(find.text('PREVIOUSLY')).dy),
      reason:
          'a caller that cannot place the session in time invents no '
          'boundary',
    );
  });

  // The planner opens the same sheet with no session on the desk and no set
  // ids (2026-10-26): there is no after-group to split, so the checkpoint
  // divides the whole feed — the pass's PRs lead, the rest is PREVIOUSLY.
  testWidgets('with no session on the desk the checkpoint splits the whole '
      'feed', (tester) async {
    final beforeReview = _event(
      setId: 's10',
      weight: 68,
      reps: 3,
      date: DateTime(2026, 10, 21),
      beforeWeight: 65,
    );
    final sinceReview = _event(
      setId: 's11',
      weight: 70,
      reps: 3,
      date: DateTime(2026, 10, 25),
      beforeWeight: 68,
    );

    await _openSheet(
      tester,
      prs: [..._prs, beforeReview, sinceReview],
      sessionSetIds: const <String>{},
      sinceLastReviewAt: DateTime(2026, 10, 22),
      physicalHeight: 6622,
    );

    expect(find.text('6 PRs'), findsOneWidget);
    expect(find.text('SINCE LAST REVIEW'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    expect(
      find.text('AFTER'),
      findsNothing,
      reason: 'a plan has no session for "after the session" to mean',
    );
    expect(
      find.text('THIS SESSION'),
      findsNothing,
      reason: 'and no set ids, so no session shelf either',
    );

    final since = tester.getTopLeft(find.text('SINCE LAST REVIEW')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(since, lessThan(previously));

    final sinceEntry = tester
        .getTopLeft(find.byKey(const ValueKey('pr-history-entry-s11')))
        .dy;
    final beforeEntry = tester
        .getTopLeft(find.byKey(const ValueKey('pr-history-entry-s10')))
        .dy;
    expect(sinceEntry, greaterThan(since));
    expect(sinceEntry, lessThan(previously));
    expect(beforeEntry, greaterThan(previously));
  });

  testWidgets('the feed runs newest first, and a session PR names the value '
      'it beat', (tester) async {
    await _openSheet(tester);

    // Two PRs landed the same day: the later (60 × 8) leads the 60 × 5.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s2'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('pr-history-entry-s1'))).dy,
      ),
    );
    // 60 × 8 beat the best reps at exactly 60 — named alone.
    final entry = find.byKey(const ValueKey('pr-history-entry-s2'));
    expect(
      find.descendant(of: entry, matching: find.text('60kg × 5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: entry, matching: find.text('WAS')),
      findsOneWidget,
    );
    // The oldest entry had nothing to beat.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pr-history-entry-s0')),
        matching: find.text('FIRST PR'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the weight filter narrows both groups and the count follows', (
    tester,
  ) async {
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('pr-history-weight-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('60 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 kg'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 4 PRs'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-history-entry-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-history-entry-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-history-entry-s9')), findsNothing);
    expect(
      find.text('PREVIOUSLY'),
      findsNothing,
      reason: 'a group with nothing left draws no heading',
    );
  });

  testWidgets('filters that meet nothing say so instead of drawing an empty '
      'list', (tester) async {
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('pr-history-weight-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('65 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('65 kg'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pr-history-reps-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('5 reps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 reps'));
    await tester.pumpAndSettle();

    expect(find.text('No PRs match'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-history-list')), findsNothing);
  });

  testWidgets('the sheet stands at 0.7 of the screen whatever the feed holds', (
    tester,
  ) async {
    await _openSheet(tester);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getSize(find.byKey(const ValueKey('pr-history-sheet'))).height,
      closeTo(screenHeight * 0.7, 1),
    );
  });
}
