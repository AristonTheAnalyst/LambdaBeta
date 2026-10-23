import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/session/view/ratings_sheet.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';

import 'support/readable_text.dart';

/// The live session's ratings pencil opens one sheet holding both bookends
/// (2026-10-22): the same wording the pre/post wizard pages use, editable
/// while the session runs and read-only wherever the viewer passes no
/// callbacks. Every edit must reach the caller — the sheet is a second door
/// to the VM's four fields, never a private copy.

Finder _inPre(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('session-ratings-pre')),
  matching: matching,
);

Finder _inPost(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('session-ratings-post')),
  matching: matching,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  bool editable = true,
  int? preFeeling,
  String preNotes = '',
  int? postFeeling,
  String postNotes = '',
  List<int>? preTaps,
  List<String>? preTyped,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showSessionRatingsSheet(
                context,
                preFeeling: preFeeling,
                preNotes: preNotes,
                postFeeling: postFeeling,
                postNotes: postNotes,
                onPreFeelingChanged: editable ? (n) => preTaps?.add(n) : null,
                onPreNotesChanged: editable ? (v) => preTyped?.add(v) : null,
                onPostFeelingChanged: editable ? (_) {} : null,
                onPostNotesChanged: editable ? (_) {} : null,
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
  testWidgets('the sheet draws the session\'s two bookends', (tester) async {
    await _pumpSheet(
      tester,
      preFeeling: 4,
      preNotes: 'Slept well',
      postFeeling: 3,
      postNotes: 'Rushed the last set',
    );

    expect(find.byKey(const ValueKey('session-ratings-sheet')), findsOneWidget);
    expect(find.text('Session Ratings'), findsOneWidget);
    expect(find.text('PRE-WORKOUT'), findsOneWidget);
    expect(find.text('POST-WORKOUT'), findsOneWidget);
    expect(
      find.text("How well do you think you're going to do"),
      findsOneWidget,
    );
    expect(find.text('How well did you do this session'), findsOneWidget);

    // The stored notes and ratings arrive in their own sections.
    expect(_inPre(find.text('Slept well')), findsOneWidget);
    expect(_inPost(find.text('Rushed the last set')), findsOneWidget);
    expect(_inPre(find.byIcon(Icons.star_rounded)), findsNWidgets(4));
    expect(_inPost(find.byIcon(Icons.star_rounded)), findsNWidgets(3));

    // Editable while the session runs.
    expect(find.byType(LambdaInput), findsNWidgets(2));
    expectReadableText(
      tester,
      find.byKey(const ValueKey('session-ratings-sheet')),
    );
  });

  testWidgets('a star tap and a keystroke reach the caller', (tester) async {
    final preTaps = <int>[];
    final preTyped = <String>[];
    await _pumpSheet(tester, preTaps: preTaps, preTyped: preTyped);

    // Nothing rated yet: five empty stars in the pre section.
    final stars = _inPre(find.byIcon(Icons.star_border_rounded));
    expect(stars, findsNWidgets(5));

    // The callback carries the tapped number — the VM's setter owns the
    // toggle rule, so the sheet never decides what "tap 3" means.
    await tester.tap(stars.at(2));
    await tester.pumpAndSettle();
    expect(preTaps, [3]);
    expect(_inPre(find.byIcon(Icons.star_rounded)), findsNWidgets(3));

    await tester.enterText(_inPre(find.byType(LambdaInput)), 'Felt strong');
    await tester.pumpAndSettle();
    expect(preTyped, ['Felt strong']);
  });

  testWidgets('null callbacks render both bookends read-only', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      editable: false,
      preFeeling: 2,
      preNotes: 'Slept well',
    );

    expect(find.byType(LambdaInput), findsNothing);
    expect(_inPre(find.byType(LambdaReadout)), findsOneWidget);
    expect(_inPre(find.text('Slept well')), findsOneWidget);
    // Empty read-only notes state the absence instead of drawing a field.
    expect(find.text('No post-workout notes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('session-ratings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-ratings-sheet')), findsNothing);
  });
}
