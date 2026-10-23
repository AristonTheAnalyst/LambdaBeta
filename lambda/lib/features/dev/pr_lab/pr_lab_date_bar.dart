// LAB COPY — the /dev/pr-lab layout sandbox's own date changer. Never import
// this from a production screen. Edit freely: nothing here can reach the real
// session, planner, logs or PR History demo (2026-10-22).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/container_styles.dart';
import 'pr_lab_exercise_selector.dart';
import 'pr_lab_header_icon_button.dart';

/// The five keys one drawn date bar wears.
///
/// The bar is one control drawn in two places — the stage's floor and the
/// ratings sheet — and both are on screen at once, so each needs its own
/// names. Bundling them keeps the widget's other six arguments readable.
class PrLabDateBarKeys {
  const PrLabDateBarKeys({
    required this.bar,
    required this.older,
    required this.newer,
    required this.state,
    required this.date,
  });

  /// The stage's own bar, at the floor above the action row.
  static const session = PrLabDateBarKeys(
    bar: ValueKey('pr-lab-session-date-bar'),
    older: ValueKey('pr-lab-prev-session'),
    newer: ValueKey('pr-lab-next-session'),
    state: ValueKey('pr-lab-session-state'),
    date: ValueKey('pr-lab-session-date'),
  );

  /// The same bar, drawn inside the ratings sheet (2026-10-22).
  static const ratings = PrLabDateBarKeys(
    bar: ValueKey('pr-lab-ratings-date-bar'),
    older: ValueKey('pr-lab-ratings-prev'),
    newer: ValueKey('pr-lab-ratings-next'),
    state: ValueKey('pr-lab-ratings-state'),
    date: ValueKey('pr-lab-ratings-date'),
  );

  final Key bar;
  final Key older;
  final Key newer;
  final Key state;
  final Key date;
}

/// The date changer: the session on the desk, centred between the arrows
/// that walk the exercise's timeline — one arrow on either side, so the
/// phrase sits in the middle of the bar rather than in whatever room the
/// arrows leave (2026-10-21).
///
/// Left walks back through the timeline (older), right returns toward today.
/// The ends are inert — a control that disappears shifts everything beside
/// it, so a spent arrow greys instead.
///
/// The stage pins it at the floor; the ratings sheet pins it under its two
/// bookends. One widget, so the two read as the same control (2026-10-22).
class PrLabDateBar extends StatelessWidget {
  const PrLabDateBar({
    super.key,
    required this.keys,
    required this.isToday,
    required this.date,
    required this.canGoOlder,
    required this.canGoNewer,
    required this.onOlder,
    required this.onNewer,
  });

  final PrLabDateBarKeys keys;

  /// Whether the phrase leads with TODAY (the live session) or PREVIOUSLY
  /// (a recorded one the reader has walked onto).
  final bool isToday;

  final DateTime date;
  final bool canGoOlder;
  final bool canGoNewer;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: keys.bar,
      // One inset all round — an arrow stands at each edge. 5, not 6: the
      // hairline is part of the inset, so the arrows land 6 from the bar's
      // outer edge — the same 6 the card's content stands from the page
      // gutter, which is what put the two chevron pairs on one line
      // (2026-10-22).
      padding: const EdgeInsets.all(5),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Row(
        children: [
          PrLabHeaderIconButton(
            key: keys.older,
            icon: Icons.chevron_left,
            semanticsLabel: 'Previous workout',
            // One chevron recipe for the stage: the selector's flanks and
            // these two arrows share the 40 target, the 24 glyph and the 6
            // corner (2026-10-21).
            glyphSize: kPrLabSelectorArrowGlyph,
            variant: PrLabHeaderIconVariant.boxed,
            boxSize: kPrLabSelectorArrowSize,
            radius: kPrLabSelectorArrowRadius,
            color: AppColors.primary,
            onPressed: canGoOlder ? onOlder : null,
          ),
          const SizedBox(width: AppSpacing.xs),
          // The session's state leads — "TODAY -" while the live session is
          // on the desk, "PREVIOUSLY -" once the reader has walked onto an
          // older workout — then the date it names. Centred between the
          // arrows, which stand at both edges at one size, so the phrase
          // lands on the bar's own middle. Scale-to-fit so a narrow stage
          // narrows the line rather than overflowing it.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? 'TODAY -' : 'PREVIOUSLY -',
                    key: keys.state,
                    style: AppFonts.mono(
                      // The date's own size: the state and the date it names
                      // are one line read as one phrase (2026-10-21).
                      fontSize: 12.8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      // Both states are read, so both wear readable ink; the
                      // accent marks the live session, not the only legible
                      // reading (2026-10-22 — the sheet's readability guard
                      // caught the old decorative `muted`).
                      color: isToday
                          ? AppColors.accent
                          : AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('d MMM yyyy').format(date),
                    key: keys.date,
                    style: AppFonts.mono(
                      fontSize: 12.8,
                      letterSpacing: 0.6,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          PrLabHeaderIconButton(
            key: keys.newer,
            icon: Icons.chevron_right,
            semanticsLabel: 'Next workout',
            glyphSize: kPrLabSelectorArrowGlyph,
            variant: PrLabHeaderIconVariant.boxed,
            boxSize: kPrLabSelectorArrowSize,
            radius: kPrLabSelectorArrowRadius,
            color: AppColors.primary,
            onPressed: canGoNewer ? onNewer : null,
          ),
        ],
      ),
    );
  }
}
