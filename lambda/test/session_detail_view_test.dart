import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lambda/core/styles/app_spacing.dart';
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
import 'package:lambda/features/logs/view/session_detail_screen.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/floating_bar.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/segmented_control.dart';
import 'package:lambda/shared/widgets/session_chevron_button.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/readable_text.dart';
import 'support/fake_coach_repository.dart';

/// The past-session viewer IS the Training view, read-only (2026-10-22).
///
/// The PRs | Details | Reflection toggle is gone: the sets are the page, the
/// PRs live behind the trophy tile, the bookends behind the ratings pencil,
/// and the notes behind the book. The page reads like the live session —
/// the flat exercise card on the 22pt gutter, and the live session's own
/// floor: the date bar, undo/redo with the historic trash, the pencil and
/// the two tiles.
class _FakeSessionRepo extends Fake implements SessionRepository {
  final notesCalls =
      <
        ({
          String sessionId,
          String? preNotes,
          String? postNotes,
          int? preFeeling,
          int? postFeeling,
        })
      >[];

  /// Three completed sessions, newest first — the stack the date bar walks.
  static final _stamps = {
    'w2': DateTime(2026, 10, 21, 9),
    'w1': DateTime(2026, 10, 20, 9),
    'w0': DateTime(2026, 10, 19, 9),
  };

  /// Whether this device resumes a live session — the newest record's right
  /// arrow steps back onto it.
  bool hasLiveSession = false;

  /// Whether the record's one set is flagged — a deleted exercise, whose
  /// Restore button is the card's way back.
  bool hasDeletedSet = false;

  @override
  Future<Session?> fetchSession(String sessionId) async => Session(
    sessionId: sessionId,
    userId: 'u1',
    createdDatetime: _stamps[sessionId] ?? DateTime(2026, 10, 20, 9),
    endDatetime: DateTime(2026, 10, 20, 10),
    preNotes: 'Slept well',
    postNotes: 'Rushed the last set',
    preFeeling: 4,
    feeling: 3,
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
      hasLiveSession ? 'live1' : null;

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      [
        SessionExercise(
          sessionExerciseId: 'se-$sessionId',
          sessionId: sessionId,
          userId: 'u1',
          exerciseOrder: 1,
          exerciseId: 'ex1',
        ),
      ];

  /// Every record has ONE set, and each record's set carries its own weight
  /// — the assertive difference a walk test reads (w0 is the older, lighter
  /// record).
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
          weight: sessionId == 'w0' ? 40 : 60,
          reps: const [5],
          isDeleted: hasDeletedSet,
        ),
      ];

  @override
  Future<void> updateSessionNotes(
    String sessionId, {
    String? preNotes,
    String? postNotes,
    int? preFeeling,
    int? postFeeling,
  }) async {
    notesCalls.add((
      sessionId: sessionId,
      preNotes: preNotes,
      postNotes: postNotes,
      preFeeling: preFeeling,
      postFeeling: postFeeling,
    ));
  }
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
  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async => [
    // One born in THIS session, one from an older one: only the first
    // counts toward this session's number.
    ExerciseNote(
      exerciseNoteId: 'l1',
      userId: userId,
      exerciseId: exerciseId,
      text: 'Elbows tucked',
      pinned: false,
      createdDate: DateTime(2026, 10, 20),
      sessionId: 'w1',
    ),
    ExerciseNote(
      exerciseNoteId: 'l2',
      userId: userId,
      exerciseId: exerciseId,
      text: 'Old cue',
      pinned: false,
      createdDate: DateTime(2026, 9, 1),
      sessionId: 'w0',
    ),
    // Written after w1 (the record read first): the third shelf —
    // "previously" would misdate it (2026-10-23).
    ExerciseNote(
      exerciseNoteId: 'l3',
      userId: userId,
      exerciseId: exerciseId,
      text: 'Later cue',
      pinned: false,
      createdDate: DateTime(2026, 10, 22),
      sessionId: 'w2',
    ),
  ];
}

