// LAB COPY — the /dev/pr-lab layout sandbox's own widget. Never import this
// from a production screen. Edit freely: nothing here can reach the real
// session, planner, logs or PR History demo (2026-10-21).

import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';

/// A group's name inside the lab's sheets — centred between two white
/// hairlines, so the break between groups reads as a rule across the sheet
/// with the name set into it (2026-10-21).
///
/// The header says where you are (`BENCH PRESS` over `PR History`); this says
/// which part of it you are reading (`THIS SESSION` over its entries). The
/// label is the header's own mono caps, tracked — and white like the header's
/// title, not a muted caption, so the two sheets' breaks read at the same
/// weight.
class PrLabSectionLabel extends StatelessWidget {
  const PrLabSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _Rule()),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label.toUpperCase(),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(child: _Rule()),
      ],
    );
  }
}

/// The half-rule on either side of a section's name.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: AppColors.primary);
}
