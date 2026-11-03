import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/device_id.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/exercise_note.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:lambda/features/session/view/session_history_peek.dart';
import 'package:lambda/shared/widgets/session_chevron_button.dart';
import 'support/fake_coach_repository.dart';

/// The live Training page's history peek (2026-10-22).
///
/// The date bar's steps never navigate: the same page swaps the record's
/// sets under it, and only the newest record's right arrow leaves the
/// record — a callback onto today's live sets, not a pop or a route.
class _FakeSessionRepo extends Fake implements SessionRepository {
  static final _stamps = {
    'w2': DateTime(2026, 10, 21, 9),
    'w1': DateTime(2026, 10, 20, 9),
    'w0': DateTime(2026, 10, 19, 9),
  };

  /// Weight per record — the assertive difference a walk test reads.
  static const _weights = {'w2': 80.0, 'w1': 60.0, 'w0': 40.0};

  @override
  Future<Session?> fetchSession(String sessionId) async => Session(
    sessionId: sessionId,
    userId: 'u1',
    createdDatetime: _stamps[sessionId] ?? DateTime(2026, 10, 20, 9),
    endDatetime: DateTime(2026, 10, 20, 10),
    plannedSessionName: 'Upper A',
  );

  @override
  Future<List<({String sessionId, DateTime createdDatetime})>>
  loadCompletedSessionStamps(String userId) async => [
    for (final entry in _stamps.entries)
      (sessionId: entry.key, createdDatetime: entry.value),
  ];

  @override
  Future<String?> getActiveSessionId(String userId, {String? deviceId}) async =>
      'live1';

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async => [
    SessionExercise(
      sessionExerciseId: 'se-$sessionId',
      sessionId: sessionId,
      userId: 'u1',
      exerciseOrder: 1,
      exerciseId: 'ex1',
    ),
  ];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      [
        SessionExerciseSet(
          sessionExerciseSetId: 'set-$sessionId',
          sessionExerciseId: 'se-$sessionId',
          sessionId: sessionId,
          userId: 'u1',
          exerciseId: 'ex1',
          setNumber: 1,
          weight: _weights[sessionId],
          reps: const [5],
        ),
      ];
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {
    'ex1': const ExerciseDetail(
      exercise: CustomExercise(
        exerciseId: 'ex1',
        userId: 'u1',
        name: 'Ring Pushup',
      ),
    ),
  };

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

class _FakeExerciseNoteRepo extends Fake implements ExerciseNoteRepository {
  @override
  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async =>
      const [];
}

void main() {
  late _FakeSessionRepo repo;

  setUp(() {
    repo = _FakeSessionRepo();
    DeviceId.override('device-1');
    PastSetsTimelineCache.loaderOverride = (u) async => const <PastSetRow>[];
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    DeviceId.override(null);
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  /// Loads the peek at [sessionId] and pumps it the way the live Training
  /// page hosts it.
  Future<SessionDetailViewModel> pumpPeek(
    WidgetTester tester, {
    required VoidCallback onExit,
    String sessionId = 'w2',
  }) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final vm = SessionDetailViewModel(
      coachRepo: FakeCoachRepository(),
      sessionRepo: repo,
      exerciseRepo: _FakeExerciseRepo(),
      noteRepo: _FakeExerciseNoteRepo(),
      userId: 'u1',
    );
    await vm.load(sessionId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<SessionDetailState>(
            valueListenable: vm.state,
            builder: (context, state, _) => SessionHistoryPeek(
              viewModel: vm,
              state: state,
              onExit: onExit,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  double weightOf(SessionDetailViewModel vm) => vm
      .state
      .value
      .setsByOrder
      .values
      .expand((l) => l)
      .single
      .weight!;

  bool enabledOf(WidgetTester tester, String key) => tester
      .widget<SessionChevronButton>(find.byKey(ValueKey(key)))
      .enabled;

  /// The record walk is SESSION mode's (2026-10-23): both surfaces default to
  /// EXERCISE, which walks the active exercise's own performances on the
  /// card. The bar's chip is the door between the two stacks.
  Future<void> enterSessionMode(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('session-date-bar-mode-session')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the live page hosts the record itself — PREVIOUSLY, the '
      'viewer\'s card, no navigation', (tester) async {
    var exits = 0;
    await pumpPeek(tester, onExit: () => exits++);

    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-exercise-card')), findsOneWidget);
    expect(exits, 0);
  });

  testWidgets('a step swaps the record in place: the sets change under the '
      'same page, without a spinner or an exit', (tester) async {
    var exits = 0;
    final vm = await pumpPeek(tester, onExit: () => exits++);
    expect(weightOf(vm), 80);
    await enterSessionMode(tester);
    var sawLoading = false;
    vm.state.addListener(() {
      if (vm.state.value.isLoading) sawLoading = true;
    });

    await tester.tap(find.byKey(const ValueKey('session-date-bar-older')));
    await tester.pumpAndSettle();

    expect(weightOf(vm), 60, reason: 'w1\'s own set is on the card now');
    expect(vm.state.value.session?.sessionId, 'w1');
    expect(
      sawLoading,
      isFalse,
      reason: 'the record being left stays on screen — the viewer\'s own '
          'in-place rule',
    );
    expect(exits, 0, reason: 'a record-to-record step never leaves the page');
    expect(find.byType(SessionHistoryPeek), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('session-date-bar-newer')));
    await tester.pumpAndSettle();
    expect(weightOf(vm), 80, reason: 'the right arrow walks back to w2');
  });

  testWidgets('the newest record\'s right arrow steps onto today through the '
      'page\'s own callback — not a pop', (tester) async {
    var exits = 0;
    await pumpPeek(tester, onExit: () => exits++);
    await enterSessionMode(tester);

    expect(
      enabledOf(tester, 'session-date-bar-newer'),
      isTrue,
      reason: 'the live session stands past the newest record',
    );
    await tester.tap(find.byKey(const ValueKey('session-date-bar-newer')));
    await tester.pumpAndSettle();
    expect(exits, 1, reason: 'today is the live page still mounted below');
  });

  testWidgets('the oldest record greys its left arrow instead of leaving the '
      'stack', (tester) async {
    final vm = await pumpPeek(tester, onExit: () {}, sessionId: 'w0');
    await enterSessionMode(tester);

    expect(enabledOf(tester, 'session-date-bar-older'), isFalse);
    expect(enabledOf(tester, 'session-date-bar-newer'), isTrue);
    expect(vm.state.value.walk?.olderId, isNull);
  });
}
