import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';

/// A group's name inside the session sheets (2026-10-22) — centred between
/// two hairlines, so the break between groups reads as a rule across the
/// sheet with the name set into it.
///
/// The PR History sheet and the Notes modal both split their feed into
/// what the session on the desk added and what came before it, and both say
/// so with this one widget. The label is the header's own mono caps,
/// tracked, and white like a title rather than a muted caption, so the two
/// sheets' breaks read at the same weight.
class SheetSectionLabel extends StatelessWidget {
  const SheetSectionLabel(this.label, {super.key});

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
