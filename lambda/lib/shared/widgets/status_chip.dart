import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';

/// The small pill that labels what a program is doing — "Active", "Paused", a
/// due prompt.
///
/// One widget for all of them because they are the same object with different
/// words: a paused badge that looked unlike an active one would read as a
/// different kind of thing rather than the same thing in another state. The
/// [muted] tone is the whole distinction — accent for "this is where you are",
/// muted for "this is waiting" — and it is a tone rather than a colour so a
/// caller cannot invent a third look.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.muted = false,
  });

  final String label;
  final IconData? icon;

  /// Neutral styling for a state that is not the active one. Paused is not a
  /// lesser active — it is simply not running, and it should not compete with
  /// the program that is.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final fg = muted ? AppColors.muted : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.surfaceHigh : AppColors.accentBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted ? AppColors.border : fg.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppFonts.ui(
              fontSize: 14,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
