// LAB COPY — the /dev/pr-lab layout sandbox's own planned-session chip.
// Never import this from a production screen. Edit freely: nothing here can
// reach the real session, planner, logs or PR History demo (2026-10-22).

import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/user_name_text.dart';

/// The session's planned name in the page header — the planned blue on its
/// own blue ground (2026-10-22).
///
/// It is the header's title when the session on the desk came from a
/// template, and **nothing at all** when the session is freestyle: a
/// freestyle session keeps the plain title, with no chip around it. The
/// recipe is the planned token pair ([ContainerTone.planned]), the same blue
/// a planned card wears — the chip names the plan the session followed
/// without borrowing the danger chrome or a second accent.
///
/// The type is the header title's own — `AppFonts.ui` at
/// [AppTextStyles.lg] w600 — recolored to planned. The chip changes the
/// ground, never the type: swapping to a mono eyebrow made the header read
/// as a label rather than the page's name (2026-10-22).
class PrLabPlannedNameChip extends StatelessWidget {
  const PrLabPlannedNameChip({super.key, required this.name});

  /// The plan's name as the user typed it — `UserNameText` ellipsizes it and
  /// keeps it one line, however long.
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pr-lab-header-plan'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: lambdaBox(ContainerTone.planned, radius: AppRadius.md),
      child: UserNameText(
        name,
        tooltip: true,
        style: AppFonts.ui(
          fontSize: AppTextStyles.lg,
          fontWeight: FontWeight.w600,
          color: AppColors.planned,
        ),
      ),
    );
  }
}
