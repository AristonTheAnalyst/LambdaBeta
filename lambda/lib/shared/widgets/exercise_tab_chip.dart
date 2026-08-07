import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';

/// A pill-chip tab for the exercise tab bar. Used by both the session screen
/// and the planned-workout screen.
class ExerciseTabChip extends StatelessWidget {
  const ExerciseTabChip({
    super.key,
    required this.label,
    required this.isActive,
    this.count,
    this.prefixIcon,
    this.activeColor,
    required this.onTap,
    this.onRemove,
  });

  final String label;
  final bool isActive;
  final int? count;
  final IconData? prefixIcon;

  /// The active-pill color — defaults to the accent orange, but the planner
  /// passes green so its planned-exercise pills read as "planned".
  final Color? activeColor;
  final VoidCallback onTap;

  /// When non-null a small close icon appears at the right edge of the pill.
  /// Tapping it (not the main label area) calls this callback — the caller
  /// should present a confirmation dialog if needed.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 10, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: isActive ? color : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prefixIcon != null) ...[
              Icon(prefixIcon, size: 11, color: color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: AppFonts.ui(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? color : AppColors.primary)),
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close, size: 13, color: isActive ? color : AppColors.border),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "+" add-exercise button that sits at the end of the tab bar row.
class AddExerciseButton extends StatelessWidget {
  const AddExerciseButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(Icons.add, size: 16, color: AppColors.muted),
      ),
    );
  }
}
