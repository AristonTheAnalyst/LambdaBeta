import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_text_styles.dart';
import 'package:lambda/features/dev/pr_lab/pr_lab_exercise_selector.dart';
import 'package:lambda/features/dev/pr_lab/pr_lab_screen.dart';
import 'package:lambda/features/dev/pr_lab/pr_lab_set_row.dart';
import 'package:lambda/features/dev/pr_lab/pr_lab_swipe_actions.dart';
import 'package:lambda/features/dev/pr_lab/pr_lab_undo_redo_buttons.dart';
import 'package:lambda/shared/widgets/feeling_rating.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';

import 'support/readable_text.dart';

/// The lab's isolated copy of the demo stage: it must render on its own and
/// open its own sheet, with no shared widget behind it (2026-10-21).
Finder _inSheet(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('pr-lab-sheet')),
  matching: matching,
);

/// A reading inside one action-bar tile — the tiles are glyph + number only,
/// and both numbers have look-alikes elsewhere on the stage (a reps cell, a
/// note body), so every count is read where it is drawn.
Finder _inTile(String key, String text) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

/// The pencil's sheet (2026-10-22).
Finder _inRatings(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('pr-lab-ratings-sheet')),
  matching: matching,
);

Future<void> _pumpLab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: PrLabScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the lab stage renders its copied widgets', (tester) async {
    await _pumpLab(tester);
    expect(find.text('Freestyle Session'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    // The date bar opens on today's session.
    expect(find.text('20 Oct 2026'), findsOneWidget);
    expect(find.text('TODAY -'), findsOneWidget);
    // Session-scoped metrics: the bench's gains in the fake session — two
    // PRs and two notes stamped with its id — drawn as gains.
    expect(_inTile('pr-lab-prs-tile', '+2'), findsOneWidget);
    expect(_inTile('pr-lab-notes-tile', '+2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the action bar carries undo, redo and the trash', (
    tester,
  ) async {
    await _pumpLab(tester);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);

    // The trash slot is live (one fake deleted exercise) and lists it.
    await tester.tap(find.byIcon(Icons.restore_from_trash));
    await tester.pumpAndSettle();
    expect(find.text('Dumbbell Fly'), findsOneWidget);
  });

  testWidgets('the trophy tile opens the lab sheet in two groups', (
    tester,
  ) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-prs-tile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pr-lab-sheet')), findsOneWidget);

    // The header wears the Notes sheet's recipe: the exercise as an
    // eyebrow over the title, with the all-time count beside the close.
    expect(_inSheet(find.text('BENCH PRESS')), findsOneWidget);
    expect(_inSheet(find.text('PR History')), findsOneWidget);
    // The door still opens the all-time feed; only the tile's number is
    // session-scoped.
    expect(_inSheet(find.text('12 PRs')), findsOneWidget);

    // This session's PRs lead under their own heading, history under the
    // next — and the retired all-time caption is gone.
    expect(_inSheet(find.text('THIS SESSION')), findsOneWidget);
    expect(_inSheet(find.text('PREVIOUSLY')), findsOneWidget);
    expect(
      tester.getRect(_inSheet(find.text('THIS SESSION'))).top,
      lessThan(tester.getRect(_inSheet(find.text('PREVIOUSLY'))).top),
    );
    expect(_inSheet(find.text('ALL-TIME · NEWEST FIRST')), findsNothing);
  });

  testWidgets('switching exercise re-reads both metric tiles', (tester) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    expect(find.text('Incline Bench Press'), findsOneWidget);
    expect(_inTile('pr-lab-prs-tile', '+2'), findsOneWidget);
    expect(_inTile('pr-lab-notes-tile', '+1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pr-lab-prs-tile')));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('INCLINE BENCH PRESS')), findsOneWidget);
    expect(_inSheet(find.text('5 PRs')), findsOneWidget);
  });

  testWidgets('a tile reading 0 still opens its door', (tester) async {
    await _pumpLab(tester);
    // Bench → incline → fly.
    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    expect(find.text('Cable Fly'), findsOneWidget);
    expect(_inTile('pr-lab-prs-tile', '+1'), findsOneWidget);
    expect(_inTile('pr-lab-notes-tile', '0'), findsOneWidget);

    // Zero notes means no session notes, not a dead tile — the modal
    // still opens over the exercise's seeded past note.
    await tester.tap(find.byKey(const ValueKey('pr-lab-notes-tile')));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    expect(
      find.text('Slight elbow bend held all the way through — never lock out.'),
      findsOneWidget,
    );
    // No notes in this session: the session's shelf is not drawn empty,
    // and the one earlier note sits under its own heading.
    expect(find.text('THIS SESSION'), findsNothing);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
  });

  testWidgets('the book tile opens the notes modal over seeded rows', (
    tester,
  ) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-notes-tile')));
    await tester.pumpAndSettle();

    // The same header recipe as the PR sheet: eyebrow over the title.
    expect(find.text('BENCH PRESS'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(
      find.text(
        'Wider grip was shifting the bar path left. Back to ring finger on '
        'the ring.',
      ),
      findsOneWidget,
    );

    // This session's notes lead, the ones before it follow — the pinned
    // old note stays under its own heading instead of jumping the line.
    expect(find.text('THIS SESSION'), findsOneWidget);
    expect(find.text('PREVIOUSLY'), findsOneWidget);
    final sessionTop = tester.getRect(find.text('THIS SESSION')).top;
    final previousTop = tester.getRect(find.text('PREVIOUSLY')).top;
    expect(sessionTop, lessThan(previousTop));
    expect(
      tester
          .getRect(
            find.text(
              'Leg drive starts before the bar leaves the chest, not after.',
            ),
          )
          .top,
      inExclusiveRange(sessionTop, previousTop),
    );
  });

  testWidgets('the keyboard paints over the floor instead of lifting it', (
    tester,
  ) async {
    await _pumpLab(tester);
    final dateBar = find.byKey(const ValueKey('pr-lab-session-date-bar'));
    final stage = find.byType(PrLabScreen);
    final resting = tester.getRect(dateBar);

    // A software keyboard's worth of inset, as iOS reports it while it is
    // up (physical pixels — 300 logical at this DPR).
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();

    // The inset really reached the page — otherwise the check below would
    // prove nothing.
    expect(MediaQuery.viewInsetsOf(tester.element(stage)).bottom, 300);

    // The floor is chrome and stays at the screen's edge; the keyboard is
    // drawn over it. A resizing Scaffold would have lifted this bar.
    expect(tester.getRect(dateBar), resting);
  });

  testWidgets('both chevron pairs stand on one recipe', (tester) async {
    await _pumpLab(tester);

    // The selector's flanks and the date bar's arrows are one control drawn
    // twice: the same 40 target, the same 24 chevron (2026-10-21).
    final keys = [
      'exercise-selector-prev',
      'exercise-selector-next',
      'pr-lab-prev-session',
      'pr-lab-next-session',
    ];
    final flanks = tester.getSize(
      find.byKey(const ValueKey('exercise-selector-prev')),
    );
    expect(flanks.width, kPrLabSelectorArrowSize);
    expect(flanks.height, kPrLabSelectorArrowSize);

    for (final key in keys) {
      final button = find.byKey(ValueKey(key));
      expect(tester.getSize(button), flanks);
      final icon = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byType(Icon)),
      );
      expect(icon.size, kPrLabSelectorArrowGlyph);
      expect(
        icon.icon,
        key.contains('prev') ? Icons.chevron_left : Icons.chevron_right,
      );
    }
  });

  testWidgets('the date sits centred between its two arrows', (tester) async {
    await _pumpLab(tester);
    final bar = tester.getRect(
      find.byKey(const ValueKey('pr-lab-session-date-bar')),
    );
    final state = tester.getRect(
      find.byKey(const ValueKey('pr-lab-session-state')),
    );
    final date = tester.getRect(
      find.byKey(const ValueKey('pr-lab-session-date')),
    );
    final prev = tester.getRect(
      find.byKey(const ValueKey('pr-lab-prev-session')),
    );
    final next = tester.getRect(
      find.byKey(const ValueKey('pr-lab-next-session')),
    );

    // One arrow at each edge; the phrase on the bar's own middle rather than
    // in whatever room the arrows leave (2026-10-21).
    expect(prev.right, lessThan(state.left));
    expect(next.left, greaterThan(date.right));
    expect((state.left + date.right) / 2, closeTo(bar.center.dx, 1));
  });

  testWidgets('the PR sheet draws readable type and ink', (tester) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-prs-tile')));
    await tester.pumpAndSettle();

    // Nothing in the sheet is 10px or muted (2026-10-21).
    expectReadableText(tester, find.byKey(const ValueKey('pr-lab-sheet')));

    final count = tester.widget<Text>(_inSheet(find.text('12 PRs')));
    expect(count.style?.fontSize, AppTextStyles.caption);
    expect(count.style?.color, AppColors.inkSecondary);

    // The label became the field-label recipe; the comparison it introduced
    // keeps the quiet ink while the values it beat carry content ink.
    final label = tester.widget<Text>(_inSheet(find.text('WEIGHT')));
    expect(label.style?.fontSize, AppTextStyles.xs);
    expect(label.style?.color, AppColors.primary);

    final was = tester.widget<Text>(_inSheet(find.text('WAS')).first);
    expect(was.style?.fontSize, AppTextStyles.xs);
    expect(was.style?.color, AppColors.inkSecondary);

    final gap = tester.widget<Text>(_inSheet(find.text('34 days prior')));
    expect(gap.style?.color, AppColors.inkSecondary);

    final killer = tester.widget<Text>(_inSheet(find.text('110kg × 3')));
    expect(killer.style?.fontSize, AppTextStyles.body);
    expect(killer.style?.color, AppColors.accent);
  });

  testWidgets('the notes sheet draws readable type and ink', (tester) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-notes-tile')));
    await tester.pumpAndSettle();

    const sheetKey = ValueKey('pr-lab-notes-sheet');
    expectReadableText(tester, find.byKey(sheetKey));
    Finder inSheet(Finder matching) =>
        find.descendant(of: find.byKey(sheetKey), matching: matching);

    // The body is the ladder's body size with a line height for prose.
    final body = tester.widget<Text>(
      inSheet(
        find.text(
          'Leg drive starts before the bar leaves the chest, not after.',
        ),
      ),
    );
    expect(body.style?.fontSize, AppTextStyles.body);
    expect(body.style?.height, 1.35);
    expect(body.style?.color, AppColors.primary);

    final date = tester.widget<Text>(inSheet(find.text('Sep 8 · 6:40 PM')));
    expect(date.style?.fontSize, AppTextStyles.xs);
    expect(date.style?.color, AppColors.inkSecondary);

    final heading = tester.widget<Text>(inSheet(find.text('THIS SESSION')));
    expect(heading.style?.fontSize, AppTextStyles.xs);
    expect(heading.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('the date bar walks the exercise history read-only', (
    tester,
  ) async {
    await _pumpLab(tester);
    expect(find.text('20 Oct 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pr-lab-prev-session')));
    await tester.pumpAndSettle();

    // The bar names the previous workout, and the card reads as history: no
    // add row, and that session's own values in place of today's.
    expect(find.text('16 Sep 2026'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(find.text('TODAY -'), findsNothing);
    expect(find.text('+ ADD SET'), findsNothing);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('110'), findsNothing);

    // The tiles keep counting the session on the desk, whatever date the
    // card is showing.
    expect(_inTile('pr-lab-prs-tile', '+2'), findsOneWidget);
    expect(_inTile('pr-lab-notes-tile', '+2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pr-lab-next-session')));
    await tester.pumpAndSettle();

    expect(find.text('20 Oct 2026'), findsOneWidget);
    expect(find.text('TODAY -'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsNothing);
    expect(find.text('110'), findsOneWidget);

    // Switching exercise returns the bar to today — the index is an offset
    // into the other exercise's own timeline.
    await tester.tap(find.byKey(const ValueKey('pr-lab-prev-session')));
    await tester.pumpAndSettle();
    expect(find.text('PREVIOUSLY -'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    expect(find.text('Incline Bench Press'), findsOneWidget);
    expect(find.text('20 Oct 2026'), findsOneWidget);
    expect(find.text('TODAY -'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsNothing);
  });

  testWidgets('the flat card stands on the date bar\'s gutter', (tester) async {
    // The alignment is a 402pt-screen fact: page gutter 16 + card inset 6.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PrLabScreen()));
    await tester.pumpAndSettle();

    final selectorPrev = tester.getRect(
      find.byKey(const ValueKey('exercise-selector-prev')),
    );
    final selectorNext = tester.getRect(
      find.byKey(const ValueKey('exercise-selector-next')),
    );
    final datePrev = tester.getRect(
      find.byKey(const ValueKey('pr-lab-prev-session')),
    );
    final dateNext = tester.getRect(
      find.byKey(const ValueKey('pr-lab-next-session')),
    );

    // The card lost its boxes and tightened its inset until its arrows stand
    // on the date bar's own line (2026-10-22).
    expect(selectorPrev.left, 22);
    expect(selectorPrev.left, datePrev.left);
    expect(selectorNext.right, dateNext.right);
    expect(selectorNext.right, 380);

    // The field stands exactly as tall as the arrows flanking it. It used to
    // size to its text (~35), leaving the two 40 boxes standing proud
    // (2026-10-22).
    final field = tester.getRect(
      find.byKey(const ValueKey('exercise-selector-field')),
    );
    expect(field.height, selectorPrev.height);
    expect(field.height, 40);

    // The set rows run the full content width — edge to edge with the
    // arrows, not inset inside a second box.
    final row = tester.getRect(find.byType(PrLabSetRow).first);
    expect(row.left, selectorPrev.left);
    expect(row.right, selectorNext.right);

    // The column labels sit one row-inset in from that gutter, over the
    // rows' number cells.
    expect(
      tester.getRect(find.byKey(const ValueKey('pr-lab-grid-headers'))).left,
      30,
    );
  });

  testWidgets('the grid reads KG then REPS, and variation takes the rest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PrLabScreen()));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.byType(PrLabSetRow).first);
    final kg = tester.getRect(find.byKey(const ValueKey('live-set-1-kg')));
    final reps = tester.getRect(find.byKey(const ValueKey('live-set-1-reps')));

    // Weight, then reps — the order every set is named in, everywhere.
    expect(kg.left, lessThan(reps.left));
    expect(kg.width, closeTo(kPrLabNumCellWidth, 0.01));
    expect(reps.width, closeTo(kPrLabNumCellWidth, 0.01));
    expect(reps.left, closeTo(kg.right + kPrLabCellGap, 0.01));

    // Four digits plus a decimal point, as a real weight is typed —
    // mono-15 is 9pt per character, so "1024.5" is 54pt and must sit
    // inside the cell without scrolling.
    expect(kg.width, greaterThanOrEqualTo(54));
    expect(reps.width, greaterThanOrEqualTo(54));

    // The row's own 1.2 accent border (it is a PR row) insets its content,
    // so the anchor is exact to within that hairline.
    expect(
      kg.left - row.left,
      closeTo(8 + kPrLabNumberCellWidth + kPrLabCellGap, 1.5),
    );

    // The numbers are fixed-width, so variation owns every point left over —
    // 173.6pt of the 358pt row, where the old 1:1:2 split gave it 149.
    expect(row.right - reps.right, greaterThan(185));

    // The header labels sit exactly over the cells they name.
    expect(
      tester.getRect(find.text('KG')).center.dx,
      closeTo(kg.center.dx, 1.5),
    );
    expect(
      tester.getRect(find.text('REPS')).center.dx,
      closeTo(reps.center.dx, 1.5),
    );
  });

  testWidgets('the card is flat unless it is planned or deleted', (
    tester,
  ) async {
    BoxDecoration card() =>
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('pr-lab-exercise-card')),
                )
                .decoration!
            as BoxDecoration;

    await _pumpLab(tester);
    // Freestyle: no fill, no rim — the page ground shows through.
    expect(card().color, isNull);
    expect(card().border, isNull);

    // The trash's faux deleted exercise dresses the active card in the
    // danger rim — the outline-only deleted reading.
    await tester.tap(find.byIcon(Icons.restore_from_trash));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dumbbell Fly'));
    await tester.pumpAndSettle();
    expect(card().color, isNull);
    expect(
      (card().border! as Border).top.color,
      AppColors.danger.withValues(alpha: 0.35),
    );

    // Another exercise leaves the reading behind.
    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    expect(card().border, isNull);
  });

  testWidgets('the pencil sits between the trash and the PRS tile', (
    tester,
  ) async {
    await _pumpLab(tester);

    // One more boxed control in the action bar, the same 48 recipe as the
    // undo/redo pair (2026-10-22).
    final pencil = find.byKey(const ValueKey('pr-lab-ratings-button'));
    expect(
      tester.getSize(pencil),
      const Size(kPrLabBarControlSize, kPrLabBarControlSize),
    );

    final trash = tester.getRect(find.byIcon(Icons.restore_from_trash));
    final prs = tester.getRect(find.byKey(const ValueKey('pr-lab-prs-tile')));
    final pencilRect = tester.getRect(pencil);
    expect(pencilRect.left, greaterThan(trash.right));
    expect(pencilRect.right, lessThan(prs.left));

    // It wears the tiles' orange glass, not the neutral chrome of the
    // undo/redo pair: a door to session content, like the trophy and the
    // book beside it (2026-10-22).
    final box =
        tester
                .widget<Container>(
                  find.descendant(of: pencil, matching: find.byType(Container)),
                )
                .decoration!
            as BoxDecoration;
    expect(box.color, AppColors.accent.withAlpha(26));
    expect((box.border! as Border).top.color, AppColors.accent.withAlpha(77));
    expect(
      tester
          .widget<Icon>(find.descendant(of: pencil, matching: find.byType(Icon)))
          .color,
      AppColors.accent,
    );

    await tester.tap(pencil);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pr-lab-ratings-sheet')), findsOneWidget);
  });

  testWidgets('the header wears a planned chip only for a planned session', (
    tester,
  ) async {
    await _pumpLab(tester);

    // Today's demo is freestyle: the plain title, and nothing around it.
    expect(find.text('Freestyle Session'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-lab-header-plan')), findsNothing);

    // The previous bench session came from a plan, so the header's title is
    // that plan's name in the planned blue on its own blue ground.
    await tester.tap(find.byKey(const ValueKey('pr-lab-prev-session')));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('pr-lab-header-plan'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Push A')),
      findsOneWidget,
    );
    final box = tester.widget<Container>(chip).decoration! as BoxDecoration;
    expect(box.color, AppColors.plannedBg);
    expect(
      (box.border! as Border).top.color,
      AppColors.planned.withValues(alpha: 0.35),
    );
    final name = tester.widget<Text>(
      find.descendant(of: chip, matching: find.byType(Text)),
    );
    expect(name.style?.color, AppColors.planned);
    expect(find.text('Freestyle Session'), findsNothing);

    // Back to today: the chip goes and the plain title returns.
    await tester.tap(find.byKey(const ValueKey('pr-lab-next-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pr-lab-header-plan')), findsNothing);
    expect(find.text('Freestyle Session'), findsOneWidget);
  });

  testWidgets('the ratings sheet carries both bookends, seeded', (
    tester,
  ) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-button')));
    await tester.pumpAndSettle();

    // The workout's name over the title; the date lives in the bar at the
    // foot, where it can be stepped (2026-10-22).
    expect(_inRatings(find.text('FREESTYLE SESSION')), findsOneWidget);
    expect(_inRatings(find.text('Session Ratings')), findsOneWidget);
    expect(_inRatings(find.text('TODAY -')), findsOneWidget);
    expect(_inRatings(find.text('20 Oct 2026')), findsOneWidget);
    expect(_inRatings(find.text('PRE-WORKOUT')), findsOneWidget);
    expect(_inRatings(find.text('POST-WORKOUT')), findsOneWidget);

    // One rating row and one notes field per half, seeded with today's
    // answers — and nothing 10px or muted anywhere in the sheet.
    expect(_inRatings(find.byType(FeelingRating)), findsNWidgets(2));
    expect(_inRatings(find.byType(LambdaInput)), findsNWidgets(2));
    expect(
      tester
          .widget<FeelingRating>(
            find.byKey(const ValueKey('pr-lab-pre-rating')),
          )
          .value,
      4,
    );
    expect(
      tester
          .widget<LambdaInput>(find.byKey(const ValueKey('pr-lab-pre-notes')))
          .controller
          .text,
      'Slept well — feeling strong',
    );
    expect(
      tester
          .widget<LambdaInput>(find.byKey(const ValueKey('pr-lab-post-notes')))
          .controller
          .text,
      'Rushed the last set',
    );
    expectReadableText(tester, find.byKey(const ValueKey('pr-lab-ratings-sheet')));
  });

  testWidgets('the ratings sheet remembers an edit and toggles a star', (
    tester,
  ) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-button')));
    await tester.pumpAndSettle();

    FeelingRating pre() => tester.widget<FeelingRating>(
      find.byKey(const ValueKey('pr-lab-pre-rating')),
    );
    expect(pre().value, 4);

    // The one empty star is the fifth; tapping it raises the rating.
    await tester.tap(
      _inRatings(
        find.descendant(
          of: find.byKey(const ValueKey('pr-lab-pre-rating')),
          matching: find.byIcon(Icons.star_border_rounded),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pre().value, 5);

    await tester.enterText(
      find.byKey(const ValueKey('pr-lab-pre-notes')),
      'Felt strong all morning',
    );
    await tester.pumpAndSettle();

    // Close and reopen: the screen kept what the sheet wrote.
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pr-lab-ratings-sheet')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-button')));
    await tester.pumpAndSettle();
    expect(pre().value, 5);
    expect(
      tester
          .widget<LambdaInput>(find.byKey(const ValueKey('pr-lab-pre-notes')))
          .controller
          .text,
      'Felt strong all morning',
    );

    // Tapping the star that is already selected clears the rating — the
    // wizard pages' own rule.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pr-lab-pre-rating')),
        matching: find.byIcon(Icons.star_rounded),
      ).last,
    );
    await tester.pumpAndSettle();
    expect(pre().value, isNull);
  });

  testWidgets('a past session opens the ratings read-only', (tester) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-prev-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-button')));
    await tester.pumpAndSettle();

    // The sheet reads the session the card behind it is showing, and reads:
    // no field is writable, the notes come back through the readout, the
    // stars are inert.
    expect(find.byKey(const ValueKey('pr-lab-ratings-sheet')), findsOneWidget);
    expect(_inRatings(find.text('PUSH A')), findsOneWidget);
    expect(_inRatings(find.text('PREVIOUSLY -')), findsOneWidget);
    expect(_inRatings(find.text('16 Sep 2026')), findsOneWidget);
    expect(_inRatings(find.byType(LambdaInput)), findsNothing);

    final preNotes = tester.widget<LambdaReadout>(
      find.byKey(const ValueKey('pr-lab-pre-notes')),
    );
    expect(preNotes.value, 'Woke up stiff — shoulders tight');

    final pre = tester.widget<FeelingRating>(
      find.byKey(const ValueKey('pr-lab-pre-rating')),
    );
    expect(pre.value, 3);
    expect(pre.onChanged, isNull);
    expectReadableText(tester, find.byKey(const ValueKey('pr-lab-ratings-sheet')));
  });

  testWidgets('the sheet walks the sessions and the stage follows', (
    tester,
  ) async {
    await _pumpLab(tester);
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-button')));
    await tester.pumpAndSettle();

    // Today: the answers are the reader's to change.
    expect(_inRatings(find.text('TODAY -')), findsOneWidget);
    expect(_inRatings(find.byType(LambdaInput)), findsNWidgets(2));

    // Older: the sheet and the stage's own bar move together, and both
    // sections turn read-only with that session's seeded answers.
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-prev')));
    await tester.pumpAndSettle();
    expect(_inRatings(find.text('PREVIOUSLY -')), findsOneWidget);
    expect(_inRatings(find.text('16 Sep 2026')), findsOneWidget);
    expect(_inRatings(find.byType(LambdaInput)), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('pr-lab-session-state')))
          .data,
      'PREVIOUSLY -',
    );

    // Back to today: editable again, and the stage returned with it.
    await tester.tap(find.byKey(const ValueKey('pr-lab-ratings-next')));
    await tester.pumpAndSettle();
    expect(_inRatings(find.text('TODAY -')), findsOneWidget);
    expect(_inRatings(find.byType(LambdaInput)), findsNWidgets(2));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('pr-lab-session-state')))
          .data,
      'TODAY -',
    );
  });

  testWidgets('a swipe arrives one circle at a time, with no fade', (
    tester,
  ) async {
    // The drawer on its own, full size — three actions, the set row's shape.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 52,
              child: PrLabSwipeActions(
                actions: [
                  PrLabSwipeAction(
                    icon: Icons.copy_rounded,
                    color: AppColors.accent,
                    foreground: AppColors.accentText,
                    onTap: () {},
                  ),
                  PrLabSwipeAction(
                    icon: Icons.sticky_note_2_outlined,
                    color: AppColors.primary,
                    foreground: AppColors.bg,
                    onTap: () {},
                  ),
                  PrLabSwipeAction(
                    icon: Icons.delete_outline,
                    color: AppColors.danger,
                    foreground: AppColors.dangerText,
                    onTap: () {},
                  ),
                ],
                child: Container(color: AppColors.surfaceHigh),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The x-scale, not `getMaxScaleOnAxis()`: `Transform.scale` leaves the z
    // axis at 1, which would make every circle measure 1 whatever its size.
    double scaleOf(IconData icon) => tester
        .widget<Transform>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Transform))
              .first,
        )
        .transform
        .entry(0, 0);

    // Closed: every circle is at zero, and nothing anywhere in the drawer
    // fades — the arrival is scale and only scale (2026-10-22).
    for (final icon in [
      Icons.copy_rounded,
      Icons.sticky_note_2_outlined,
      Icons.delete_outline,
    ]) {
      expect(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(scaleOf(icon), 0);
    }

    // Circles, not blocks — the action is a filled disc inside its slot.
    final disc =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.byIcon(Icons.delete_outline),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(disc.shape, BoxShape.circle);
    expect(disc.color, AppColors.danger);

    // The drawer opens from the trailing edge, so the delete circle arrives
    // over the first slot-width of travel while the other two wait at zero.
    // 52 is the slot width the drawer measures in (three circles, 12 apart).
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PrLabSwipeActions)),
    );
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(Icons.delete_outline), greaterThan(0.9));
    expect(scaleOf(Icons.sticky_note_2_outlined), 0);
    expect(scaleOf(Icons.copy_rounded), 0);

    // Second slot-width: the note circle's turn, copy still waiting.
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(Icons.sticky_note_2_outlined), greaterThan(0.9));
    expect(scaleOf(Icons.copy_rounded), 0);

    // Third: copy lands, all three seated in list order.
    await gesture.moveBy(const Offset(-52, 0));
    await tester.pump();
    expect(scaleOf(Icons.copy_rounded), greaterThan(0.9));
    await gesture.up();
    await tester.pumpAndSettle();

    // Fully open (every circle at scale 1, so positions are their laid-out
    // ones): one slot — 52 — between neighbouring circle centres, which
    // leaves 12 between 40 discs. The first draft's 64 left 24 and read as
    // three separate controls rather than one cluster (2026-10-22).
    final copyX = tester.getCenter(find.byIcon(Icons.copy_rounded)).dx;
    final noteX = tester
        .getCenter(find.byIcon(Icons.sticky_note_2_outlined))
        .dx;
    final deleteX = tester.getCenter(find.byIcon(Icons.delete_outline)).dx;
    expect(noteX - copyX, 52);
    expect(deleteX - noteX, 52);
  });

  testWidgets('the note circle is hollow until the set has a note', (
    tester,
  ) async {
    Widget harness({required bool filled}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 52,
            child: PrLabSwipeActions(
              actions: [
                PrLabSwipeAction(
                  icon: Icons.sticky_note_2_outlined,
                  color: AppColors.primary,
                  foreground: AppColors.bg,
                  filled: filled,
                  onTap: () {},
                ),
              ],
              child: Container(color: AppColors.surfaceHigh),
            ),
          ),
        ),
      ),
    );

    BoxDecoration discOf() =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.byIcon(Icons.sticky_note_2_outlined),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    Color glyphOf() => tester
        .widget<Icon>(find.byIcon(Icons.sticky_note_2_outlined))
        .color!;

    // No note: the fill is empty — the page ground shows through a ring, and
    // the glyph takes the ring's colour so it stays readable on that ground.
    await tester.pumpWidget(harness(filled: false));
    expect(discOf().color, Colors.transparent);
    expect(discOf().border!.top.color, AppColors.primary);
    expect(glyphOf(), AppColors.primary);

    // A note exists: the circle fills, and the glyph flips to the dark ink
    // that reads on the cream.
    await tester.pumpWidget(harness(filled: true));
    expect(discOf().color, AppColors.primary);
    expect(discOf().border, isNull);
    expect(glyphOf(), AppColors.bg);
  });

  testWidgets('saving a note from the row fills its circle', (tester) async {
    await _pumpLab(tester);

    final firstRow = find.byType(PrLabSetRow).first;
    final noteIcon = find.descendant(
      of: firstRow,
      matching: find.byIcon(Icons.sticky_note_2_outlined),
    );
    final disc = find
        .ancestor(of: noteIcon, matching: find.byType(Container))
        .first;
    BoxDecoration discDecoration() =>
        tester.widget<Container>(disc).decoration! as BoxDecoration;

    // At rest the set has no note: the circle is a ring, not a fill.
    expect(discDecoration().color, Colors.transparent);

    // Swipe the row out and tap Note — the shared sheet opens over the lab.
    // The drag starts on the row's leading cell: a text cell captures its own
    // horizontal pan for cursor placement, but the index cell is inert.
    final rowRect = tester.getRect(firstRow);
    final swipe = await tester.startGesture(
      Offset(rowRect.left + 8, rowRect.center.dy),
    );
    await swipe.moveBy(const Offset(-160, 0));
    await tester.pump();
    await swipe.up();
    await tester.pumpAndSettle();
    await tester.tap(noteIcon);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Set 1 Notes')),
      findsOneWidget,
    );

    // Type and save: the screen keeps the note, and the circle it belongs to
    // fills — a ring said "no note yet", the fill says there is one.
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(LambdaInput)),
      'Elbow tucked, bar path clean',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: sheet, matching: find.byIcon(Icons.check)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    expect(discDecoration().color, AppColors.primary);
    expect(discDecoration().border, isNull);
  });

  testWidgets('opening one drawer closes the one already open', (tester) async {
    Widget row(String key, IconData icon) => SizedBox(
      key: ValueKey(key),
      width: 320,
      height: 52,
      child: PrLabSwipeActions(
        actions: [
          PrLabSwipeAction(
            icon: icon,
            color: AppColors.danger,
            foreground: AppColors.dangerText,
            onTap: () {},
          ),
        ],
        child: Container(color: AppColors.surfaceHigh),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row('row-a', Icons.delete_outline),
                const SizedBox(height: 12),
                row('row-b', Icons.flag),
              ],
            ),
          ),
        ),
      ),
    );

    double scaleOf(IconData icon) => tester
        .widget<Transform>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Transform))
              .first,
        )
        .transform
        .entry(0, 0);

    // Open the first row.
    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-a'))),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(Icons.delete_outline), 1);

    // Swiping the second row hands the stage over: the first goes back.
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-b'))),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(Icons.flag), 1);
    expect(scaleOf(Icons.delete_outline), 0);
  });

  testWidgets('a tap anywhere but the action circles puts the row back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 52,
              child: PrLabSwipeActions(
                actions: [
                  PrLabSwipeAction(
                    icon: Icons.delete_outline,
                    color: AppColors.danger,
                    foreground: AppColors.dangerText,
                    onTap: () {},
                  ),
                ],
                child: Container(color: AppColors.surfaceHigh),
              ),
            ),
          ),
        ),
      ),
    );

    double scaleOf(IconData icon) => tester
        .widget<Transform>(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Transform))
              .first,
        )
        .transform
        .entry(0, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PrLabSwipeActions)),
    );
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(Icons.delete_outline), 1);

    // A tap on the page, away from the row — the drawer was open and the
    // release travelled nowhere, so it counts as a tap and the row goes back.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(scaleOf(Icons.delete_outline), 0);
  });
}
