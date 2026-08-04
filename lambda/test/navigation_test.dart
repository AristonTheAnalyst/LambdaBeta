import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lambda/features/statistics/view/insights_screen.dart';
import 'package:lambda/features/statistics/view/pr_catalog_screen.dart';
import 'package:lambda/features/statistics/view/statistics_screen.dart';

/// Ground-truth check: does ONE tap on the Insights card navigate to the
/// Insights screen (vs. needing two presses as reported on device)?
void main() {
  testWidgets('one tap on Insights card pushes InsightsScreen', (tester) async {
    final router = GoRouter(
      initialLocation: '/statistics',
      routes: [
        GoRoute(
          path: '/statistics',
          builder: (_, _) => const StatisticsScreen(),
          routes: [
            GoRoute(path: 'insights', builder: (_, _) => const InsightsScreen()),
            GoRoute(path: 'prs', builder: (_, _) => const PrCatalogScreen()),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // On the hub.
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(find.byType(InsightsScreen), findsNothing);

    // ONE tap on the Insights card.
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.byType(InsightsScreen), findsOneWidget,
        reason: 'a single tap on the Insights card should navigate to it');
  });
}
