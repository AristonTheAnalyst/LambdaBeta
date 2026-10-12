import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_spacing.dart';
import 'package:lambda/shared/widgets/scroll_shrink_nav_bar.dart';

/// The scroll-driven half of [ScrollShrinkNavBar]. In tests the bottom safe
/// area is zero, so the bar's painted height is exactly its box height.
void main() {
  const items = [
    ScrollShrinkNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    ScrollShrinkNavItem(
      icon: Icons.search,
      activeIcon: Icons.search,
      label: 'Search',
    ),
  ];

  /// The bar takes no controller — it follows the list's scroll
  /// notifications. The test keeps one only so it can drive the scroll.
  Future<ScrollController> pumpBar(
    WidgetTester tester, {
    ValueChanged<int>? onTap,
    int currentIndex = 0,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollShrinkNavBar(
            currentIndex: currentIndex,
            onTap: onTap ?? (_) {},
            items: items,
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 40; i++)
                  const SizedBox(height: 100, child: Text('row')),
              ],
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  /// The bar's painted box. The shrink is a transform, so the layout size
  /// stays at the expanded one — only the transformed rect tells the truth.
  Rect barRect(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(find.byType(BackdropFilter));
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  double barHeight(WidgetTester tester) => barRect(tester).height;

  /// A jump is what a real scroll produces, minus the gesture. The first jump
  /// only primes the direction — the bar needs two samples to see one.
  Future<void> scrollTo(
    WidgetTester tester,
    ScrollController controller,
    double offset,
  ) async {
    controller.jumpTo(offset);
    await tester.pumpAndSettle();
  }

  testWidgets('starts at full size', (tester) async {
    await pumpBar(tester);
    expect(barHeight(tester), ScrollShrinkNavBar.expandedHeight);
  });

  testWidgets('shrinks when the page scrolls down', (tester) async {
    final controller = await pumpBar(tester);
    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);
  });

  testWidgets('shrinks in both dimensions, as one piece', (tester) async {
    final controller = await pumpBar(tester);
    final expanded = barRect(tester);

    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    final collapsed = barRect(tester);

    expect(collapsed.height, lessThan(expanded.height));
    expect(collapsed.width, lessThan(expanded.width));
    // Uniform: both axes move by the same factor.
    expect(
      collapsed.width / expanded.width,
      closeTo(collapsed.height / expanded.height, 0.001),
    );
    // Anchored at the bottom edge, so it recedes without drifting upward.
    expect(collapsed.bottom, closeTo(expanded.bottom, 0.001));
    expect(collapsed.left, greaterThan(expanded.left));
    expect(collapsed.right, lessThan(expanded.right));
  });

  testWidgets('springs back when the page scrolls up', (tester) async {
    final controller = await pumpBar(tester);
    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);

    await scrollTo(tester, controller, 250);
    expect(barHeight(tester), ScrollShrinkNavBar.expandedHeight);
  });

  testWidgets('expands when the page returns to the top', (tester) async {
    final controller = await pumpBar(tester);
    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);

    await scrollTo(tester, controller, 0);
    expect(barHeight(tester), ScrollShrinkNavBar.expandedHeight);
  });

  testWidgets('a tab change arrives fully expanded', (tester) async {
    final controller = await pumpBar(tester);
    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);

    // Not a scroll — the bar must not inherit the last page's collapse.
    await pumpBar(tester, currentIndex: 1);
    await tester.pumpAndSettle();
    expect(barHeight(tester), ScrollShrinkNavBar.expandedHeight);
  });

  testWidgets('tapping an item reports its index', (tester) async {
    int? tapped;
    await pumpBar(tester, onTap: (i) => tapped = i);

    await tester.tap(find.byIcon(Icons.search));
    expect(tapped, 1);
  });

  testWidgets('drives from a list inside a horizontal pager', (tester) async {
    // The Session tab's shape: the list the page scrolls lives inside a
    // pager, and the bar still has to follow it.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollShrinkNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: items,
            child: PageView(
              children: [
                ListView(
                  controller: controller,
                  children: [
                    for (var i = 0; i < 40; i++)
                      const SizedBox(height: 100, child: Text('row')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await scrollTo(tester, controller, 50);
    await scrollTo(tester, controller, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);
  });

  testWidgets('a sideways scroller is not the page moving', (tester) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollShrinkNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: items,
            // A single scroll view rather than a lazy list: the chip row has
            // to stay attached to its controller while the page is scrolled
            // past it, and a lazy list would have thrown it away.
            child: SingleChildScrollView(
              controller: vertical,
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: ListView(
                      controller: horizontal,
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < 40; i++)
                          const SizedBox(width: 100, child: Text('chip')),
                      ],
                    ),
                  ),
                  for (var i = 0; i < 40; i++)
                    const SizedBox(height: 100, child: Text('row')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Sideways movement, with the page itself still at the top: the bar has
    // no business reacting to it.
    horizontal.jumpTo(400);
    await tester.pumpAndSettle();
    expect(barHeight(tester), ScrollShrinkNavBar.expandedHeight);

    await scrollTo(tester, vertical, 50);
    await scrollTo(tester, vertical, 400);
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);

    // And the other way round: a chip row swiped while the page is scrolled
    // down must not spring the bar back open.
    horizontal.jumpTo(800);
    await tester.pumpAndSettle();
    expect(barHeight(tester), ScrollShrinkNavBar.collapsedHeight);
  });

  testWidgets('contentInset answers for the bar, and only under one',
      (tester) async {
    double? beside;
    double? under;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // No bar above this one: a page opened full-screen, which must
            // not reserve space for a bar that is not there.
            beside = ScrollShrinkNavBar.contentInset(context);
            return ScrollShrinkNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: items,
              child: Builder(
                builder: (context) {
                  under = ScrollShrinkNavBar.contentInset(context);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(beside, 0);
    expect(under, ScrollShrinkNavBar.expandedHeight + AppSpacing.sm + AppSpacing.lg);
  });
}