void main() {
  late _FakeSessionRepo repo;

  setUp(() {
    repo = _FakeSessionRepo();
    // The date bar's live check asks the device's id; the seam keeps it off
    // the preferences plugin, whose future does not settle under the test
    // binding's fake clock.
    DeviceId.override('device-1');
    PastSetsTimelineCache.loaderOverride = (u) async => const <PastSetRow>[];
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    DeviceId.override(null);
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  /// Loads the VM and pumps the shared body the way the /logs route does.
  Future<SessionDetailViewModel> pumpViewer(
    WidgetTester tester, {
    String sessionId = 'w1',
    VoidCallback? onWalkOlder,
    VoidCallback? onWalkNewer,
    bool readOnly = false,
    double? floorBottomInset,
    bool underBar = false,
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
          // The real screen opts out of the resize (2026-10-25): the floor
          // keeps its place and the keyboard paints over it. The harness
          // mirrors that, or the body's MediaQuery would have its bottom
          // viewInsets stripped and no keyboard test could see an inset.
          resizeToAvoidBottomInset: false,
          body: ValueListenableBuilder<SessionDetailState>(
            valueListenable: vm.state,
            builder: (context, state, _) {
              if (state.isLoading) return const SizedBox.shrink();
              final view = SessionDetailView(
                viewModel: vm,
                state: state,
                readOnly: readOnly,
                // The route carries the read/edit mode; a friend's record
                // does not (2026-10-27).
                canEdit: !readOnly,
                onWalkOlder: onWalkOlder,
                onWalkNewer: onWalkNewer,
                floorBottomInset: floorBottomInset,
              );
              // The shell's floor, for the tests that read the bar's
              // clearance: the viewer's own floor answers contentInset only
              // where something floats over it.
              if (!underBar) return view;
              return FloatingBarOverlay(
                bar: const SizedBox(height: FloatingBar.barHeight),
                child: view,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  /// The record walk is SESSION mode's (2026-10-23): both surfaces default to
  /// EXERCISE, which walks the active exercise's own performances on the
  /// card. The bar's chip is the door between the two stacks.
  Future<void> enterSessionMode(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('session-date-bar-mode-session')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the viewer draws the Training view — no toggle, date bar, flat '
      'card, the live floor row and both tiles', (tester) async {
    await pumpViewer(tester);

    // The readability rollout reaches the viewer with the rest of the app.
    // `—` is the numeric set-cell's absence glyph, quiet on purpose
    // (the `accessibility` skill's one allowance).
    expectReadableText(
      tester,
      find.byType(SessionDetailView),
      allowMuted: {'—'},
    );

    // The three-surface toggle is gone for good.
    expect(find.byType(SegmentedControl<String>), findsNothing);
    expect(find.text('Reflection'), findsNothing);
    expect(find.text('Details'), findsNothing);

    // The floor leads with the live page's date bar — the same widget on
    // both surfaces, saying PREVIOUSLY here because this is a record being
    // read (the live Training page says TODAY).
    expect(find.byKey(const ValueKey('session-date-bar')), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(
      find.text(DateFormat('d MMM yyyy').format(DateTime(2026, 10, 20))),
      findsOneWidget,
    );

    // The flat card — the page ground shows through.
    final card = tester.widget<Container>(
      find.byKey(const ValueKey('session-exercise-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.border, isNull);

    // The floor bar: star, trophy, pin.
    expect(find.byKey(const ValueKey('session-detail-bar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-detail-ratings-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('session-prs-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-notes-tile')), findsOneWidget);

    // ExerciseNote counting is session-scoped: the older cue is readable in the
    // modal but does not inflate this session's number. The count rides the
    // reading even though it is no longer drawn (2026-10-27).
    expect(
      find.bySemanticsLabel('1 exercise note this session'),
      findsOneWidget,
    );
    // The one logged set is the first set in its (exercise × variation) pair,
    // so it opens the frontier — a first PR derived from the session's own
    // rows, with no prior history to lean on.
    expect(find.bySemanticsLabel('1 PR this session'), findsOneWidget);
  });

  testWidgets('view mode is a record — no ADD SET, flat cells, a plain '
      'variation; edit mode brings the form back (2026-10-26)', (tester) async {
    final vm = await pumpViewer(tester);

    // What is NOT there: the dead row that would add a set, the boxed cell
    // that invites a keystroke, and the picker's chevron with no picker.
    expect(
      find.text('+ ADD SET'),
      findsNothing,
      reason: 'a record offers no way to add to it',
    );
    final readOnlyKg = tester.widget<TextField>(
      find.byKey(const ValueKey('history-set-1-kg')),
    );
    expect(readOnlyKg.decoration!.filled, isFalse);
    expect(readOnlyKg.decoration!.enabledBorder, InputBorder.none);
    expect(readOnlyKg.decoration!.focusedBorder, InputBorder.none);
    // Scoped to the row: the exercise selector's own field (the card's
    // header control) wears the same chevron.
    final row = find.byKey(const ValueKey('session-set-row-history-set-1'));
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsNothing,
      reason:
          'the variation cell is plain text — a chevron on a record '
          'promises a picker that is not there',
    );
    expect(
      find.descendant(of: row, matching: find.byType(DropdownSelect<String?>)),
      findsNothing,
    );
    expect(find.text('No Variation'), findsOneWidget);

    // And what edit mode must bring back — the flip is the assertion.
    vm.startEditing();
    await tester.pumpAndSettle();

    expect(find.text('+ ADD SET'), findsOneWidget);
    final editKg = tester.widget<TextField>(
      find.byKey(const ValueKey('history-set-1-kg')),
    );
    expect(editKg.decoration!.filled, isTrue);
    expect(editKg.decoration!.enabledBorder, isA<OutlineInputBorder>());
    expect(
      find.descendant(of: row, matching: find.byType(DropdownSelect<String?>)),
      findsOneWidget,
    );
  });

  testWidgets('view mode opens the ratings read-only', (tester) async {
    await pumpViewer(tester);

    await tester.tap(
      find.byKey(const ValueKey('session-detail-ratings-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-ratings-sheet')), findsOneWidget);
    // The stored answers, not empty boxes.
    expect(find.text('Slept well'), findsOneWidget);
    expect(find.text('Rushed the last set'), findsOneWidget);
    expect(
      find.byType(LambdaInput),
      findsNothing,
      reason: 'looking at a past session is not writing one',
    );
  });

  testWidgets('edit mode opens the ratings editable, and Done writes every '
      'answer in one call', (tester) async {
    final vm = await pumpViewer(tester);

    // The live floor's pair is drawn in BOTH modes — spent in view mode
    // (nothing has been edited to walk back), live in edit mode — so the
    // floor never changes shape with the mode. The trash rides in its slot
    // rather than the header, exactly where the live session keeps it.
    expect(find.bySemanticsLabel('Undo'), findsOneWidget);
    expect(find.bySemanticsLabel('Redo'), findsOneWidget);
    expect(find.bySemanticsLabel('Deleted exercises'), findsOneWidget);
    vm.startEditing();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Undo'), findsOneWidget);
    expect(find.bySemanticsLabel('Redo'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('session-detail-ratings-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(LambdaInput),
      findsNWidgets(2),
      reason: 'edit mode: the pre and post notes are writable',
    );
    await tester.enterText(
      // Inside the PRE section — the page has text fields of its own.
      find.descendant(
        of: find.byKey(const ValueKey('session-ratings-pre')),
        matching: find.byType(TextField),
      ),
      'Edited pre',
    );
    expect(vm.state.value.preNotesDraft, 'Edited pre');

    // Closing the sheet keeps the draft; the header's Done is this call.
    await tester.tap(find.byKey(const ValueKey('session-ratings-close')));
    await tester.pumpAndSettle();
    await vm.saveNotes();

    expect(repo.notesCalls, hasLength(1));
    final call = repo.notesCalls.single;
    expect(call.preNotes, 'Edited pre');
    expect(call.postNotes, 'Rushed the last set');
    expect(call.preFeeling, 4);
    expect(call.postFeeling, 3);
    expect(
      vm.state.value.isEditing,
      isFalse,
      reason: 'Done leaves edit mode once the write lands',
    );
  });

  testWidgets('the sheet\'s own pencil flips the page\'s mode from a read '
      'record (2026-10-27)', (tester) async {
    final vm = await pumpViewer(tester);
    expect(vm.state.value.isEditing, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('session-detail-ratings-button')),
    );
    await tester.pumpAndSettle();

    // Reading: no fields, and the pencil waiting in the sheet's own X
    // container.
    expect(find.byType(LambdaInput), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-ratings-edit')));
    await tester.pumpAndSettle();

    // The sheet's pencil drives the SAME mode the header glyph does.
    expect(vm.state.value.isEditing, isTrue);
    expect(find.byType(LambdaInput), findsNWidgets(2));

    // Typed answers land in the drafts the header's Done will persist.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('session-ratings-pre')),
        matching: find.byType(TextField),
      ),
      'Through the sheet',
    );
    expect(vm.state.value.preNotesDraft, 'Through the sheet');

    // Flipped back inside the sheet: the page's mode leaves with it.
    await tester.tap(find.byKey(const ValueKey('session-ratings-edit')));
    await tester.pumpAndSettle();
    expect(vm.state.value.isEditing, isFalse);
    expect(find.byType(LambdaInput), findsNothing);

    // A friend's record has no mode to switch — its sheet draws no pencil.
    // (The sheet closes first: pumpViewer re-updates the same MaterialApp
    // element, and a modal route would ride that update into the new mount.)
    await tester.tap(find.byKey(const ValueKey('session-ratings-close')));
    await tester.pumpAndSettle();
    await pumpViewer(tester, readOnly: true);
    await tester.tap(
      find.byKey(const ValueKey('session-detail-ratings-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('session-ratings-edit')),
      findsNothing,
      reason: 'somebody else\'s record is read, never edited',
    );
  });

  // ── The keyboard (2026-10-25) ─────────────────────────────────────────────

  testWidgets('the keyboard never lifts the floor; the card\'s viewport ends '
      'above it', (tester) async {
    // The iPhone 17's own frame, where the floor is 152 points tall and the
    // numeric pad's 291–300 would otherwise leave half a page dead.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    await pumpViewer(tester);

    final screen = tester.getRect(find.byType(Scaffold).first);
    final floorBefore = tester.getRect(
      find.byKey(const ValueKey('session-detail-bar')),
    );

    // 300 logical points of keyboard, the numeric pad's own order of height.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    final floorAfter = tester.getRect(
      find.byKey(const ValueKey('session-detail-bar')),
    );
    final scrollAfter = tester.getRect(find.byType(SingleChildScrollView));

    expect(
      floorAfter,
      floorBefore,
      reason: 'the floor keeps its place under the keyboard',
    );
    expect(
      scrollAfter.bottom,
      closeTo(screen.bottom - 300, 0.5),
      reason: 'the card\'s viewport ends at the keyboard\'s top',
    );
  });

  testWidgets('a keyboard shorter than the floor moves nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    await pumpViewer(tester);

    final floorBefore = tester.getRect(
      find.byKey(const ValueKey('session-detail-bar')),
    );
    final scrollBefore = tester.getRect(find.byType(SingleChildScrollView));
    expect(
      floorBefore.height,
      greaterThan(100),
      reason: 'this test is only meaningful while the floor is taller than it',
    );

    // 100 points of keyboard: entirely behind the floor, so the page keeps
    // every point the floor leaves it.
    tester.view.viewInsets = const FakeViewPadding(bottom: 100 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const ValueKey('session-detail-bar'))),
      floorBefore,
      reason: 'the floor keeps its place under the keyboard',
    );
    expect(
      tester.getRect(find.byType(SingleChildScrollView)),
      scrollBefore,
      reason: 'a keyboard the floor already covers takes nothing from the page',
    );
  });

  testWidgets('the date bar walks the stack from a record in the middle', (
    tester,
  ) async {
    var older = 0;
    var newer = 0;
    await pumpViewer(
      tester,
      onWalkOlder: () => older++,
      onWalkNewer: () => newer++,
    );
    await enterSessionMode(tester);

    await tester.tap(find.byKey(const ValueKey('session-date-bar-older')));
    await tester.tap(find.byKey(const ValueKey('session-date-bar-newer')));
    expect(older, 1, reason: 'w0 is one step older than w1');
    expect(newer, 1, reason: 'w2 is one step newer than w1');
  });

  testWidgets('the ends of the stack grey their arrow instead of losing it', (
    tester,
  ) async {
    // The oldest record has nothing older.
    await pumpViewer(
      tester,
      sessionId: 'w0',
      onWalkOlder: () {},
      onWalkNewer: () {},
    );
    await enterSessionMode(tester);
    expect(
      tester
          .widget<SessionChevronButton>(
            find.byKey(const ValueKey('session-date-bar-older')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<SessionChevronButton>(
            find.byKey(const ValueKey('session-date-bar-newer')),
          )
          .enabled,
      isTrue,
    );
  });

  testWidgets('the newest record steps back onto today only while a live '
      'session is resumable', (tester) async {
    await pumpViewer(tester, sessionId: 'w2', onWalkNewer: () {});
    await enterSessionMode(tester);
    expect(
      tester
          .widget<SessionChevronButton>(
            find.byKey(const ValueKey('session-date-bar-newer')),
          )
          .enabled,
      isFalse,
      reason: 'no live session — "today" is not a page this bar can reach',
    );

    repo.hasLiveSession = true;
    await pumpViewer(tester, sessionId: 'w2', onWalkNewer: () {});
    await enterSessionMode(tester);
    expect(
      tester
          .widget<SessionChevronButton>(
            find.byKey(const ValueKey('session-date-bar-newer')),
          )
          .enabled,
      isTrue,
      reason: 'the right arrow returns to the live Training page',
    );
  });

  // ── The walk is in place (2026-10-22) ─────────────────────────────────────

  testWidgets('a step swaps the record under the same page — no spinner, the '
      'sets replaced, the bar re-briefed', (tester) async {
    final vm = await pumpViewer(tester); // w1, 60 kg
    var sawLoading = false;
    vm.state.addListener(() {
      if (vm.state.value.isLoading) sawLoading = true;
    });

    await vm.walkTo('w0');
    await tester.pumpAndSettle();

    expect(
      sawLoading,
      isFalse,
      reason:
          'the record being left stays on screen — never a spinner over '
          'a page that already has sets',
    );
    expect(vm.state.value.session?.sessionId, 'w0');
    expect(
      vm.state.value.setsByOrder.values.expand((l) => l).single.weight,
      40,
      reason: 'the sets on the page are the stepped-to record\'s own',
    );
    // The bar now briefs itself on the record on screen: w0 is the oldest,
    // so its left arrow is spent and its right names the record just left.
    expect(vm.state.value.walk?.olderId, isNull);
    expect(vm.state.value.walk?.newerId, 'w1');
    // The page is still drawing — the walk never took the view away.
    expect(find.byType(SessionDetailView), findsOneWidget);
  });

  testWidgets('a step leaves the edit pass behind, and Done saves the record '
      'on screen — not the route\'s original id', (tester) async {
    final vm = await pumpViewer(tester);
    vm.startEditing();
    vm.setPreNotesDraft('written on w1');
    expect(vm.state.value.isEditing, isTrue);

    await vm.walkTo('w0');
    await tester.pumpAndSettle();

    expect(
      vm.state.value.isEditing,
      isFalse,
      reason: 'the arriving record opens read-only until its own Edit',
    );
    expect(
      vm.state.value.preNotesDraft,
      '',
      reason: 'the left record\'s draft must not be saved onto another record',
    );
    expect(
      vm.canUndo,
      isFalse,
      reason: 'undo steps never outlive their record',
    );

    vm.startEditing();
    await vm.saveNotes();
    expect(
      repo.notesCalls.single.sessionId,
      'w0',
      reason: 'the write follows the record on screen',
    );
  });

  // ── The floor's doors are the PR Lab's sheets (2026-10-22) ────────────────

  testWidgets('the trophy opens the PR History for the exercise and record on '
      'screen', (tester) async {
    await pumpViewer(tester, sessionId: 'w1');

    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pr-history-sheet')), findsOneWidget);
    expect(find.text('PR History'), findsOneWidget);
    // The exercise the card names, as the sheet's eyebrow.
    expect(find.text('RING PUSHUP'), findsOneWidget);
    // The record's own set opened the frontier, so its PR sits in the
    // middle shelf — headed by the record's date, because a record being
    // read is not "this session" to the reader (2026-10-23).
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('THIS SESSION'), findsNothing);
    expect(
      find.byKey(const ValueKey('pr-history-entry-set-w1')),
      findsOneWidget,
    );
    expect(find.text('60kg × 5'), findsOneWidget);
    expect(
      find.text('PREVIOUSLY'),
      findsNothing,
      reason: 'the fixture timeline holds no history behind w1',
    );
  });

  testWidgets('a past record splits its PR history around itself — before and '
      'after it', (tester) async {
    // Records on either side of w1 in the derived frontier — w0's 40 kg and
    // w2's 65 kg. Reading w1's trophy must place each on its own side of the
    // record (2026-10-23).
    PastSetsTimelineCache.loaderOverride = (u) async => [
      PastSetRow(
        sessionExerciseSetId: 'set-w0',
        sessionExerciseId: 'se-w0',
        sessionId: 'w0',
        userId: 'u1',
        exerciseId: 'ex1',
        setNumber: 1,
        weight: 40,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 19, 9),
        exerciseName: 'Ring Pushup',
      ),
      PastSetRow(
        sessionExerciseSetId: 'set-w2',
        sessionExerciseId: 'se-w2',
        sessionId: 'w2',
        userId: 'u1',
        exerciseId: 'ex1',
        setNumber: 1,
        weight: 65,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 21, 9),
        exerciseName: 'Ring Pushup',
      ),
    ];
    PastSetsTimelineCache.instance.invalidate();

    await pumpViewer(tester, sessionId: 'w1');
    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pumpAndSettle();

    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);

    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously), reason: 'before and after never mix');

    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('pr-history-entry-set-w2')))
          .dy,
      greaterThan(after),
      reason: 'w2\'s PR was achieved after the record being read',
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('pr-history-entry-set-w2')))
          .dy,
      lessThan(middle),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('pr-history-entry-set-w1')))
          .dy,
      greaterThan(middle),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('pr-history-entry-set-w1')))
          .dy,
      lessThan(previously),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('pr-history-entry-set-w0')))
          .dy,
      greaterThan(previously),
      reason: 'w0 came before w1',
    );
  });

  testWidgets('the book groups the notes by the record on screen — and '
      'walking the bar moves the group', (tester) async {
    final vm = await pumpViewer(tester, sessionId: 'w1');
    await tester.tap(find.byKey(const ValueKey('session-notes-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-sheet')), findsOneWidget);
    // Newest first (2026-10-23): the note written after w1 leads, then the
    // record's own shelf, headed by its date (a record being read is not
    // "this session" to the reader), then everything older.
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.text('20 OCT 2026'), findsOneWidget);
    expect(find.text('THIS SESSION'), findsNothing);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    final after = tester.getTopLeft(find.text('AFTER')).dy;
    final middle = tester.getTopLeft(find.text('20 OCT 2026')).dy;
    final previously = tester.getTopLeft(find.text('PREVIOUSLY')).dy;
    expect(after, lessThan(middle));
    expect(middle, lessThan(previously), reason: 'before and after never mix');
    expect(
      tester.getTopLeft(find.text('Later cue')).dy,
      greaterThan(after),
      reason: 'a note written after w1 sits above the record',
    );
    expect(tester.getTopLeft(find.text('Later cue')).dy, lessThan(middle));
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      greaterThan(middle),
      reason: 'w1\'s own note sits on its dated shelf',
    );
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      lessThan(previously),
    );
    expect(tester.getTopLeft(find.text('Old cue')).dy, greaterThan(previously));
    Navigator.of(
      tester.element(find.byKey(const ValueKey('notes-sheet'))),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();

    // Walk one record older: the shelf moves with the bar — w0's own cue
    // lands under its own date, and both later notes rise into the group
    // above it. The door follows the date on the bar, not the route that
    // opened the page.
    await vm.walkTo('w0');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-notes-tile')));
    await tester.pumpAndSettle();
    expect(find.text('19 OCT 2026'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsNothing);
    final walkedAfter = tester.getTopLeft(find.text('AFTER')).dy;
    final walkedMiddle = tester.getTopLeft(find.text('19 OCT 2026')).dy;
    expect(walkedAfter, lessThan(walkedMiddle));
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      greaterThan(walkedAfter),
      reason: 'written after w0, so it leads now',
    );
    expect(
      tester.getTopLeft(find.text('Elbows tucked')).dy,
      lessThan(walkedMiddle),
    );
    expect(
      tester.getTopLeft(find.text('Old cue')).dy,
      greaterThan(walkedMiddle),
      reason: 'w0\'s own note now sits on its dated shelf',
    );
  });

  // ── A friend's record (2026-10-23) ───────────────────────────────────────
  // The page is the Training view read-only already; a friend's record also
  // goes without the two write doors view mode still holds: the Restore
  // button and the notes composer.

  testWidgets('a friend\'s record draws no Restore under a deleted exercise — '
      'it is not theirs to restore', (tester) async {
    repo.hasDeletedSet = true;
    await pumpViewer(tester);
    expect(
      find.text('Restore'),
      findsOneWidget,
      reason: 'the reader\'s own record keeps the way back',
    );

    await pumpViewer(tester, readOnly: true);
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('a friend\'s exercise notes open read-only — the shelves draw, '
      'the composer and drawer do not', (tester) async {
    await pumpViewer(tester, readOnly: true);
    await tester.tap(find.byKey(const ValueKey('session-notes-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-sheet')), findsOneWidget);
    expect(find.text('Elbows tucked'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Add exercise note'),
      findsNothing,
      reason: 'a friend\'s notes are read, never added to',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notes-sheet')),
        matching: find.byType(SwipeActions),
      ),
      findsNothing,
      reason: 'no delete drawer on somebody else\'s notes',
    );

    // Tap-to-edit is gone too: the text is a read.
    await tester.tap(find.text('Elbows tucked'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notes-sheet')),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
  });

  // ── The floor's own clearance (2026-10-27) ───────────────────────────────
  // The viewer's floor is the live one: under the shell's floating bar it
  // reserves the bar's height below its action row. The another-device
  // preview is the one page whose own band, not the floor, clears the bar —
  // it hands the floor a small pad instead, so the bar's clearance is spent
  // once and the Switch button lands above the bar rather than under it.

  EdgeInsets floorPadding(WidgetTester tester) =>
      tester
              .widget<Container>(
                find.byKey(const ValueKey('session-detail-bar')),
              )
              .padding
          as EdgeInsets;

  testWidgets('the floor clears the shell\'s floating bar by default', (
    tester,
  ) async {
    await pumpViewer(tester, underBar: true);
    expect(
      floorPadding(tester).bottom,
      FloatingBar.barHeight + FloatingBar.floatGap + AppSpacing.lg,
      reason: 'the bar\'s height, its gap and the page\'s own air',
    );
  });

  testWidgets('a caller whose own band clears the bar keeps only its air', (
    tester,
  ) async {
    await pumpViewer(tester, underBar: true, floorBottomInset: AppSpacing.sm);
    expect(
      floorPadding(tester).bottom,
      AppSpacing.sm,
      reason: 'the preview\'s Switch band spends the clearance, not the floor',
    );
  });
}
