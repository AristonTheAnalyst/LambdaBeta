import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<ScrollController> pumpBar(
    WidgetTester tester, {
    ValueChanged<int>? onTap,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollShrinkNavBar(
            controller: controller,
            currentIndex: 0,
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

  testWidgets('tapping an item reports its index', (tester) async {
    int? tapped;
    await pumpBar(tester, onTap: (i) => tapped = i);

    await tester.tap(find.byIcon(Icons.search));
    expect(tapped, 1);
  });
}
