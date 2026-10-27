import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/features/session/view/ratings_sheet.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';

import 'support/readable_text.dart';

/// The live session's ratings pencil opens one sheet holding both bookends
/// (2026-10-22): the same wording the pre/post wizard pages use, editable
/// while the session runs and read-only wherever the viewer passes no
/// callbacks. Every edit must reach the caller — the sheet is a second door
/// to the VM's four fields, never a private copy.
///
/// A surface with a read/edit MODE (the past-session viewer) passes
/// [showSessionRatingsSheet]'s `onEditingChanged` and grows the sheet's own
/// pencil, left of the X (2026-10-27): the toggle flips the sections in place
/// and drives the caller's mode.

Finder _inPre(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('session-ratings-pre')),
  matching: matching,
);

Finder _inPost(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('session-ratings-post')),
  matching: matching,
);

Finder _editButton() => find.byKey(const ValueKey('session-ratings-edit'));

Future<void> _pumpSheet(
  WidgetTester tester, {
  bool editable = true,
  bool editing = true,
  List<bool>? editToggles,
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
                editing: editing,
                preFeeling: preFeeling,
                preNotes: preNotes,
                postFeeling: postFeeling,
                postNotes: postNotes,
                onPreFeelingChanged: editable ? (n) => preTaps?.add(n) : null,
                onPreNotesChanged: editable ? (v) => preTyped?.add(v) : null,
                onPostFeelingChanged: editable ? (_) {} : null,
                onPostNotesChanged: editable ? (_) {} : null,
                onEditingChanged: editToggles?.add,
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

  testWidgets('null callbacks render both bookends read-only', (tester) async {
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

  testWidgets('the pencil sits left of the X, and only where a mode exists', (
    tester,
  ) async {
    // The live session is always editable: one mode, no toggle.
    await _pumpSheet(tester);
    expect(_editButton(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-ratings-close')));
    await tester.pumpAndSettle();

    // A surface with a read/edit mode grows the pencil in the close
    // button's own container, one slot to its left.
    await _pumpSheet(tester, editing: false, editToggles: []);
    expect(_editButton(), findsOneWidget);
    expect(
      tester.getCenter(_editButton()).dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('session-ratings-close')))
            .dx,
      ),
    );
  });

  testWidgets('the pencil flips the sections in place — accent while editing, '
      'primary glass while reading', (tester) async {
    final toggles = <bool>[];
    final preTaps = <int>[];
    final preTyped = <String>[];
    await _pumpSheet(
      tester,
      editing: false,
      editToggles: toggles,
      preFeeling: 2,
      preNotes: 'Slept well',
      preTaps: preTaps,
      preTyped: preTyped,
    );

    Icon pencilIcon() => tester.widget<Icon>(
      find.descendant(
        of: _editButton(),
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );

    // Reading: the stored answers, no fields, and the pencil at rest.
    expect(find.byType(LambdaInput), findsNothing);
    expect(_inPre(find.text('Slept well')), findsOneWidget);
    expect(find.bySemanticsLabel('Edit ratings'), findsOneWidget);
    expect(pencilIcon().color, AppColors.primary);

    // The tap reaches the caller's mode and the sheet turns editable on the
    // spot — the stored values stay on display (starting an edit seeds the
    // drafts from the record).
    await tester.tap(_editButton());
    await tester.pumpAndSettle();
    expect(toggles, [true]);
    expect(find.byType(LambdaInput), findsNWidgets(2));
    expect(_inPre(find.text('Slept well')), findsOneWidget);
    expect(find.bySemanticsLabel('Stop editing ratings'), findsOneWidget);
    expect(pencilIcon().color, AppColors.accent);

    // The text keeps the field's size in both modes — the toggle must not
    // resize the box's words (2026-10-28).
    final editSize = tester
        .widget<TextField>(_inPre(find.byType(TextField)))
        .style!
        .fontSize;

    // Editable for real: a star tap and a keystroke reach the caller. Two
    // stars are lit, so the first empty one is the third.
    await tester.tap(_inPre(find.byIcon(Icons.star_border_rounded)).at(0));
    await tester.pumpAndSettle();
    expect(preTaps, [3]);
    await tester.enterText(_inPre(find.byType(LambdaInput)), 'Felt strong');
    await tester.pumpAndSettle();
    expect(preTyped, ['Felt strong']);

    // Off again: back to reading, the snapped-back stored answers, and the
    // callbacks gated — nothing reaches the caller while the mode is read.
    await tester.tap(_editButton());
    await tester.pumpAndSettle();
    expect(toggles, [true, false]);
    expect(find.byType(LambdaInput), findsNothing);
    // The pre notes are a readout again; the post ones are empty, so they
    // state the absence instead of drawing a box.
    expect(find.byType(LambdaReadout), findsOneWidget);
    expect(find.text('No post-workout notes'), findsOneWidget);
    expect(_inPre(find.text('Slept well')), findsOneWidget);
    expect(
      tester.widget<Text>(_inPre(find.text('Slept well'))).style!.fontSize,
      editSize,
      reason:
          'the read-out and the field draw at one size — the toggle '
          'never resizes the text',
    );
    expect(
      find.text('Felt strong'),
      findsNothing,
      reason:
          'leaving the mode drops what was typed in it, like the '
          'viewer\'s cancel does',
    );

    final before = preTaps.length;
    await tester.tap(
      _inPre(find.byIcon(Icons.star_border_rounded)).at(0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      preTaps.length,
      before,
      reason: 'read mode never writes — the stars are inert',
    );
  });
}
