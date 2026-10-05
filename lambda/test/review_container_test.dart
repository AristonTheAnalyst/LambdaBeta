import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/core/styles/app_spacing.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/view/review_container.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The review ceremony's two load-bearing rules.
///
/// The container is deliberately quiet: it puts a bar up and otherwise gets out
/// of the way. Which means the ways it goes wrong are quiet too — a bar that
/// lingers on screens with no review, a `bottomNavigationBar` that exists when
/// it should not, or a Finish that snapshots the plan WITHOUT the edits the
/// user just spent the review making. Every one of those is invisible in a
/// screenshot and obvious here.
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

  ReviewSession session({ReviewScopeKind scope = ReviewScopeKind.program}) =>
      ReviewSession(
        reviewId: 'rev1',
        programId: 'prog1',
        scopeKind: scope,
        scopeLabel: 'Whole program',
        blockId: scope == ReviewScopeKind.block ? 'b1' : null,
        sessionId: scope == ReviewScopeKind.session ? 's1' : null,
      );

  /// Pumps a `Scaffold` inside a real [ReviewScope], handing the builder a
  /// context that is genuinely below it — which is the whole point, since the
  /// slot reads the ambient session off that chain.
  Future<void> pumpScaffold(
    WidgetTester tester,
    Widget Function(BuildContext context) build,
  ) => tester.pumpWidget(
    ReviewScope(child: MaterialApp(home: Builder(builder: build))),
  );

  group('reviewBottomSlot', () {
    testWidgets('gives the child back untouched when no review is running', (
      tester,
    ) async {
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
            child: const Text('nav bar'),
          ),
        ),
      );
      expect(find.text('nav bar'), findsOneWidget);
      expect(find.text('Reviewing'), findsNothing);
    });

    testWidgets('returns null when there is neither a review nor a child', (
      tester,
    ) async {
      // Easy to get wrong and expensive to miss: a zero-height placeholder
      // here would flip the Scaffold's internal bottom-padding handling, and
      // the editor's last row would scroll under the home indicator with
      // nothing drawn over it.
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
          ),
        ),
      );
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
    });

    testWidgets('stacks the bar above the child once a review is running', (
      tester,
    ) async {
      reviewSessionNotifier.value = session();
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
            child: const Text('nav bar'),
          ),
        ),
      );
      expect(find.text('Reviewing'), findsOneWidget);
      expect(find.text('Whole program'), findsOneWidget);
      expect(find.text('nav bar'), findsOneWidget);
    });

    testWidgets('with nothing under it, the bar carries the home-indicator '
        'inset itself', (tester) async {
      // 34 logical points, the classic bottom inset. Physical pixels on the
      // view; logical ones in the padding.
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
          ),
        ),
      );

      // The inset goes INSIDE the bar's own background, the way `BottomNavBar`
      // does it: the accent has to reach the screen edge while the Finish
      // button stays out of the gesture zone. It REPLACES the base padding
      // rather than stacking on it — the content sits just above the home
      // indicator, not a base padding above it with a dead band under.
      final padding = _barPadding(tester);
      expect(padding.bottom, 34);
      // And the sides are uniform: the label and Finish share one inset —
      // wider than the content above, so the controls stay off the screen
      // edges.
      expect(padding.left, AppSpacing.xl);
      expect(padding.top, AppSpacing.lg);
      expect(padding.right, AppSpacing.xl);
    });

    testWidgets('keeps its own padding when there is no inset to yield to', (
      tester,
    ) async {
      // No home indicator, or a raised keyboard — the inset drops to zero and
      // must not take the bottom padding with it, or the button would sit
      // flush against the edge.
      reviewSessionNotifier.value = session();
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
          ),
        ),
      );
      expect(_barPadding(tester).bottom, AppSpacing.lg);
    });

    testWidgets('puts its content the same distance from every real screen '
        'edge', (tester) async {
      // The padding assertions above say what the container declares; this one
      // says what the user sees. Measured on an iPhone-class viewport
      // (402×874 logical, 34pt inset) straight off the laid-out widgets.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
          ),
        ),
      );

      final bar = tester.getRect(find.byType(ReviewBar));
      final label = tester.getRect(find.text('Reviewing'));
      final finish = tester.getRect(find.byType(GlassButton));

      final screenWidth = tester.view.physicalSize.width / 3;
      final screenHeight = tester.view.physicalSize.height / 3;

      // Label off the left edge and Finish off the right edge: the same 24pt.
      expect(label.left - bar.left, AppSpacing.xl);
      expect(screenWidth - finish.right, closeTo(AppSpacing.xl, 0.01));
      // Content bottom off the screen bottom: the inset alone.
      expect(screenHeight - finish.bottom, closeTo(34, 0.01));
      // The bar's background still reaches the edge the inset reserves.
      expect(bar.bottom, closeTo(screenHeight, 0.01));
    });

    testWidgets('with an editor bar stacked under it, the bar leaves the '
        'inset to that bar', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 102);
      addTearDown(tester.view.reset);
      reviewSessionNotifier.value = session();

      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
            child: const Text('nav bar'),
          ),
        ),
      );

      // Exactly the base padding: `BottomNavBar` absorbs the inset under this
      // bar, and a second helping here would open a strip of accent between
      // the two.
      expect(_barPadding(tester).bottom, AppSpacing.lg);
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

  group('Finish', () {
    testWidgets(
      'settles the editor first, and aborts when it does not settle',
      (tester) async {
        reviewSessionNotifier.value = session();
        final gate = Completer<bool>();
        var settled = 0;

        await pumpScaffold(
          tester,
          (context) => Scaffold(
            bottomNavigationBar: reviewBottomSlot(
              context,
              settle: () {
                settled++;
                return gate.future;
              },
              child: const Text('nav bar'),
            ),
          ),
        );

        await tester.tap(find.text('Finish'));
        await tester.pump();

        // Settle is asked FIRST. A snapshot records the plan as it stands, so
        // opening the notes sheet over an editor with unsaved edits would let
        // the user describe changes that are not in what gets saved.
        expect(settled, 1);
        expect(
          find.text('Finish review'),
          findsNothing,
          reason: 'the notes sheet must not open until the editor settles',
        );

        // The user chose "Stay", or the save failed. Either way the review is
        // still running and nothing was written.
        gate.complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Reviewing'), findsOneWidget);
        expect(find.text('Finish review'), findsNothing);
        expect(reviewSessionNotifier.value?.reviewId, 'rev1');
      },
    );

    testWidgets('leaves without finishing when dismissed', (tester) async {
      reviewSessionNotifier.value = session();
      await pumpScaffold(
        tester,
        (context) => Scaffold(
          bottomNavigationBar: reviewBottomSlot(
            context,
            settle: () async => true,
            child: const Text('nav bar'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Reviewing is optional: opening one to look around and walking out must
      // leave it open, with no snapshot cut.
      expect(reviewSessionNotifier.value, isNull);
      expect(find.text('Reviewing'), findsNothing);
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

/// The padding the bar's own container applies — where the inset has to land
/// to keep the accent flush with the screen edge.
EdgeInsets _barPadding(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(ReviewBar), matching: find.byType(Container))
        .first,
  );
  return container.padding! as EdgeInsets;
}
