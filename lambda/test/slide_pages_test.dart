import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/slide_pages.dart';

Widget _pager(SlidePagesController c) => MaterialApp(
      home: Scaffold(
        body: SlidePages(
          controller: c,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            Center(child: Text('prep')),
            Center(child: Text('training')),
            Center(child: Text('reflection')),
          ],
        ),
      ),
    );

void main() {
  testWidgets('wizard page survives tab re-entry via restorePageView',
      (tester) async {
    final c = SlidePagesController();
    await tester.pumpWidget(_pager(c));
    c.slideToPage(1); // header Start → Training
    await tester.pump();
    expect(c.currentPage, 1);

    // Tab away: the shell disposes the screen, detaching the PageView.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    // Re-entry: anchor the pager BEFORE the fresh PageView attaches (what
    // SessionScreen.initState does on the cached-VM path).
    c.restorePageView();
    await tester.pumpWidget(_pager(c));
    await tester.pump();

    expect(c.currentPage, 1,
        reason: 'a fresh PageView must resume at the page the user left');
    expect(find.text('training'), findsOneWidget);
    expect(find.text('prep'), findsNothing);
  });

  testWidgets('without restorePageView a fresh PageView resets to page 0',
      (tester) async {
    final c = SlidePagesController();
    await tester.pumpWidget(_pager(c));
    c.slideToPage(1);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    await tester.pumpWidget(_pager(c));
    await tester.pump();

    // Documents the failure mode restorePageView exists to fix: the reattached
    // PageView starts at its initialPage (0), dumping the user back on Prep —
    // whose header has no Back button.
    expect(find.text('prep'), findsOneWidget);
    expect(find.text('training'), findsNothing);
  });
}
