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
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final int? count;
  final IconData? prefixIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentBg : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prefixIcon != null) ...[
              Icon(prefixIcon, size: 11, color: AppColors.accent),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: AppFonts.ui(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppColors.accent : AppColors.primary)),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count', style: AppFonts.mono(fontSize: 10, color: AppColors.accent)),
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
