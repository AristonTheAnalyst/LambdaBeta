import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/core/styles/app_spacing.dart';
import 'package:lambda/core/styles/app_text_styles.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/goals/view/goal_row.dart';
import 'package:lambda/features/programs/view/content_diff_sheet.dart';
import 'package:lambda/features/programs/view/record_workout_screen.dart';
import 'package:lambda/features/programs/view/review_container.dart';
import 'package:lambda/shared/widgets/container_styles.dart';
import 'package:lambda/shared/widgets/exercise_selector.dart';
import 'package:lambda/shared/widgets/floating_bar.dart';
import 'package:lambda/shared/widgets/glass_button.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';
import 'package:lambda/shared/widgets/scroll_shrink_nav_bar.dart';
import 'package:lambda/shared/widgets/session_exercise_card.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/fake_program_repos.dart';

/// The review ceremony's load-bearing rules.
///
/// The container is deliberately quiet: it puts a bar up and otherwise gets out
/// of the way. Which means the ways it goes wrong are quiet too — a bar that
/// lingers on screens with no review, a nav bar left standing under a pass, a
/// Done that records a workout WITHOUT the edits the user just made in it, or
/// text on the floating bar inheriting MaterialApp's error style and coming
/// out underlined in yellow, which is exactly what the bar did while it was
/// drawn outside any Material. Every one of those is invisible in a screenshot
/// and obvious here.
///
/// The bar's two modes are pinned here as well: **overview** (the landing —
/// the pass's progress and Finish) and **workout** (the glyph verbs). The
/// verbs belong to different altitudes, and a bar that offered all of them
/// everywhere would ask "finish the whole pass?" from inside one workout. The
/// tick's landing is a third state — the label turns green and reads
/// [kReviewCompleteLabel], and the workout stays on screen under it — and it is
/// pinned in the `Done` group below.
/// The bar's workout verbs, as glyphs: the note a set's own swipe wears, an
/// eye (Compare — "show me the record"), two half-overlapping shapes
/// (Changes — "tell me what moved"), and a tick. Named here so the tests
/// that exercise them read as the verbs rather than as font glyphs — and so
/// the bar's glyphs are pinned in one place.
///
/// The eye has two halves, because the toggle wears its state: outlined at
/// rest, filled while the record is up. Tests name the half they expect
/// instead of asking only that an eye exists.
const kNoteGlyph = Icons.sticky_note_2_outlined;
const kCompareGlyph = Icons.visibility_outlined;
const kCompareGlyphOn = Icons.visibility;
const kChangesGlyph = Icons.difference_outlined;
const kDoneGlyph = Icons.check;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont(AppFonts.uiFamily, const [
      'assets/fonts/Manrope-400.ttf',
      'assets/fonts/Manrope-600.ttf',
      'assets/fonts/Manrope-800.ttf',
    ]);
    await _loadFont(AppFonts.monoFamily, const [
      'assets/fonts/JetBrainsMono-400.ttf',
      'assets/fonts/JetBrainsMono-700.ttf',
    ]);
  });

  // The session is process-global — matching `themeNotifier` — so a test that
  // left one running would hand it to the next one.
  setUp(() => reviewSessionNotifier.value = null);
  tearDown(() => reviewSessionNotifier.value = null);

  ReviewSession session({
    String reviewId = 'rev1',
    String? title,
    List<String> sessionIds = const ['s1'],
    List<String> goalIds = const [],
    Map<String, DateTime> reviewed = const {},
    String? activeSessionId,
    String? activeWorkoutName,
    String? programId = 'prog1',
  }) => ReviewSession(
    reviewId: reviewId,
    programId: programId,
    sessionIds: sessionIds,
    goalIds: goalIds,
    reviewed: reviewed,
    activeSessionId: activeSessionId,
    activeWorkoutName: activeWorkoutName,
    title: title,
  );

  /// Pumps a `Scaffold` inside a real [ReviewScope], handing the builder a
  /// context that is genuinely below it — which is the whole point, since the
  /// chrome reads the ambient session off that chain.
  Future<void> pumpScaffold(
    WidgetTester tester,
    Widget Function(BuildContext context) build,
  ) => tester.pumpWidget(
    ReviewScope(child: MaterialApp(home: Builder(builder: build))),
  );

  /// The real stack in miniature: a base page with a route named
  /// [kReviewRouteName] pushed over it and the bar inside that route — the
  /// shape [startReview] builds. Returns the future its caller awaited, which
  /// must resolve once the route unwinds.
  Future<Future<bool?>> pumpReviewRoute(
    WidgetTester tester,
    Widget Function(BuildContext context) build,
  ) async {
    late BuildContext root;
    await tester.pumpWidget(
      ReviewScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold(body: Text('base page'));
            },
          ),
        ),
      ),
    );
    final result = Navigator.of(root, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kReviewRouteName),
        builder: build,
      ),
    );
    await tester.pumpAndSettle();
    return result;
  }

  group('reviewChrome', () {
    testWidgets('draws nothing when no review is running', (tester) async {
      await pumpScaffold(
        tester,
        (context) =>
            reviewChrome(context, settle: null, child: const Text('page')),
      );

      expect(find.text('page'), findsOneWidget);
      expect(find.byType(FloatingBar), findsNothing);
      expect(find.textContaining('In Review'), findsNothing);
    });

    testWidgets('puts the bar up once a review is running', (tester) async {
      reviewSessionNotifier.value = session();
      await pumpScaffold(
        tester,
        (context) => reviewChrome(
          context,
          settle: () async => true,
          child: const Text('page'),
        ),
      );

      expect(
        find.text('In Review · 0 of 1'),
        findsOneWidget,
        reason: 'with no workout open the bar reads the pass, not the workout',
      );
      expect(find.text('page'), findsOneWidget,
          reason: 'the page is still there — the bar is painted over it, not '
              'instead of it');
    });

    testWidgets('hides Done when the editor behind it cannot settle, and '
        'offers no second way out — leaving is the editor\'s own back guard', (
      tester,
    ) async {
      // The container's loading and dead-end states draw the bar with no
      // editor under it: nothing examined means nothing to record.
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      await pumpScaffold(
        tester,
        (context) =>
            reviewChrome(context, settle: null, child: const Text('page')),
      );

      expect(find.text('In Review'), findsOneWidget);
      expect(
        find.byIcon(kDoneGlyph),
        findsNothing,
        reason: 'a tick over an editor that cannot save would say "finished '
            'with this one" about a change that never landed',
      );
      expect(
        find.text('Finish'),
        findsNothing,
        reason: 'the editor\'s bar carries the workout\'s verbs — the pass is '
            'finished from the landing',
      );
      expect(
        find.byIcon(Icons.close),
        findsNothing,
        reason: 'the bar carries decisions about the review, not navigation — '
            'there is no × on it',
      );
    });

    testWidgets('shows Done once a workout is open and the editor can settle',
        (tester) async {
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      await pumpScaffold(
        tester,
        (context) => reviewChrome(
          context,
          settle: () async => true,
          child: const Text('editor'),
        ),
      );

      expect(find.text('In Review'), findsOneWidget);
      expect(find.byIcon(kDoneGlyph), findsOneWidget);
    });
  });

  group('editorNavBar', () {
    testWidgets('is the nav bar outside a review', (tester) async {
      await pumpScaffold(
        tester,
        (context) => editorNavBar(
          context,
          onTap: (_) {},
          settle: null,
          child: const Text('page'),
        ),
      );

      expect(find.byType(ScrollShrinkNavBar), findsOneWidget);
      expect(find.textContaining('In Review'), findsNothing);
    });

    testWidgets('stands the nav bar down for the length of a pass', (
      tester,
    ) async {
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      await pumpScaffold(
        tester,
        (context) => editorNavBar(
          context,
          onTap: (_) {},
          settle: () async => true,
          settleForCompare: () async => true,
          onComparison: (_) {},
          child: const Text('page'),
        ),
      );

      expect(find.text('In Review'), findsOneWidget);
      expect(find.byIcon(kCompareGlyph), findsOneWidget);
      expect(find.byIcon(kDoneGlyph), findsOneWidget);
      expect(
        find.byType(ScrollShrinkNavBar),
        findsNothing,
        reason: 'two bars at the floor is worse than either alone — the pass '
            'owns the bottom of the screen while it runs',
      );
      expect(
        find.byType(FloatingBar),
        findsOneWidget,
        reason: 'and the bar it owns is the same container the nav bar wears',
      );
    });
  });

  group('bar modes', () {
    testWidgets('the landing\'s bar counts the pass and offers Finish — no '
        'workout verbs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(
              sessionIds: const ['s1', 's2'],
              reviewed: {'s1': DateTime(2026, 3, 1)},
            ),
            onFinish: () async {},
          ),
        ),
      );

      expect(
        find.text('In Review · 1 of 2'),
        findsOneWidget,
        reason: 'the overview answers "how far through am I" at a glance — '
            'that is what the ticks are for',
      );
      expect(find.text('Finish'), findsOneWidget);
      expect(find.byIcon(kCompareGlyph), findsNothing);
      expect(find.byIcon(kDoneGlyph), findsNothing);
    });

    testWidgets('the landing\'s bar waits on the whole pass before Finish', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(sessionIds: const ['s1', 's2']),
            onFinish: () async {},
            // The whole pass: workouts plus goals, as the landing counts it.
            overviewProgress: (done: 1, total: 3),
          ),
        ),
      );

      expect(
        find.text('In Review · 1 of 3'),
        findsOneWidget,
        reason: 'the tally handed in is the whole pass, so the count and the '
            'gate always speak for the same work',
      );
      expect(
        tester
            .widget<GlassButton>(find.widgetWithText(GlassButton, 'Finish'))
            .disabled,
        isTrue,
        reason: 'a pass with work left in it is not finished, and the bar says '
            'so by refusing the button rather than by asking afterwards — the '
            'tabs say which half is holding it up',
      );
    });

    testWidgets('the tally landing on the whole pass opens Finish', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(sessionIds: const ['s1', 's2']),
            onFinish: () async {},
            overviewProgress: (done: 3, total: 3),
          ),
        ),
      );

      expect(find.text('In Review · 3 of 3'), findsOneWidget);
      expect(
        tester
            .widget<GlassButton>(find.widgetWithText(GlassButton, 'Finish'))
            .disabled,
        isFalse,
        reason: 'every workout walked and every goal reported — the pass is '
            'finished, and Finish is the way to say it',
      );
    });

    testWidgets('a workout\'s bar offers Compare and Done — never Finish', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            onComparison: (_) {},
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(find.text('In Review'), findsOneWidget);
      expect(find.byIcon(kCompareGlyph), findsOneWidget);
      expect(find.byIcon(kDoneGlyph), findsOneWidget);
      expect(
        find.text('Finish'),
        findsNothing,
        reason: 'finishing the pass is a decision about the whole set, and it '
            'is taken on the landing, where the set is',
      );
    });

    testWidgets('the bar carries the workout\'s note, beside its other two '
        'verbs', (tester) async {
      // The note is per-workout, like Compare and Done, so it stands with
      // them — the editor's header used to carry it beside the workout's name,
      // which put the pass's verbs on two different shelves.
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(
              programId: null,
              activeSessionId: 's1',
              activeWorkoutName: 'Push Day',
            ),
            settleForCompare: () async => true,
            onComparison: (_) {},
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(
        find.byIcon(kNoteGlyph),
        findsOneWidget,
        reason: 'the glyph a set\'s own note wears, so one note reads the same '
            'wherever it is reached from',
      );
      expect(find.byIcon(kCompareGlyph), findsOneWidget);
      expect(find.byIcon(kDoneGlyph), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(kNoteGlyph)).color,
        AppColors.muted,
        reason: 'the workout has no note yet, so the glyph sits back — the '
            'other two are quiet chrome for verbs, this one is a state',
      );
    });

    testWidgets('the tick wears the review\'s green only once it is up — and '
        'Compare keeps the page\'s ink', (tester) async {
      // Colour on this bar is what the pass HAS, never what it might do: the
      // tick sits in the page's own ink until the mark is made, and turns the
      // review's green on the frame it lands. Compare carries nothing either
      // way — a lens wears no colour.
      reviewWorkoutNotesNotifier.value = const {'s1': 'Left it alone'};
      addTearDown(() => reviewWorkoutNotesNotifier.value = const {});

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            onComparison: (_) {},
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(
        tester.widget<Icon>(find.byIcon(kNoteGlyph)).color,
        AppColors.success,
        reason: 'a workout the pass holds a note for brightens — in green',
      );
      expect(
        tester.widget<Icon>(find.byIcon(kDoneGlyph)).color,
        AppColors.primary,
        reason: 'unticked, the tick is an ordinary control: the answer has not '
            'been given, so the colour is not on it yet',
      );
      expect(
        tester.widget<Icon>(find.byIcon(kCompareGlyph)).color,
        AppColors.primary,
        reason: 'Compare is a lens, not an answer: it keeps the page\'s own '
            'ink — white on the dark theme — never the review\'s colours',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(
              activeSessionId: 's1',
              reviewed: {'s1': DateTime(2026, 10, 9)},
            ),
            onComparison: (_) {},
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(
        tester.widget<Icon>(find.byIcon(kDoneGlyph)).color,
        AppColors.success,
        reason: 'the mark made, the tick turns green — the one button that '
            'puts the colour on is the one that takes it off',
      );
    });

    testWidgets('names the record while it is up — the sets below are not the '
        'plan', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            onComparison: (_) {},
            comparing: true,
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(
        find.text('Previously'),
        findsOneWidget,
        reason: 'the flip is values only, so the label is what reads out that '
            'the record is on screen, not the plan',
      );
      expect(find.text('In Review'), findsNothing);
      expect(
        find.byIcon(kCompareGlyphOn),
        findsOneWidget,
        reason: 'and the button says the same thing as the words: filled while '
            'the record is up, so the toggle reads pressed',
      );
      expect(find.byIcon(kCompareGlyph), findsNothing);
    });

    testWidgets('locks the note and the tick while the record is up, and '
        'leaves the way back live', (tester) async {
      // The pass's claims are about the plan. A note written, or a workout
      // ticked, while the record is on screen would judge something the user
      // is not looking at — so both grey out with the flip. Compare itself
      // stays pressable: it is the way back to the plan, and the record must
      // not be a room with no door (2026-10-10).
      var doneCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            onComparison: (_) {},
            comparing: true,
            onSetDone: (_) async {
              doneCalls++;
            },
          ),
        ),
      );

      GlassButton buttonOf(IconData glyph) => tester.widget<GlassButton>(
        find.ancestor(
          of: find.byIcon(glyph),
          matching: find.byType(GlassButton),
        ),
      );

      expect(
        buttonOf(kNoteGlyph).disabled,
        isTrue,
        reason: 'the workout note is the pass\'s, and the pass is not what is '
            'on screen — the card below reads the RECORD\'s note instead',
      );
      expect(
        buttonOf(kDoneGlyph).disabled,
        isTrue,
        reason: 'the tick is the pass\'s verdict on the plan, and the plan is '
            'not what is up',
      );
      expect(
        buttonOf(kCompareGlyphOn).disabled,
        isFalse,
        reason: 'the eye is the way back — locking it would strand the user on '
            'the record',
      );

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();
      expect(
        doneCalls,
        0,
        reason: 'a locked tick is grey all the way through: no write behind it',
      );
    });
  });

  // ── The label's rise ─────────────────────────────────────────────────────
  //
  // The label is one line of text that swaps in place, and the swap is the
  // only thing on the bar that moves. It went wrong once: both lines ride one
  // AnimatedSwitcher, so whatever the tween says, the outgoing copy is on
  // screen for as long as the swap lasts — and every way of animating it (a
  // lone tween painting it through the incoming line, then a rig keeping the
  // pair a line apart) still showed two lines of a label that is one. Both
  // read as a stutter, not a rise. What is pinned here is the rule that ends
  // it: the replaced line is dropped outright, on the frame the swap starts,
  // and only the arriving line moves — up from below, fading in as it comes.
  group('the label\'s rise', () {
    testWidgets('the replaced line is gone the instant the swap starts, and '
        'the arriving one rises into its place', (tester) async {
      reviewSessionNotifier.value = session(sessionIds: const ['s1', 's2']);
      await pumpScaffold(
        tester,
        (context) => reviewChrome(
          context,
          settle: () async => true,
          child: const Text('page'),
        ),
      );

      // The landing's line, at rest — the line the swap measures against.
      final landing = tester.getRect(find.text('In Review · 0 of 2'));

      // A workout opens under the bar: the label swaps to the workout's own.
      reviewSessionNotifier.value = session(
        sessionIds: const ['s1', 's2'],
        activeSessionId: 's1',
        activeWorkoutName: 'Psycho 1',
      );
      await tester.pump();

      expect(
        find.text('In Review · 0 of 2'),
        findsNothing,
        reason: 'the replaced line does not exit — it is dropped on the frame '
            'the swap starts. A label that is one line of text cannot be two, '
            'and any exit at all is a second line for as long as it lasts',
      );

      // Walk the 180ms rise. The arriving line comes up from below its
      // resting line the whole way, and it is on its way in, not in place.
      for (var step = 0; step < 5; step++) {
        await tester.pump(const Duration(milliseconds: 30));

        final arriving = tester.getRect(find.text('In Review'));
        expect(
          arriving.top,
          greaterThanOrEqualTo(landing.top),
          reason: 'the arriving line rises into place from below and never '
              'overshoots the line it comes to rest on',
        );
        final opacity = tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('In Review'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;
        expect(
          opacity,
          inExclusiveRange(0, 1),
          reason: 'the line fades up as it rises — it is not simply there',
        );
        if (step == 2) {
          expect(
            arriving.top,
            greaterThan(landing.top + 1),
            reason: 'halfway through, the line has actually moved: it is '
                'rising, not stacked still',
          );
        }
      }

      // And it settles: one line, on the resting line.
      await tester.pumpAndSettle();
      final rested = tester.getRect(find.text('In Review'));
      expect(rested.top, landing.top);
      expect(rested.height, landing.height);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('In Review'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
        reason: 'at rest the line is fully there',
      );
    });
  });

  group('geometry', () {
    testWidgets('floats inside the screen edges, above the safe area', (
      tester,
    ) async {
      // Physical pixels on the view; logical ones in the assertions. 402×874
      // logical with a 34pt bottom inset is an iPhone-class viewport.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      await pumpScaffold(
        tester,
        (context) =>
            reviewChrome(context, settle: null, child: const SizedBox()),
      );

      final screenWidth = tester.view.physicalSize.width / 3;
      final screenHeight = tester.view.physicalSize.height / 3;
      final bar = tester.getRect(find.byType(FloatingBar));

      expect(bar.left, FloatingBar.sideMargin);
      expect(screenWidth - bar.right, FloatingBar.sideMargin);
      expect(bar.height, FloatingBar.barHeight);
      expect(bar.bottom, screenHeight - 34 - FloatingBar.floatGap);
    });

    testWidgets('tells the page under it how much room to leave', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      double? inset;
      await pumpScaffold(
        tester,
        (context) => reviewChrome(
          context,
          settle: null,
          child: Builder(
            builder: (inner) {
              inset = FloatingBarOverlay.contentInset(inner);
              return const SizedBox();
            },
          ),
        ),
      );

      // The whole strip the bar claims: its height, the gap it floats on, the
      // home indicator under it, and a base gap so content does not touch it.
      expect(
        inset,
        FloatingBar.barHeight +
            FloatingBar.floatGap +
            34 +
            AppSpacing.lg,
      );
    });

    testWidgets('a bar stacked above shares the floor — and widens the room '
        'the page leaves', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      double? inset;
      await pumpScaffold(
        tester,
        (context) => reviewChrome(
          context,
          settle: null,
          // What the editor stacks over the pass: its own counts, in a
          // second pill of the same container.
          aboveBar: const FloatingBar(child: SizedBox()),
          child: Builder(
            builder: (inner) {
              inset = FloatingBarOverlay.contentInset(inner);
              return const SizedBox();
            },
          ),
        ),
      );

      // One stack, so the page clears all of it: the counts' bar, the gap it
      // floats on, the review bar, its own gap, the home indicator, and the
      // base gap.
      expect(
        inset,
        FloatingBar.barHeight +
            FloatingBar.floatGap +
            FloatingBar.barHeight +
            FloatingBar.floatGap +
            34 +
            AppSpacing.lg,
      );

      // And the two bars really do stand as one stack: the same margins, one
      // gap apart — a second bar drifting off the first would read as a
      // separate thing hovering nearby.
      final above = tester.getRect(find.byType(FloatingBar).first);
      final bar = tester.getRect(find.byType(FloatingBar).last);
      expect(above.left, bar.left);
      expect(above.width, bar.width);
      expect(bar.top - above.bottom, FloatingBar.floatGap);
    });

    testWidgets('a bar can take a rim of its own — for a bar with something '
        'to say', (tester) async {
      // The rim is the floor's own faint cream unless a bar asks otherwise.
      // The editor's counts ask for the accent while they hold the record
      // rather than the plan: the border is the one thing on that screen
      // saying which of the two the numbers belong to.
      Color? rimOf() {
        for (final element in find
            .descendant(
              of: find.byType(FloatingBar),
              matching: find.byType(DecoratedBox),
            )
            .evaluate()) {
          final decoration = (element.widget as DecoratedBox).decoration;
          if (decoration is BoxDecoration && decoration.border != null) {
            return (decoration.border! as Border).top.color;
          }
        }
        return null;
      }

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: FloatingBar(child: SizedBox()))),
      );
      expect(
        rimOf(),
        floatingRim,
        reason: 'a bar with nothing to say wears the floor\'s own edge',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingBar(
              rimColor: AppColors.accent,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      expect(rimOf(), AppColors.accent);
    });

    testWidgets('answers zero where no bar paints over the page', (
      tester,
    ) async {
      // A page built under a bar answers for the bar; the same page opened
      // full-screen (Training Logs, say) must answer nothing, so one screen can
      // serve both without a flag.
      double? inset;
      await pumpScaffold(
        tester,
        (context) => Builder(
          builder: (inner) {
            inset = FloatingBarOverlay.contentInset(inner);
            return const SizedBox();
          },
        ),
      );
      expect(inset, 0);
    });
  });

  group('text on the bar', () {
    testWidgets('inherits the theme, not the debug error style', (
      tester,
    ) async {
      // The bar floats ABOVE the page, outside the Scaffold's own Material. A
      // Scaffold-less page is the regression's own shape, and it is what the
      // bar looked like before: MaterialApp's base text style is its error
      // style — red, monospaced, and underlined in double yellow — so the
      // label came out underlined.
      await tester.pumpWidget(
        ReviewScope(
          child: MaterialApp(
            home: ReviewBar(session: session()),
          ),
        ),
      );

      final style = DefaultTextStyle.of(
        tester.element(find.text('In Review · 0 of 1')),
      ).style;
      expect(
        style.decoration,
        isNot(TextDecoration.underline),
        reason: '"In Review" must not come out underlined',
      );
      expect(style.decorationColor, isNot(const Color(0xFFFFFF00)));
    });

    testWidgets('and the word still on it does too', (tester) async {
      // Finish is the bar's only word, now that the workout's verbs are
      // glyphs — and it stands under the same Material.
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(session: session(), onFinish: () async {}),
        ),
      );

      final style = DefaultTextStyle.of(
        tester.element(find.text('Finish')),
      ).style;
      expect(
        style.decoration,
        isNot(TextDecoration.underline),
        reason: '"Finish" must not come out underlined',
      );
    });
  });

  group('ReviewScope', () {
    testWidgets('publishes the session to everything below it', (tester) async {
      reviewSessionNotifier.value = session();
      ReviewSession? seen;
      await pumpScaffold(tester, (context) {
        seen = ReviewScope.maybeOf(context);
        return const SizedBox();
      });
      expect(seen?.reviewId, 'rev1');
    });

    testWidgets('reads as no review when there is no scope above', (
      tester,
    ) async {
      reviewSessionNotifier.value = session();
      ReviewSession? seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              seen = ReviewScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, isNull);
    });
  });

  group('Done', () {
    testWidgets(
      'settles the editor first, and aborts when it does not settle',
      (tester) async {
        reviewSessionNotifier.value = session(activeSessionId: 's1');
        final gate = Completer<bool>();
        var settled = 0;

        await pumpScaffold(
          tester,
          (context) => reviewChrome(
            context,
            settle: () {
              settled++;
              return gate.future;
            },
            child: const Text('editor'),
          ),
        );

        await tester.tap(find.byIcon(kDoneGlyph));
        await tester.pump();

        // Settle is asked FIRST. Done means "finished with this one", and a
        // tick over unsaved edits would say that about a change that never
        // landed — so the row is not written until the editor has saved.
        expect(settled, 1);
        expect(
          reviewSessionNotifier.value?.reviewed,
          isEmpty,
          reason: 'no tick is recorded while the save is in the air',
        );

        // The save failed. The user stays in the workout, untick still set,
        // and the review is still running.
        gate.complete(false);
        await tester.pumpAndSettle();
        expect(find.text('editor'), findsOneWidget);
        expect(reviewSessionNotifier.value?.activeSessionId, 's1');
        expect(reviewSessionNotifier.value?.reviewed, isEmpty);
      },
    );

    testWidgets('stays on the review route when the settle is refused', (
      tester,
    ) async {
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      bool? finished;
      final result = await pumpReviewRoute(
        tester,
        (context) => reviewChrome(
          context,
          settle: () async => false,
          child: const Text('editor'),
        ),
      );
      // Recorded rather than awaited, so a regression fails on an assertion
      // instead of hanging the test on a future that never resolves.
      result.then((value) => finished = value);

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();

      expect(find.text('editor'), findsOneWidget);
      expect(find.text('base page'), findsNothing);
      expect(finished, isNull);
      expect(reviewSessionNotifier.value?.reviewId, 'rev1');
    });

    testWidgets('the landed tick is answered on the bar, and the workout '
        'stays put', (tester) async {
      final recorded = session(activeSessionId: 's1');
      reviewSessionNotifier.value = recorded;

      var left = false;
      final result = await pumpReviewRoute(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            // Read live, like reviewChrome reads it: setting the tick replaces
            // the session, and the bar has to survive being handed the new one.
            session: ReviewScope.maybeOf(context)!,
            onComparison: (_) {},
            onSetDone: (done) async {
              // What the real write does on its way through: the map moves and
              // the open workout stays exactly where it is — the tick is a
              // state of this workout, not a way out of it.
              reviewSessionNotifier.value = recorded.copyWith(
                reviewed: {...recorded.reviewed, 's1': DateTime(2026, 10, 9)},
              );
            },
          ),
        ),
      );
      result.then((_) => left = true);

      expect(find.text('In Review'), findsOneWidget);

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text(kReviewCompleteLabel),
        findsOneWidget,
        reason: 'the tick\'s answer replaces whatever the label was saying',
      );
      expect(find.text('In Review'), findsNothing);
      expect(
        reviewSessionNotifier.value?.activeSessionId,
        's1',
        reason: 'the workout stays open: the tick is read back off the session '
            'the bar is showing, so clearing it would take the answer away',
      );
      expect(
        find.byIcon(kCompareGlyph),
        findsOneWidget,
        reason: 'the bar keeps the workout it just finished: the workout is '
            'still the page under the bar, and a bar shedding its verbs from '
            'under the words answering them would read as the screen falling '
            'apart at the moment it says done',
      );
      expect(
        tester.widget<FloatingBar>(find.byType(FloatingBar)).rimColor,
        AppColors.success,
        reason: 'the floor turns green with the words: done is one colour in '
            'this app, and the bar says it in both places at once',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(
        find.text('base page'),
        findsNothing,
        reason: 'the answer is the bar staying, not the route going — nothing '
            'is waiting to take the workout down behind it',
      );
      expect(left, isFalse);
      expect(find.text(kReviewCompleteLabel), findsOneWidget);

      // And the record never speaks over the answer: raising the eye on a
      // workout already ticked keeps 'Review Complete' — the tick is a fact
      // about this workout, where 'Previously' is only what is on screen. The
      // flip is set up rather than tapped, because the tick's own button is
      // locked once the record is up (see the earlier lock test).
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(
              activeSessionId: 's1',
              reviewed: {'s1': DateTime(2026, 10, 9)},
            ),
            onComparison: (_) {},
            comparing: true,
            onSetDone: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(kReviewCompleteLabel),
        findsOneWidget,
        reason: 'the answer outranks the record: flipping to it does not '
            'retract a tick that already landed',
      );
      expect(find.text('Previously'), findsNothing);
    });

    testWidgets('the tick is a toggle: the same button takes it back off, and '
        'the bar returns to the pass\'s words', (tester) async {
      final workout = session(activeSessionId: 's1');
      reviewSessionNotifier.value = workout;
      var flips = <bool>[];

      await tester.pumpWidget(
        ReviewScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ReviewBar(
                  // Read live, like reviewChrome reads it — the flip comes back
                  // through the session, not through the button.
                  session: ReviewScope.maybeOf(context)!,
                  onSetDone: (done) async {
                    flips.add(done);
                    final reviewed = Map<String, DateTime>.of(
                      reviewSessionNotifier.value!.reviewed,
                    );
                    if (done) {
                      reviewed['s1'] = DateTime(2026, 10, 9);
                    } else {
                      reviewed.remove('s1');
                    }
                    reviewSessionNotifier.value = workout.copyWith(
                      reviewed: reviewed,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Marked by mistake: the same glyph, pressed again, unmakes it — the
      // label returns to the pass's own words and the floor gives up the
      // green, so the bar stops claiming a tick the record no longer has.
      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();
      expect(flips, [true]);
      expect(find.text(kReviewCompleteLabel), findsOneWidget);

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();
      expect(flips, [true, false]);
      expect(
        find.text(kReviewCompleteLabel),
        findsNothing,
        reason: 'the bar says what the record says — and the record no longer '
            'has this workout marked',
      );
      expect(find.text('In Review'), findsOneWidget);
      expect(
        tester.widget<FloatingBar>(find.byType(FloatingBar)).rimColor,
        isNull,
        reason: 'the green goes back with the words',
      );
    });

    testWidgets('a tick that did not land leaves the bar as it was', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            onSetDone: (_) async {
              presses++;
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();

      expect(presses, 1);
      expect(find.text('In Review'), findsOneWidget);
      expect(
        find.text(kReviewCompleteLabel),
        findsNothing,
        reason: 'the bar only says done when done landed',
      );
      expect(
        tester.widget<FloatingBar>(find.byType(FloatingBar)).rimColor,
        isNull,
        reason: 'and it does not keep the green for a press that did nothing',
      );

      // And pressable again: a failed save keeps the user in the workout.
      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();
      expect(presses, 2);
    });
  });

  group('Finish', () {
    testWidgets('runs the landing\'s finish when pressed', (tester) async {
      var finishes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(sessionIds: const ['s1', 's2']),
            onFinish: () async => finishes++,
          ),
        ),
      );

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(finishes, 1);
    });

    testWidgets('a partial pass is asked about once — unticked work does not '
        'block a finish, but it is not passed over in silence', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  answer = await confirmPartialFinish(
                    context,
                    reviewed: 1,
                    total: 3,
                  );
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 3 reviewed'), findsOneWidget);
      expect(
        find.textContaining('saved with the review as they stand'),
        findsOneWidget,
        reason: 'the question says what happens to the unticked workouts — '
            'they are recorded as they are, not dropped',
      );

      await tester.tap(find.text('Keep reviewing'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('and "finish anyway" really does go on', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  answer = await confirmPartialFinish(
                    context,
                    reviewed: 1,
                    total: 3,
                  );
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish anyway'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });

  group('Compare', () {
    testWidgets('is hidden when nothing can show a comparison', (tester) async {
      // Compare needs a surface that can hold the record — the workout editor
      // that flips its sets for it. A bar with nothing behind it does not
      // offer the verb: loading a comparison no one can show would be a
      // button that does nothing.
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewBar(
            session: session(activeSessionId: 's1'),
            onSetDone: (_) async {},
          ),
        ),
      );

      expect(find.byIcon(kCompareGlyph), findsNothing);
      expect(
        find.byIcon(kDoneGlyph),
        findsOneWidget,
        reason: 'the two callbacks are wired separately — dropping '
            'onComparison must not take Done with it',
      );
    });

    testWidgets('settles the editor, loads, then hands the record over — '
        'no sheet', (tester) async {
      final order = <String>[];
      var loads = 0;
      ReviewComparison? shown;

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async {
              order.add('settle');
              return true;
            },
            loadComparison: () async {
              loads++;
              order.add('load');
              return ReviewComparison(
                before: _content('60'),
                after: _content('70'),
                exerciseNames: const {},
              );
            },
            onComparison: (comparison) => shown = comparison,
          ),
        ),
      );

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      // Settle FIRST, and silently: the comparison reads saved state, so an
      // edit still sitting in a form field would read as a change that never
      // happened — and comparing changes nothing, so it may not put a dialog
      // in the user's way either.
      expect(order, ['settle', 'load']);
      expect(loads, 1);

      expect(
        shown?.before?.sessions.single.name,
        'Push Day',
        reason: 'the surface that can show the record is handed it — the '
            'editor flips its own sets rather than opening something over them',
      );
      expect(
        find.text(kReviewChangesTitle),
        findsNothing,
        reason: 'the diff sheet is off: the comparison renders IN the editor, '
            'not over it',
      );
    });

    testWidgets('aborts when the editor will not settle', (tester) async {
      var loads = 0;
      ReviewComparison? shown;

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => false,
            loadComparison: () async {
              loads++;
              return ReviewComparison(
                before: _content('60'),
                after: _content('70'),
                exerciseNames: const {},
              );
            },
            onComparison: (comparison) => shown = comparison,
          ),
        ),
      );

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      // The save failed. Nothing on screen moves: a record shown against
      // state the user cannot see would describe a plan that does not exist.
      expect(loads, 0);
      expect(shown, isNull);
      expect(find.text('In Review'), findsOneWidget);
    });

    testWidgets('says so when the comparison cannot be read', (
      tester,
    ) async {
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => throw StateError('offline'),
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not compare'), findsOneWidget);
      // Still reviewing: a read that failed is not a reason to lose the pass.
      expect(find.text('In Review'), findsOneWidget);
    });

    testWidgets('tapping Compare again leaves the record without reading it '
        'again', (tester) async {
      var loads = 0;
      var settles = 0;
      // Seeded non-null: the assertion below has to prove the callback flipped
      // it, not that it was never called.
      ReviewComparison? shown = ReviewComparison(
        before: _content('60'),
        after: _content('70'),
        exerciseNames: const {},
      );

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            comparing: true,
            settleForCompare: () async {
              settles++;
              return true;
            },
            loadComparison: () async {
              loads++;
              return ReviewComparison(
                before: _content('60'),
                after: _content('70'),
                exerciseNames: const {},
              );
            },
            onComparison: (comparison) => shown = comparison,
          ),
        ),
      );

      await tester.tap(find.byIcon(kCompareGlyphOn));
      await tester.pumpAndSettle();

      expect(shown, isNull, reason: 'null is the flip back to the plan');
      expect(
        loads,
        0,
        reason: 'the editor already holds the record — leaving it is not a '
            'second read',
      );
      expect(
        settles,
        0,
        reason: 'and there is nothing to settle on the way back either',
      );
    });

    testWidgets('says so when nothing was recorded, instead of showing the '
        'plan back', (tester) async {
      ReviewComparison? shown;

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => ReviewComparison(
              before: null,
              after: _content('70'),
              exerciseNames: const {},
            ),
            onComparison: (comparison) => shown = comparison,
          ),
        ),
      );

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      expect(find.text(kNoEarlierVersionNote), findsOneWidget);
      expect(
        shown,
        isNull,
        reason: 'flipping to nothing would show the plan back under a heading '
            'claiming it is the record — worse than saying there is none',
      );
    });
  });

  group('Changes', () {
    ReviewComparison stubComparison() => ReviewComparison(
      before: _content('60'),
      after: _content('70'),
      exerciseNames: const {},
    );

    testWidgets('is offered wherever a workout is open — no surface required', (
      tester,
    ) async {
      // Compare needs an editor that can flip for it; the changes sheet
      // carries itself, so this button is up even with no onComparison at all.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewBar(
              session: session(activeSessionId: 's1'),
              onSetDone: (_) async {},
            ),
          ),
        ),
      );

      expect(find.byIcon(kChangesGlyph), findsOneWidget);
      expect(
        find.byIcon(kCompareGlyph),
        findsNothing,
        reason: 'and the two gates really are separate — this is the same bar '
            'that dropped Compare',
      );
    });

    testWidgets('is off the landing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewBar(session: session(), onFinish: () async {}),
          ),
        ),
      );

      expect(find.text('Finish'), findsOneWidget);
      expect(
        find.byIcon(kChangesGlyph),
        findsNothing,
        reason: 'the landing is the pass, not one workout — there is nothing '
            'on screen for the sheet to describe',
      );
    });

    testWidgets('sits between Compare and Note', (tester) async {
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => stubComparison(),
            onComparison: (_) {},
            onSetDone: (_) async {},
          ),
        ),
      );

      final compare = tester.getCenter(find.byIcon(kCompareGlyph)).dx;
      final changes = tester.getCenter(find.byIcon(kChangesGlyph)).dx;
      final note = tester.getCenter(find.byIcon(kNoteGlyph)).dx;

      expect(compare, lessThan(changes));
      expect(
        changes,
        lessThan(note),
        reason: 'the lens pair reads together — showing the record, then '
            'telling it — with the note and its claim further along',
      );
    });

    testWidgets('settles, loads, then opens the sheet — never flips the '
        'editor', (tester) async {
      final order = <String>[];
      final flips = <ReviewComparison?>[];

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async {
              order.add('settle');
              return true;
            },
            loadComparison: () async {
              order.add('load');
              return stubComparison();
            },
            onComparison: (comparison) => flips.add(comparison),
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      // Same discipline as Compare — settle first, silently — but the record
      // goes to a sheet, not into the editor: what is underneath must keep
      // showing the plan.
      expect(order, ['settle', 'load']);
      expect(find.text(kReviewChangesTitle), findsOneWidget);
      expect(
        flips,
        isEmpty,
        reason: 'a flip here would put the record in the editor behind a '
            'sheet that is describing the current state',
      );
    });

    testWidgets('flips back to the current first when the record is up', (
      tester,
    ) async {
      final order = <String>[];
      final flips = <ReviewComparison?>[];

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            comparing: true,
            settleForCompare: () async {
              order.add('settle');
              return true;
            },
            loadComparison: () async {
              order.add('load');
              return stubComparison();
            },
            onComparison: (comparison) => flips.add(comparison),
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      expect(
        flips,
        [null],
        reason: 'the sheet always answers new vs old, so the screen must be '
            'back on the current before it opens',
      );
      expect(order, ['settle', 'load']);
      expect(find.text(kReviewChangesTitle), findsOneWidget);
    });

    testWidgets('a settle that fails aborts silently', (tester) async {
      var loads = 0;

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => false,
            loadComparison: () async {
              loads++;
              return stubComparison();
            },
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      expect(loads, 0);
      expect(find.text(kReviewChangesTitle), findsNothing);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'the save failed and said so itself; the bar does not add a '
            'second voice to it',
      );
    });

    testWidgets('opens on "no earlier version" rather than saying it in a '
        'SnackBar', (tester) async {
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => ReviewComparison(
              before: null,
              after: _content('70'),
              exerciseNames: const {},
            ),
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      // Unlike Compare — which has nothing to show and says so in passing —
      // the absence is a state the sheet explains, so the sheet still opens.
      expect(find.text(kReviewChangesTitle), findsOneWidget);
      expect(find.text(kNoEarlierVersionNote), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a record that holds none of this workout reads as none', (
      tester,
    ) async {
      // The load resolved, but to a document with no sessions in scope for
      // this workout — a record of something else. Compare's own rule: that is
      // no earlier version, not a diff against unrelated contents.
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => ReviewComparison(
              before: ProgramContent(sessions: const []),
              after: _content('70'),
              exerciseNames: const {},
            ),
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      // No header names a "before" side any more: the sheet answers inside
      // ONE workout, so the absence is said in the sheet's own words.
      expect(find.text(kReviewChangesTitle), findsOneWidget);
      expect(find.text(kNoEarlierVersionNote), findsOneWidget);
    });

    testWidgets('an exercise card in the sheet opens the exercise it names', (
      tester,
    ) async {
      // The sheet's cards are how the editor below is reached: the bar hands
      // the tap verb down, the card closes the sheet and names the exercise
      // group it stands for.
      String? opened;

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => stubComparison(),
            onComparison: (_) {},
            onExerciseTap: (id) => opened = id,
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      // The stub's one exercise has no id→name map, so the card reads the
      // generic noun the diff itself falls back to.
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();

      expect(opened, 'e1');
      expect(find.text(kReviewChangesTitle), findsNothing);
    });

    testWidgets('with no editor under the bar the cards stay inert', (
      tester,
    ) async {
      // A bar can be built with nothing able to open an exercise — the
      // history panel's sheet, a harness — and the card then reads without
      // promising anywhere to go: no rung, no tap verb.
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => stubComparison(),
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      expect(find.text('Exercise'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('says so when the changes cannot be read', (tester) async {
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: ReviewBar(
            session: session(activeSessionId: 's1'),
            settleForCompare: () async => true,
            loadComparison: () async => throw StateError('offline'),
            onComparison: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not read the changes'), findsOneWidget);
      // Still reviewing: a read that failed is not a reason to lose the pass.
      expect(find.text('In Review'), findsOneWidget);
    });

    testWidgets('all four glyphs leave the label its whole line', (
      tester,
    ) async {
      // The one width that matters: the label is the whole signal that the
      // record is up, and an ellipsis would eat it. Measured at the real
      // surface (402pt), through the overlay's own gutters, with the full
      // four-glyph row up — the shape the bar was tightened for.
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      reviewSessionNotifier.value = session(activeSessionId: 's1');
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FloatingBar.sideMargin,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ReviewBar(
                session: session(activeSessionId: 's1'),
                comparing: true,
                settleForCompare: () async => true,
                loadComparison: () async => stubComparison(),
                onComparison: (_) {},
                onSetDone: (_) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Previously'), findsOneWidget);
      // Measured, not remembered: 'Review Complete' is the longest line this
      // bar can wear, and a slot that holds it holds the record's word too.
      expect(
        tester.getSize(find.byType(AnimatedSwitcher)).width,
        greaterThanOrEqualTo(_labelLineWidth(kReviewCompleteLabel)),
        reason: 'the label slot is what four 48pt glyphs leave of the bar — '
            'the longest line must fit whole, or the state is up with nothing '
            'saying so',
      );
      expect(
        tester.getCenter(find.text('Previously')).dx,
        tester.getCenter(find.byType(AnimatedSwitcher)).dx,
        reason: 'the line sits centred in the room the glyphs leave it: a '
            'line pinned to the slot\'s left edge reads as a bar with a gap, '
            'not a bar with a label',
      );
      // And the room is the one the eye can see: rim to first glyph, with no
      // padded inset on the label's side. A hidden inset would leave the
      // words off-centre by exactly its width — invisible on a short line,
      // plain on a long one like 'Review Complete'.
      final bar = tester.getRect(find.byType(FloatingBar));
      final label = tester.getRect(find.text('Previously'));
      final eye = tester.getRect(find.byType(GlassButton).first);
      expect(
        ((label.left - bar.left) - (eye.left - label.right)).abs(),
        lessThan(2),
        reason: 'the gaps it leaves on either side must read the same, or the '
            'bar looks like it lost the label\'s place',
      );
      // The glyph row above is the shape the plan tightens: this fails the
      // day a fifth control arrives without the label being re-measured.
      expect(find.byIcon(kCompareGlyphOn), findsOneWidget);
      expect(find.byIcon(kChangesGlyph), findsOneWidget);
      expect(find.byIcon(kNoteGlyph), findsOneWidget);
      expect(find.byIcon(kDoneGlyph), findsOneWidget);
    });
  });

  // ── The record ────────────────────────────────────────────────────────────
  //
  // A completed review opened from the list is the landing its pass had, read
  // once the walk is over: the same cards, the same ticks, the same tabs —
  // every way of writing taken away, and Summary added. It is deliberately
  // not a pass: nothing is published to reviewSessionNotifier, so a pass
  // running elsewhere survives a record opened and popped over it, and the
  // bar says [kReviewCompleteLabel] because the walk is over, not because a
  // tick landed under it.
  group('a record', () {
    late FakePlannedSessions planned;
    late FakeProgramRepository programs;
    late FakeExercises exercises;
    late FakeProgramHistoryRepository history;

    setUp(() {
      planned = FakePlannedSessions();
      programs = FakeProgramRepository();
      exercises = FakeExercises();
      history = FakeProgramHistoryRepository();
    });

    /// One workout and one goal, resolvable — the smallest complete pass.
    void seed() {
      planned.byId = {
        's1': const PlannedSession(
          sessionId: 's1',
          userId: 'u1',
          name: 'Push Day',
        ),
      };
      programs.goals = [
        const Goal(
          goalId: 'g1',
          userId: 'u1',
          exerciseId: 'e1',
          description: 'Beltless, pause on the chest',
          targetWeight: 100,
          targetReps: 5,
        ),
      ];
      exercises.details = {
        'e1': const ExerciseDetail(
          exercise: CustomExercise(
            exerciseId: 'e1',
            userId: 'u1',
            name: 'Bench Press',
          ),
        ),
      };
      // What the reader resolves its nouns from — the record stores ids.
      exercises.exerciseNames = {'e1': 'Bench Press', 'e2': 'Row', 'e3': 'Curl'};
    }

    ReviewSession recordSession({
      String title = 'End of block',
      List<String> sessionIds = const ['s1'],
      List<String> goalIds = const ['g1'],
      Map<String, DateTime> reviewed = const {},
    }) => ReviewSession(
      reviewId: 'rec1',
      programId: null,
      sessionIds: sessionIds,
      goalIds: goalIds,
      reviewed: reviewed,
      title: title,
    );

    /// The record's stack: a base page with the record route — named
    /// [kReviewRouteNameRecord], the name [openCompletedReview] pushes — over
    /// it. The stores are injected, which is what makes a host test possible
    /// at all: there is no database under this one.
    Future<Future<bool?>> pumpRecord(
      WidgetTester tester, {
      required ReviewSession subject,
    }) async {
      late BuildContext root;
      await tester.pumpWidget(
        ReviewScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                root = context;
                return const Scaffold(body: Text('base page'));
              },
            ),
          ),
        ),
      );
      final result = Navigator.of(root, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          settings: const RouteSettings(name: kReviewRouteNameRecord),
          builder: (_) => ReviewRoute(
            session: subject,
            readOnly: true,
            userId: 'u1',
            plannedRepository: planned,
            programRepository: programs,
            exerciseRepository: exercises,
            historyRepository: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return result;
    }

    /// The completed row a record reads through: one workout, plus whatever
    /// the review said about it. The snapshot is the whole document the reader
    /// is narrowed against — a second workout in it would be another card on
    /// the landing, not another page in this one.
    ///
    /// Both sides are on the row, and they hold different values on purpose
    /// (70 before, 80 after): the eye's whole job is that the two are drawn by
    /// the same card and read differently, which a row with one side could not
    /// tell apart from a broken flip.
    /// An exercise one side holds alone, with a set of its own — the sides'
    /// disagreement, which is what the eye's marks are read off.
    ContentExercise solo(String id, int order) => ContentExercise(
      plannedExerciseId: 'pe-$id',
      plannedSessionId: 's1',
      userId: 'u1',
      exerciseId: id,
      exerciseOrder: order,
      sets: [
        ContentSet(
          plannedSetId: 'ps-$id',
          plannedExerciseId: 'pe-$id',
          plannedSessionId: 's1',
          userId: 'u1',
          setNumber: 1,
          targetWeight: '40',
          targetReps: '10',
        ),
      ],
    );

    ProgramReview completedRow({
      String? exerciseNote,
      String? workoutNote,
      bool reviewed = false,
      bool withSnapshot = true,
      bool withBaseline = true,
      bool withExercises = true,
      bool withBeforeExercises = true,
      bool secondExercise = false,
      // An exercise the snapshot holds and the baseline does not — what the
      // review ADDED; and one the baseline held and the snapshot does not —
      // what it DROPPED. Both are read off the other side, never stored.
      String? addedAfter,
      String? droppedAfter,
    }) {
      ContentSession side(
        String weight,
        bool exercises, {
        List<ContentExercise> extra = const [],
      }) => ContentSession(
        sessionId: 's1',
        userId: 'u1',
        name: 'Push Day',
        exercises: exercises
            ? [
                ContentExercise(
                  plannedExerciseId: 'pe1',
                  plannedSessionId: 's1',
                  userId: 'u1',
                  exerciseId: 'e1',
                  exerciseOrder: 0,
                  sets: [
                    ContentSet(
                      plannedSetId: 'ps1',
                      plannedExerciseId: 'pe1',
                      plannedSessionId: 's1',
                      userId: 'u1',
                      setNumber: 1,
                      targetWeight: weight,
                      targetReps: '5',
                    ),
                  ],
                ),
                // The exercise the two sides agree on — held still across the
                // review, so a diff has something to call unchanged.
                if (secondExercise)
                  const ContentExercise(
                    plannedExerciseId: 'pe2',
                    plannedSessionId: 's1',
                    userId: 'u1',
                    exerciseId: 'e2',
                    exerciseOrder: 1,
                    sets: [
                      ContentSet(
                        plannedSetId: 'ps2',
                        plannedExerciseId: 'pe2',
                        plannedSessionId: 's1',
                        userId: 'u1',
                        setNumber: 1,
                        targetWeight: '60',
                        targetReps: '8',
                      ),
                    ],
                  ),
                ...extra,
              ]
            : const [],
      );
      final snapshot = ProgramContent(
        sessions: [
          side(
            '80',
            withExercises,
            extra: [if (addedAfter != null) solo(addedAfter, 2)],
          ),
        ],
      );
      final baseline = ProgramContent(
        sessions: [
          side(
            '70',
            withBeforeExercises,
            extra: [if (droppedAfter != null) solo(droppedAfter, 2)],
          ),
        ],
      );
      return ProgramReview(
        reviewId: 'rec1',
        userId: 'u1',
        sessionIdsJson: jsonEncode(const ['s1']),
        goalIdsJson: jsonEncode(const ['g1']),
        kind: kReviewKindReview,
        title: 'End of block',
        createdDate: DateTime(2026, 10, 1),
        completedDate: DateTime(2026, 10, 9),
        outcome: kOutcomeReviewed,
        // The ticks as the pass recorded them — what the reader's bar reads
        // the workout's answer off, the way the landing's does.
        reviewedSessionsJson: jsonEncode(
          reviewed ? {'s1': DateTime(2026, 10, 9).toIso8601String()} : {},
        ),
        snapshotContent: withSnapshot ? snapshot.encode() : null,
        baselineContent: withBaseline ? baseline.encode() : null,
        exerciseNotesJson: exerciseNote == null
            ? null
            : jsonEncode({'pe1': exerciseNote}),
        workoutNotesJson: workoutNote == null
            ? null
            : jsonEncode({'s1': workoutNote}),
      );
    }

    testWidgets('lands on the same page the pass had, with every way of '
        'writing gone', (tester) async {
      seed();
      await pumpRecord(
        tester,
        subject: recordSession(reviewed: {'s1': DateTime(2026, 10, 9)}),
      );

      expect(find.text('End of block'), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Push Day'), findsOneWidget);
      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
        reason: 'the tick is the record of what the pass walked, kept whole',
      );

      // The bar says the walk is over without counting: a record is settled
      // by what it is, and no tick is under it to read.
      expect(find.text(kReviewCompleteLabel), findsOneWidget);
      expect(find.textContaining('In Review'), findsNothing);
      expect(
        find.text('Finish'),
        findsNothing,
        reason: 'Finish writes the completion, and this one is written',
      );
      expect(
        find.byType(SwipeActions),
        findsNothing,
        reason: 'the swipe takes a workout out of the pass, and the pass is '
            'over',
      );
      expect(
        find.byIcon(Icons.add),
        findsNothing,
        reason: 'the add tiles put more in the set, and the set is what it was',
      );
    });

    testWidgets('Summary is the record\'s third tab, an empty state for now', (
      tester,
    ) async {
      seed();
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet.'), findsOneWidget);
      expect(
        find.text('Push Day'),
        findsNothing,
        reason: 'the tabs switch — one list at a time',
      );
    });

    testWidgets('a record over workouts alone reads Workouts | Summary', (
      tester,
    ) async {
      seed();
      await pumpRecord(tester, subject: recordSession(goalIds: const []));

      expect(find.text('Workouts'), findsOneWidget);
      expect(
        find.text('Goals'),
        findsNothing,
        reason: 'no goals were picked, so the strip makes no claim about them',
      );
      expect(find.text('Summary'), findsOneWidget);
    });

    testWidgets('a workout card opens the workout as the record has it, and '
        'the review\'s notes read back on it', (tester) async {
      seed();
      history.reviews = [
        completedRow(
          exerciseNote: 'Elbows tucked',
          workoutNote: 'Moved well today',
        ),
      ];
      await pumpRecord(
        tester,
        subject: recordSession(reviewed: {'s1': DateTime(2026, 10, 9)}),
      );

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(find.byType(RecordWorkoutScreen), findsOneWidget);
      // The side this opens on, named on the page: the review's completion.
      expect(find.text('AFTER · 9 Oct 2026'), findsOneWidget);
      expect(find.text('BEFORE · 1 Oct 2026'), findsNothing);
      // The two altitudes of note, each where its owner is: the workout's
      // above the card, the exercise's under the exercise it is about.
      expect(find.text('Moved well today'), findsOneWidget);
      expect(find.text('Elbows tucked'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      // The set the snapshot holds, drawn by the shared row — read only, so a
      // tap on it cannot open anything and the add row was never drawn.
      expect(find.text('80'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('+ ADD SET'), findsNothing);
      expect(
        tester.widget<SessionSetRow>(find.byType(SessionSetRow)).readOnly,
        isTrue,
      );
    });

    testWidgets('an exercise the review left no note for still holds the box '
        '— the pass draws one, and the record answers the emptiness inside '
        'it', (tester) async {
      seed();
      history.reviews = [completedRow()];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(
        find.text(kReviewNoteLabel),
        findsOneWidget,
        reason: 'the box is furniture on the card the pass drew, so it is '
            'here whether or not the review typed into it',
      );
      expect(
        find.text(kNoNoteText),
        findsOneWidget,
        reason: 'and the absence is said inside the box, not by dropping it',
      );
      expect(find.byType(LambdaReadout), findsOneWidget);
      expect(
        find.byType(LambdaInput),
        findsNothing,
        reason: 'a record reads back, so the box is never a field',
      );
    });

    testWidgets('the eye flips the workout between the two sides the review '
        'left behind — before it began, and as it completed', (tester) async {
      seed();
      history.reviews = [
        completedRow(
          exerciseNote: 'Elbows tucked',
          reviewed: true,
        ),
      ];
      await pumpRecord(
        tester,
        subject: recordSession(reviewed: {'s1': DateTime(2026, 10, 9)}),
      );

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(find.text('80'), findsOneWidget);
      expect(find.text('70'), findsNothing);
      // The bar names the side on screen the way the page caption does: a
      // record's two documents are both frozen, so the label is which one is
      // being read rather than how far a walk has got.
      expect(
        find.text(kReviewAfterLabel),
        findsOneWidget,
        reason: 'the side it opens on is the one the review produced',
      );
      // Green is the completed pass's own colour, and a record opens wearing
      // it: the written-down answer, rim and words together.
      expect(
        tester.widget<Text>(find.text(kReviewAfterLabel)).style?.color,
        AppColors.success,
      );
      expect(
        tester.widget<FloatingBar>(find.byType(FloatingBar)).rimColor,
        AppColors.success,
      );

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      expect(
        find.text('BEFORE · 1 Oct 2026'),
        findsOneWidget,
        reason: 'the side on screen is named on the page and on the bar, '
            'which flip together',
      );
      expect(
        find.text(kReviewBeforeLabel),
        findsOneWidget,
        reason: 'the label swaps to the side the eye turned to',
      );
      expect(find.text(kReviewAfterLabel), findsNothing);
      // The earlier side is not the answer, it is a reading — so the colours
      // move to the reader's own accent, floor and words as one.
      expect(
        tester.widget<Text>(find.text(kReviewBeforeLabel)).style?.color,
        AppColors.accent,
      );
      expect(
        tester.widget<FloatingBar>(find.byType(FloatingBar)).rimColor,
        AppColors.accent,
      );
      expect(find.text('AFTER · 9 Oct 2026'), findsNothing);
      expect(
        find.text('70'),
        findsOneWidget,
        reason: 'the same card, the same row, the other side\'s value',
      );
      expect(find.text('80'), findsNothing);
      expect(
        find.text('Elbows tucked'),
        findsOneWidget,
        reason: 'the review\'s note is about the exercise, so it reads over '
            'either side of it',
      );
      expect(
        find.byIcon(kCompareGlyphOn),
        findsOneWidget,
        reason: 'the toggle wears its state: filled while the earlier side is '
            'on screen',
      );

      await tester.tap(find.byIcon(kCompareGlyphOn));
      await tester.pumpAndSettle();

      expect(find.text('AFTER · 9 Oct 2026'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(
        find.text(kReviewAfterLabel),
        findsOneWidget,
        reason: 'the flip back names the side it returns to',
      );
    });

    testWidgets('the sides\' disagreement rides on the names — a green plus '
        'for what the review added, a red minus for what it dropped', (
      tester,
    ) async {
      seed();
      history.reviews = [completedRow(addedAfter: 'e2', droppedAfter: 'e3')];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      /// The glyph drawn beside [name] in the selector — the field's or a
      /// popover row's, whichever is holding it: the mark rides in the same
      /// [Row] as the name it is about, name first.
      Icon? markOf(String name) {
        Element? row;
        tester.element(find.text(name).first).visitAncestorElements((e) {
          if (e.widget is Row) {
            row = e;
            return false;
          }
          return true;
        });
        if (row == null) return null;
        Icon? icon;
        void visit(Element e) {
          if (icon != null) return;
          if (e.widget is Icon) {
            icon = e.widget as Icon;
            return;
          }
          e.visitChildren(visit);
        }

        row!.visitChildren(visit);
        return icon;
      }

      // The side it opens on is the record's own, and it holds the exercise
      // the baseline never had. The mark is the eye's reading of the OTHER
      // side, so it is asked for through the list — the field holds only the
      // open exercise.
      await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
      await tester.pumpAndSettle();

      expect(
        markOf('Row')?.icon,
        ExerciseMark.added.icon,
        reason: 'the snapshot holds what the baseline did not — added since it',
      );
      expect(
        markOf('Row')?.color,
        AppColors.success,
        reason: 'and a plus is green, the review\'s own word for more',
      );
      expect(
        markOf('Bench Press'),
        isNull,
        reason: 'both sides hold it: an edit neither made is not a mark',
      );
      // Back through the field, so the popover is not what is being read next.
      await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(kCompareGlyph));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
      await tester.pumpAndSettle();

      expect(
        markOf('Curl')?.icon,
        ExerciseMark.removed.icon,
        reason: 'the baseline held what the record does not — dropped since it',
      );
      expect(
        markOf('Curl')?.color,
        AppColors.danger,
        reason: 'and a minus is red, the review\'s own word for gone',
      );
      expect(
        find.text('Row'),
        findsNothing,
        reason: 'the added exercise is not on this side at all, so it wears '
            'nothing here — one membership test, two readings',
      );
      expect(markOf('Bench Press'), isNull);
    });

    testWidgets('a record with one side has nothing to read the names '
        'against, so no name is marked', (tester) async {
      seed();
      // No baseline on the row: the eye is not even offered, and a mark would
      // be a claim about a document the record does not hold.
      history.reviews = [completedRow(withBaseline: false, addedAfter: 'e2')];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      /// The glyph drawn beside [name] in the selector — the field's or a
      /// popover row's, whichever is holding it: the mark rides in the same
      /// [Row] as the name it is about, name first.
      Icon? markOf(String name) {
        Element? row;
        tester.element(find.text(name).first).visitAncestorElements((e) {
          if (e.widget is Row) {
            row = e;
            return false;
          }
          return true;
        });
        if (row == null) return null;
        Icon? icon;
        void visit(Element e) {
          if (icon != null) return;
          if (e.widget is Icon) {
            icon = e.widget as Icon;
            return;
          }
          e.visitChildren(visit);
        }

        row!.visitChildren(visit);
        return icon;
      }

      await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
      await tester.pumpAndSettle();

      expect(find.text('Row'), findsOneWidget, reason: 'it is still listed');
      expect(
        markOf('Row'),
        isNull,
        reason: 'and drawn without a mark, not with a guess — there is no '
            'second side to have read an edit off',
      );
    });

    testWidgets('a record with only one side offers no eye — a flip into '
        'nothing would read as data gone missing', (tester) async {
      seed();
      // A row written before baselines existed: the snapshot is all there is.
      history.reviews = [completedRow(withBaseline: false)];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(find.byIcon(kCompareGlyph), findsNothing);
      expect(find.byIcon(kCompareGlyphOn), findsNothing);
      expect(find.text('AFTER · 9 Oct 2026'), findsOneWidget);
    });

    testWidgets('the bar is the pass\'s own, with every verb that writes '
        'locked — the tick wearing the record\'s answer', (tester) async {
      seed();
      history.reviews = [completedRow(reviewed: true)];
      await pumpRecord(
        tester,
        subject: recordSession(reviewed: {'s1': DateTime(2026, 10, 9)}),
      );

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      GlassButton buttonOf(IconData glyph) => tester.widget<GlassButton>(
        find.ancestor(
          of: find.byIcon(glyph),
          matching: find.byType(GlassButton),
        ),
      );

      expect(
        find.text(kReviewAfterLabel),
        findsOneWidget,
        reason: 'the bar names the frozen side on screen, not a walk that '
            'has stopped',
      );
      expect(
        buttonOf(kDoneGlyph).color,
        AppColors.success,
        reason: 'the record says this one was Done, and the tick says so too',
      );
      expect(
        buttonOf(kDoneGlyph).disabled,
        isTrue,
        reason: 'green and greyed: the answer is written down, and nothing '
            'here can change it',
      );
      expect(
        buttonOf(kNoteGlyph).disabled,
        isTrue,
        reason: 'the note this writes is the plan\'s, and a record holds no '
            'plan to write to',
      );
      expect(
        find.text('Finish'),
        findsNothing,
        reason: 'a workout\'s bar never carries Finish, record or pass',
      );

      await tester.tap(find.byIcon(kDoneGlyph));
      await tester.pumpAndSettle();
      expect(
        find.text(kReviewAfterLabel),
        findsOneWidget,
        reason: 'a locked tick is grey all the way through — nothing moved',
      );
    });

    testWidgets('a workout the record does not tick carries an unlit tick, '
        'locked the same way', (tester) async {
      seed();
      history.reviews = [completedRow()];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      final tick = tester.widget<GlassButton>(
        find.ancestor(
          of: find.byIcon(kDoneGlyph),
          matching: find.byType(GlassButton),
        ),
      );
      expect(
        tick.color,
        isNot(AppColors.success),
        reason: 'the colour is the pass\'s word for the mark, and this '
            'workout never got one',
      );
      expect(tick.disabled, isTrue);
    });

    testWidgets('Changes reads the review\'s own two sides — what the pass '
        'did to this workout — and its cards land on the exercise', (
      tester,
    ) async {
      seed();
      history.reviews = [completedRow(secondExercise: true)];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(kChangesGlyph));
      await tester.pumpAndSettle();

      expect(find.text(kReviewChangesTitle), findsOneWidget);
      // The diff is the BASELINE against the SNAPSHOT: one exercise moved
      // (70 → 80) and one held still. Had either side been read off the plan,
      // the two would read the same and both cards would say no changes.
      expect(find.text('Changes made'), findsOneWidget);
      expect(find.text('No changes'), findsOneWidget);

      // The card for the exercise that held still opens it — the same promise
      // the pass's bar makes: this page is holding the workout.
      await tester.tap(find.text('No changes'));
      await tester.pumpAndSettle();
      expect(find.text(kReviewChangesTitle), findsNothing);
      expect(
        tester
            .widget<SessionExerciseCard>(find.byType(SessionExerciseCard))
            .activeIndex,
        1,
      );
    });

    testWidgets('a workout the review kept no record of says so, rather than '
        'drawing an empty grid', (tester) async {
      seed();
      // A completion dismissed with nothing to record: no snapshot on the row.
      history.reviews = [completedRow(withSnapshot: false)];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(
        find.text('This review kept no record of this workout.'),
        findsOneWidget,
      );
      expect(
        find.byType(SessionSetRow),
        findsNothing,
        reason: 'an empty grid would read as "no sets", which is a claim the '
            'row cannot make',
      );
    });

    testWidgets('a workout recorded empty says that, and draws no card', (
      tester,
    ) async {
      seed();
      history.reviews = [completedRow(withExercises: false)];
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();

      expect(
        find.text('This review recorded no exercises for this workout.'),
        findsOneWidget,
      );
    });

    testWidgets('a goal row opens the same sheet the pass opens — reading, '
        'never writing', (tester) async {
      seed();
      await pumpRecord(tester, subject: recordSession());

      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('100 kg × 5 reps'), findsOneWidget);

      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      // The sheet the pass opens, resting. No writer was wired, so every way
      // into edit mode is gone with it — the notes rest as a readout and the
      // box never comes.
      expect(find.byType(GoalRow), findsWidgets, reason: 'the sheet is up');
      expect(find.byType(LambdaInput), findsNothing);
      expect(find.text('Add a note…'), findsNothing);
      expect(
        find.byIcon(Icons.edit_outlined),
        findsNothing,
        reason: 'a record has no pencil — nothing to enter edit mode with',
      );

      // The readout is inert: tapping it cannot open a box that would write.
      await tester.tap(find.byType(LambdaReadout));
      await tester.pumpAndSettle();
      expect(find.byType(LambdaInput), findsNothing);
    });

    testWidgets('a record never adopts or clears a pass running elsewhere', (
      tester,
    ) async {
      seed();
      // A pass of a DIFFERENT review, live in the notifier — the shape the
      // guards exist for. The opener refuses this outright, so pushing the
      // route directly is what lets the build and dispose guards be exercised
      // at all.
      reviewSessionNotifier.value = session(
        reviewId: 'live1',
        sessionIds: const ['s9'],
        activeSessionId: 's9',
      );

      final left = await pumpRecord(tester, subject: recordSession());

      expect(
        find.text(kReviewCompleteLabel),
        findsOneWidget,
        reason: 'the bar is the record\'s own — it reads the session it was '
            'opened with, not whatever pass the notifier holds',
      );
      expect(find.text('In Review'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(
        reviewSessionNotifier.value?.reviewId,
        'live1',
        reason: 'the record\'s dispose never clears a session it did not set',
      );
      expect(reviewSessionNotifier.value?.activeSessionId, 's9');
      expect(await left, isFalse);
    });

    testWidgets('a record whose workouts are gone still has a way out — and '
        'no Finish', (tester) async {
      // Nothing seeded: every id in the set resolves to nothing.
      final left = await pumpRecord(
        tester,
        subject: recordSession(sessionIds: const ['s9']),
      );

      expect(
        find.text('The workouts in this review are no longer available.'),
        findsOneWidget,
      );
      expect(find.text(kReviewCompleteLabel), findsOneWidget);
      expect(
        find.text('Finish'),
        findsNothing,
        reason: 'Finish on a record would write a completion on top of one',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('base page'), findsOneWidget);
      expect(await left, isFalse);
    });

    testWidgets('the opener refuses while a pass is live, and says so', (
      tester,
    ) async {
      seed();
      reviewSessionNotifier.value = session(activeSessionId: 's1');
      late BuildContext ctx;
      await tester.pumpWidget(
        ReviewScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(body: Text('base page'));
              },
            ),
          ),
        ),
      );

      bool? opened;
      // Recorded rather than awaited: a regression must fail on an assertion,
      // not hang the test on a route's future.
      openCompletedReview(ctx, recordSession()).then((v) => opened = v);
      await tester.pumpAndSettle();

      expect(find.text('A review is already open.'), findsOneWidget);
      expect(
        find.byType(ReviewRoute),
        findsNothing,
        reason: 'the snackbar is the whole answer — nothing was pushed',
      );
      expect(opened, isNull);
      expect(find.text('base page'), findsOneWidget);
    });

    test('completedReviewSession is the row read back whole — the resolved '
        'set, the recorded ticks, nothing invented', () {
      final legacy = ProgramReview(
        reviewId: 'rev-legacy',
        userId: 'u1',
        programId: 'prog1',
        blockId: 'b1',
        kind: kReviewKindReview,
        title: 'Old pass',
        completedDate: DateTime(2026, 10, 10),
        outcome: kOutcomeReviewed,
        // A row written before reviews carried a set: null here, and the
        // resolved set is the only truth it has.
        reviewedSessionsJson: jsonEncode({
          's1': DateTime(2026, 10, 9).toIso8601String(),
        }),
        createdDate: DateTime(2026, 1, 1),
      );

      final mapped = completedReviewSession(
        review: legacy,
        sessionIds: const ['s1', 's2'],
      );

      expect(mapped.reviewId, 'rev-legacy');
      expect(mapped.programId, 'prog1');
      expect(mapped.title, 'Old pass');
      expect(
        mapped.sessionIds,
        ['s1', 's2'],
        reason: 'the set the list resolved — the row stores none of its own',
      );
      expect(mapped.goalIds, isEmpty);
      expect(mapped.reviewed.keys, ['s1']);

      final withGoals = completedReviewSession(
        review: ProgramReview(
          reviewId: 'rev-new',
          userId: 'u1',
          kind: kReviewKindReview,
          goalIdsJson: jsonEncode(['g1', 'g2']),
          completedDate: DateTime(2026, 10, 10),
          outcome: kOutcomeReviewed,
          createdDate: DateTime(2026, 1, 1),
        ),
        sessionIds: const ['s1'],
      );

      expect(withGoals.goalIds, ['g1', 'g2']);
      expect(
        withGoals.programId,
        isNull,
        reason: 'standalone when the row is — the record keeps the row\'s own '
            'shape',
      );
    });
  });
}

Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

/// A bar label's own line width, painted with the real font — the width the
/// label slot has to hold whole. The labels are fixed strings, so a test
/// asking "does it fit?" should paint the string rather than remember a
/// number that moves every time the words do.
double _labelLineWidth(String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// One workout, one exercise, one set — enough for a comparison to have a real
/// line to say.
ProgramContent _content(String weight) => ProgramContent(
  sessions: [
    ContentSession(
      sessionId: 's1',
      userId: 'u1',
      name: 'Push Day',
      exercises: [
        ContentExercise(
          plannedExerciseId: 'e1',
          plannedSessionId: 's1',
          userId: 'u1',
          exerciseOrder: 1,
          sets: [
            ContentSet(
              plannedSetId: 'set1',
              plannedExerciseId: 'e1',
              plannedSessionId: 's1',
              userId: 'u1',
              setNumber: 1,
              targetWeight: weight,
              targetReps: '5',
            ),
          ],
        ),
      ],
    ),
  ],
);
