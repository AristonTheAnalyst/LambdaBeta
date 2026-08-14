import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';

/// The 1–5 feeling rating used by the session flow and the logs detail screen —
/// one implementation so a feeling rating looks identical everywhere.
///
/// Interactive ([onChanged] non-null) highlights exactly the tapped square
/// (the ViewModel toggles selection off when the same square is tapped again);
/// read-only fills cumulatively up to [value] (how a past rating is displayed).
class FeelingRating extends StatelessWidget {
  const FeelingRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 52,
    this.label,
    this.radius = 8,
    this.spacing = 8,
    this.textSize = 14,
  });

  /// 1–5, or null when nothing is selected.
  final int? value;

  /// Tap handler; null renders read-only.
  final void Function(int n)? onChanged;

  /// Square width/height.
  final double size;

  /// Optional muted label rendered left of the squares.
  final String? label;

  final double radius;
  final double spacing;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final readOnly = onChanged == null;
    return Row(
      mainAxisAlignment:
          label == null ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
          const SizedBox(width: 4),
        ],
        for (var n = 1; n <= 5; n++)
          _square(
            n,
            selected: readOnly ? (value ?? 0) >= n : value == n,
            isLast: n == 5,
          ),
      ],
    );
  }

  Widget _square(int n, {required bool selected, required bool isLast}) {
    final square = Container(
      width: size,
      height: size,
      margin: EdgeInsets.only(right: isLast ? 0 : spacing),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: selected ? AppColors.accent : AppColors.border),
      ),
      child: Center(
        child: Text('$n',
            style: AppFonts.ui(
                fontSize: textSize,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.accentText : AppColors.primary)),
      ),
    );
    if (onChanged == null) return square;
    return GestureDetector(onTap: () => onChanged!(n), child: square);
  }
}
