import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_spacing.dart';
import 'package:lambda/shared/widgets/card_pill_button.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';
import 'package:lambda/shared/widgets/session_exercise_card.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

import 'support/readable_text.dart';

/// The review note box on THE exercise card.
///
/// The box is the whole of a review note's life: on the editor it is where the
/// note is typed AND where it is read back, on the record it IS the record. So
/// its states have to come apart exactly — absent on a card with no review and
/// nothing noted; a live text box inside a review, shown even before there is
/// a note because the empty box is the way in; plain text on the record, and
/// only when there is something to read — and none of them may disturb the
/// rest of the card, which three other screens draw every day.
///
/// The states also have to wear the app's one text-box rule: editable is
/// [LambdaInput], read-only is [LambdaReadout].
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    String? reviewNote,
    ValueChanged<String>? onReviewNoteChanged,
    String reviewNoteLabel = kReviewNoteLabel,
    String? reviewNoteEmptyText,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionExerciseCard(
          exerciseNames: const ['Bench Press'],
          activeIndex: 0,
          onSelect: (_) {},
          rows: const [],
          reviewNote: reviewNote,
          onReviewNoteChanged: onReviewNoteChanged,
          reviewNoteLabel: reviewNoteLabel,
          reviewNoteEmptyText: reviewNoteEmptyText,
        ),
      ),
    ),
  );

  testWidgets('with nothing noted and no review, no box is drawn at all', (
    tester,
  ) async {
    // Every ordinary card — the live session, the planner at rest — lands
    // here, and a box they never asked for would be chrome on four screens.
    await pumpCard(tester);
    expect(find.text('Review Note'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'inside a review the box is a live field before there is a note',
    (tester) async {
      String? written;
      await pumpCard(tester, onReviewNoteChanged: (v) => written = v);

      // Empty, the box is still the way in: the header names it, and there is
      // a field to type into — nothing to open, no invitation copy to read.
      expect(find.text('Review Note'), findsOneWidget);
      expect(
        find.byType(LambdaInput),
        findsOneWidget,
        reason: 'an editable text box is LambdaInput, the app over',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.fillColor,
        AppColors.surface,
        reason:
            'the box must copy the session-prep notes box ("Why do you '
            'feel that way") exactly — the reference field\'s base fill, no '
            'elevated step (2026-10-08: the surfaceHigh version read as a '
            'different box from the one being copied)',
      );
      await tester.enterText(find.byType(TextField), 'Felt heavy');
      expect(written, 'Felt heavy');
    },
  );

  testWidgets('the box shows the note as typed, and edits it in place', (
    tester,
  ) async {
    String? written;
    await pumpCard(
      tester,
      reviewNote: 'Felt heavy — drop to 55 if it grinds',
      onReviewNoteChanged: (v) => written = v,
    );

    // As is: the field carries exactly what the row holds, no ellipsis, no
    // truncation — the note is read where it is written.
    expect(find.text('Felt heavy — drop to 55 if it grinds'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Dropped to 55');
    expect(written, 'Dropped to 55');
  });

  testWidgets('the field never re-seats itself from the echo of a write', (
    tester,
  ) async {
    // The card re-renders with the stored note after every keystroke's
    // write. A rebuild that feeds the same text back must leave the field
    // alone — re-seating the controller would throw the caret to the end.
    await pumpCard(
      tester,
      reviewNote: 'Felt heavy',
      onReviewNoteChanged: (_) {},
    );
    await tester.enterText(find.byType(TextField), 'x');
    // Same text arriving again under a new widget generation.
    await pumpCard(tester, reviewNote: 'x', onReviewNoteChanged: (_) {});
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'x');
  });

  testWidgets('on the record the note is shown read-only', (tester) async {
    // No change callback: the record is not a place notes are written. The
    // note still shows — that is the whole reason it was written.
    await pumpCard(tester, reviewNote: '  Swapped to paused reps  ');

    expect(find.text('Review Note'), findsOneWidget);
    // Trimmed: the box is a display here, and the whitespace a note was saved
    // with is not part of what it says.
    expect(find.text('Swapped to paused reps'), findsOneWidget);
    expect(
      find.byType(LambdaReadout),
      findsOneWidget,
      reason: 'a read-only text box is LambdaReadout, never a dead field',
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'an editable field belongs to the pass, not the record',
    );
  });

  testWidgets('the record\'s note reads under its own header', (tester) async {
    // While Compare is up the box shows the RECORD's note — the editor hands
    // it the record's words — and the header has to say whose note it is: a
    // note read under the pass's own header would be taken for the one being
    // written (2026-10-10).
    await pumpCard(
      tester,
      reviewNote: 'Swapped to paused reps',
      reviewNoteLabel: kPreviousReviewNoteLabel,
    );

    expect(find.text(kPreviousReviewNoteLabel), findsOneWidget);
    expect(
      find.text(kReviewNoteLabel),
      findsNothing,
      reason:
          'the pass\'s header on the record\'s note would claim the note '
          'is the one being written',
    );
    expect(find.text('Swapped to paused reps'), findsOneWidget);
    expect(
      find.byType(LambdaReadout),
      findsOneWidget,
      reason:
          'the record\'s note is display, never a field — the pass\'s note '
          'is written after the eye flips back',
    );
  });

  testWidgets('with nothing noted, the record\'s box holds its place and says '
      'so', (tester) async {
    // The flip changes values, never furniture: an exercise the record left
    // nothing about keeps the box the eye just landed on, and the absence of
    // a note is answered inside it — secondary ink, in the note's own place,
    // so it reads as "nothing was said" rather than as a note (2026-10-10;
    // ink raised from muted 2026-10-22).
    await pumpCard(
      tester,
      reviewNoteLabel: kPreviousReviewNoteLabel,
      reviewNoteEmptyText: kNoPreviousNoteText,
    );

    expect(find.text(kPreviousReviewNoteLabel), findsOneWidget);
    expect(find.text(kNoPreviousNoteText), findsOneWidget);
    expect(find.byType(LambdaReadout), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(kNoPreviousNoteText)).style!.color,
      AppColors.inkSecondary,
      reason:
          'placeholder copy wears the input placeholder\'s readable ink — '
          'a note\'s ink on an empty box would read as a note',
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'still the record: nothing here is writable',
    );
  });

  testWidgets('the box reads after the sets, never in the lesson slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionExerciseCard(
            exerciseNames: const ['Bench Press'],
            activeIndex: 0,
            onSelect: (_) {},
            rows: const [],
            onAddSet: () {},
            pinnedLesson: PinnedLessonData(
              text: 'Keep the elbows tucked',
              date: DateTime(2026, 10, 1),
            ),
            reviewNote: 'Swapped to paused reps',
            onReviewNoteChanged: (_) {},
          ),
        ),
      ),
    );

    // How to do the lift stays where it was — under the selector; how it
    // went reads after the work it is about.
    expect(
      tester.getTopLeft(find.text('Keep the elbows tucked')).dy,
      lessThan(tester.getTopLeft(find.text('Review Note')).dy),
    );
    expect(
      tester.getTopLeft(find.text('+ ADD SET')).dy,
      lessThan(tester.getTopLeft(find.text('Review Note')).dy),
    );
  });

  testWidgets('the pinned note reads whole in a popup; the sheet is one tap '
      'on', (tester) async {
    var viewAll = 0;
    const cue =
        'Keep the elbows tucked and pull the bar into the hips — a cue far '
        'longer than the bar\'s one line can hold';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionExerciseCard(
            exerciseNames: const ['Bench Press'],
            activeIndex: 0,
            onSelect: (_) {},
            rows: const [],
            onAddSet: () {},
            pinnedLesson: PinnedLessonData(
              text: cue,
              date: DateTime(2026, 10, 1),
            ),
            onPinnedLessonTap: () => viewAll++,
          ),
        ),
      ),
    );

    // One note glyph on the card — the bar and the Notes pill both wear the
    // set row's sticky note, never a pin (2026-10-23).
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNWidgets(2));

    // The bar holds one ellipsized line, so a tap reads before it navigates:
    // the complete message, in a popup, with no sheet opened behind it.
    await tester.tap(find.text(cue));
    await tester.pumpAndSettle();
    expect(find.text('Exercise Note'), findsOneWidget);
    expect(
      find.text(cue),
      findsNWidgets(2),
      reason: 'the popup carries the complete message, not a preview',
    );
    expect(viewAll, 0, reason: 'reading a note is not opening the sheet');

    // Close is just reading.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Exercise Note'), findsNothing);
    expect(viewAll, 0);

    // Reopen and take the door: the popup leaves, then the sheet opens.
    await tester.tap(find.text(cue));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View all exercise notes'));
    await tester.pumpAndSettle();
    expect(find.text('Exercise Note'), findsNothing);
    expect(viewAll, 1);
  });

  testWidgets('with nothing to add, the row can still hold its place — dead', (
    tester,
  ) async {
    // What Compare leans on: the card draws the same workout with the record's
    // rows in place of the plan's, and the grid must not move under the finger
    // that just tapped the button. So the row stays, greyed, with no press.
    var tapped = 0;
    Future<double> heightWith({required bool reserved}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // A scroll view, as the editor has: the card takes its own height
            // instead of being stretched to the screen's.
            body: SingleChildScrollView(
              child: SessionExerciseCard(
                exerciseNames: const ['Bench Press'],
                activeIndex: 0,
                onSelect: (_) {},
                rows: const [],
                onAddSet: reserved ? null : () => tapped++,
                reserveAddSet: reserved,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(SessionExerciseCard)).height;
    }

    final live = await heightWith(reserved: false);
    await tester.tap(find.text('+ ADD SET'));
    expect(tapped, 1, reason: 'the ordinary row is a button');

    final reserved = await heightWith(reserved: true);
    expect(
      reserved,
      live,
      reason:
          'reserving the row exists precisely so the card is exactly as '
          'tall either way — the flip changes values, never the layout',
    );
    await tester.tap(find.text('+ ADD SET'));
    expect(
      tapped,
      1,
      reason:
          'and it is dead: there is nothing to add to a '
          'record',
    );
  });

  testWidgets('the card draws readable ink and type', (tester) async {
    await pumpCard(tester);
    expectReadableText(
      tester,
      find.byType(MaterialApp),
      // The numeric cells' `—` is the documented muted absence glyph.
      allowMuted: {'—'},
    );
  });

  // ── The flat card (2026-10-22) ────────────────────────────────────────────
  // The live session and the past-session viewer draw the card with no fill
  // and no inner boxes. One 6pt inset puts the selector's arrows, the set
  // rows and the column labels on the page's 22pt gutter (16 page + 6 card).
  // The card draws no state rim at all (2026-10-23): planned's blue lives on
  // the selector field and the set rows, and a deleted exercise reads off its
  // red selector name and red rows.

  SessionSetRow readOnlyRow() => SessionSetRow(
    key: const ValueKey('flat-set-row'),
    mode: SetRowMode.planned,
    exerciseId: 'ex1',
    displayIndex: 1,
    isDraft: false,
    initialWeightText: '100',
    initialRepsText: '5',
    initialVariationId: null,
    hasNotes: false,
    readOnly: true,
    onCommit: (_, _, {bool immediate = false}) async {},
    onVariationChanged: (_) {},
    onNotesSave: (_) {},
    onDelete: () async {},
    onDuplicate: (_) {},
    variationOptions: const [
      DropdownOption<String?>(label: 'No Variation', value: null),
    ],
    allVariations: const [],
    findSimilarVariations: (_) => const [],
    submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
        null,
  );

  Future<void> pumpFlatCard(
    WidgetTester tester, {
    bool flat = true,
    bool planned = false,
    bool selectorDeleted = false,
  }) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            // The page's own gutter, as the live screen and the viewer both
            // draw it — the card owns only the 6 that follows.
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SessionExerciseCard(
              flat: flat,
              planned: planned,
              deletedExercises: [selectorDeleted, false],
              exerciseNames: const ['Bench Press', 'Row'],
              activeIndex: 0,
              onSelect: (_) {},
              rows: [readOnlyRow()],
              onAddSet: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the flat card has no door row under the selector; the boxed '
      'card still does', (tester) async {
    // The session look's doors are on the floor (PRs behind the trophy,
    // lessons behind the book), so the card goes selector straight to the
    // grid — the lab's arrangement, which the flat card mirrors. The boxed
    // card keeps its three pills, because the planner and the review
    // editors have no floor to carry them (2026-10-22).
    await pumpFlatCard(tester);
    expect(find.byType(CardPillButton), findsNothing);

    await pumpFlatCard(tester, flat: false);
    expect(find.byType(CardPillButton), findsNWidgets(3));
  });

  testWidgets('the flat card stands every child on the 22pt gutter', (
    tester,
  ) async {
    await pumpFlatCard(tester);

    // 402pt page − 16pt gutter each side = the 370pt card; the card's 6pt
    // inset is the last step to 22.
    const gutter = AppSpacing.lg + 6;
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('exercise-selector-prev')))
          .dx,
      gutter,
      reason: 'the selector\'s arrows start on the gutter',
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('flat-set-row'))).dx,
      gutter,
      reason: 'the set rows start on the same line, not 20pt inside it',
    );
    expect(
      tester.getTopRight(find.byKey(const ValueKey('flat-set-row'))).dx,
      402 - gutter,
      reason: 'and end on the mirrored gutter',
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('session-grid-headers')))
          .dx,
      gutter + 8,
      reason: 'the column labels sit 8pt inside, over the number cells',
    );
  });

  testWidgets('the flat card draws no rim in any state', (tester) async {
    BoxDecoration decoration() =>
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('session-exercise-card')),
                )
                .decoration!
            as BoxDecoration;

    await pumpFlatCard(tester);
    expect(
      decoration().color,
      isNull,
      reason: 'the page ground shows straight through the card',
    );
    expect(
      decoration().border,
      isNull,
      reason: 'the furniture carries no state',
    );

    // Planned draws no rim (2026-10-23): the blue moved down into the
    // selector field and the set rows.
    await pumpFlatCard(tester, planned: true);
    expect(decoration().color, isNull);
    expect(decoration().border, isNull);

    // Deleted draws no rim either (2026-10-23): the red selector name and
    // the red rows carry the deletion.
    await pumpFlatCard(tester, selectorDeleted: true);
    expect(decoration().color, isNull);
    expect(decoration().border, isNull);
  });

  testWidgets('the selector field carries the plan; deleted wears the deleted '
      'box instead', (tester) async {
    BoxDecoration field() =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(const ValueKey('exercise-selector-field')),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    await pumpFlatCard(tester);
    expect(
      (field().border! as Border).top.color,
      AppColors.primary.withAlpha(77),
      reason: 'neutral glass field on a freestyle exercise',
    );

    await pumpFlatCard(tester, planned: true);
    expect(field().color, AppColors.plannedBg);
    expect(
      (field().border! as Border).top.color,
      AppColors.planned.withValues(alpha: 0.35),
    );

    // Deleted still outranks planned — a deleted exercise is red, not blue.
    await pumpFlatCard(tester, planned: true, selectorDeleted: true);
    expect(field().color, AppColors.dangerBg);
    expect((field().border! as Border).top.color, AppColors.danger);
  });

  testWidgets('the boxed card keeps its normal edge; no state adds a rim', (
    tester,
  ) async {
    // The planner and the review-record screens keep the boxed card — the
    // flat flag must not have changed them, and neither `planned` nor a
    // deleted exercise repaints the boxed card's edge (the states live on the
    // selector and the rows).
    await pumpFlatCard(tester, flat: false, planned: true);
    final decoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('session-exercise-card')),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.color, AppColors.surface);
    expect((decoration.border! as Border).top.color, AppColors.border);

    await pumpFlatCard(tester, flat: false, selectorDeleted: true);
    final deletedDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('session-exercise-card')),
                )
                .decoration!
            as BoxDecoration;
    expect(
      (deletedDecoration.border! as Border).top.color,
      AppColors.border,
    );
  });
}
