import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';

/// The 1–5 feeling rating used by the session flow and the logs detail
/// screen — one implementation so a feeling rating looks identical
/// everywhere. Five tappable stars, filled cumulatively up to [value]
/// (interactive and read-only alike); the ViewModel toggles selection off
/// when the same star is tapped again.
class FeelingRating extends StatelessWidget {
  const FeelingRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 52,
    this.label,
    this.spacing = 8,
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: label == null
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppFonts.ui(fontSize: 13, color: AppColors.muted),
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
