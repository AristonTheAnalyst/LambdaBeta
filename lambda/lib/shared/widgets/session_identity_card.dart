import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';

/// The past-session viewer's session identity card — the training page's
/// template-card styling made static (no tap, no swap icon). A planned
/// session gets the planned fill + outline with its name; a freestyle
/// session renders the neutral identity card.
class SessionIdentityCard extends StatelessWidget {
  const SessionIdentityCard({super.key, required this.plannedName});

  final String? plannedName;

  @override
  Widget build(BuildContext context) {
    final planned = plannedName != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // Mirrors the template selector card: plannedBg fill + planned
        // outline when planned, plain surface + hairline otherwise.
        color: planned ? AppColors.plannedBg : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: planned
              ? AppColors.planned.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: planned
          // One line only — the session's name (or the no-plan note) sits
          // directly in the card, no kicker line, so the card stays short.
          ? Text(
              plannedName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            )
          : Text(
              'No planned session',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: 14,
                color: AppColors.muted,
              ),
            ),
    );
  }
}
