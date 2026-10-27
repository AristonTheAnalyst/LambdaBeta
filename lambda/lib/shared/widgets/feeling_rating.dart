import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';

/// The 1–5 feeling rating used by the session flow and the logs detail
/// screen — one implementation so a feeling rating looks identical
/// everywhere. Five tappable stars, filled cumulatively up to [value]
/// (interactive and read-only alike); the ViewModel toggles selection off
/// when the same star is tapped again.
///
/// **The stars wear the read/edit rule (2026-10-28).** Framed (the default),
/// the row stands in a pill whose rim never moves: glass while the stars
/// take a tap, hollow while they only read — the same one-border rule as the
/// text boxes, so a section that flips modes changes its fills and nothing
/// else. The pill hugs the stars and centres itself, so the row keeps the
/// section's centred seat. `framed: false` is the glance: the 14px stars
/// summarizing pre/post inside a log card, where the row is data being
/// scanned, not a control.
class FeelingRating extends StatelessWidget {
  const FeelingRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 52,
    this.label,
    this.spacing = 8,
    this.framed = true,
  });

  /// 1–5, or null when nothing is selected.
  final int? value;

  /// Tap handler; null renders read-only.
  final void Function(int n)? onChanged;

  /// Star icon size.
  final double size;

  /// Optional muted label rendered left of the stars.
  final String? label;

  final double spacing;

  /// Whether the row wears the control's pill — the read/edit chrome. True
  /// everywhere a rating is shown or taken as its own section; false for the
  /// inline summary stars that ride a data row.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: framed ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: label == null
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppFonts.ui(
              fontSize: AppTextStyles.caption,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(width: 4),
        ],
        for (var n = 1; n <= 5; n++)
          _star(
            n,
            // Cumulative in both modes — tapping star 4 fills 1–4.
            selected: (value ?? 0) >= n,
            isLast: n == 5,
          ),
      ],
    );
    if (!framed) return row;
    // One rim in both modes; the tint is the only thing the state moves.
    // The pill spends 24pt more than the bare row, and five 52pt stars
    // already fill a phone's bookend gutter — so on a tight ground the
    // stars scale down inside the pill instead of overflowing it (the date
    // bar's own FittedBox answer, 2026-10-28).
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: glassBox(
          AppColors.primary,
          radius: 999,
          filled: onChanged != null,
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: row),
      ),
    );
  }

  Widget _star(int n, {required bool selected, required bool isLast}) {
    final star = Icon(
      selected ? Icons.star_rounded : Icons.star_border_rounded,
      size: size,
      // Filled stars carry the ink color — ratings are not PRs, so the
      // accent stays reserved.
      color: selected ? AppColors.primary : AppColors.muted,
    );
    final padded = Padding(
      padding: EdgeInsets.only(right: isLast ? 0 : spacing),
      child: star,
    );
    if (onChanged == null) return padded;
    return GestureDetector(onTap: () => onChanged!(n), child: padded);
  }
}
