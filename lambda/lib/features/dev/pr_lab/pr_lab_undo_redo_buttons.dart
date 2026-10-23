// LAB COPY — the /dev/pr-lab layout sandbox's own copy of a shared
// widget. Never import this from a production screen. Edit freely: nothing
// here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/menu_popover.dart';

/// The lab bar's square control: 48 box around a 24px glyph — the nav bar's
/// own icon size (2026-10-21). The shared pair draws 36/32 boxes, which the
/// rehauled action bar reads as too small to hit, so the recipe is copied
/// here at one larger size rather than growing a size knob on the original.
const double kPrLabBarControlSize = 48;

/// The lab's undo/redo pair, plus the deleted-exercises trash slot.
///
/// Same recipe as the shared `UndoRedoButtons` — enabled wears the glass,
/// disabled a hairline and a muted glyph, every button keeps its tap — at
/// [kPrLabBarControlSize]. The trash rides along whenever the caller hands it
/// a pick callback; with nothing deleted it draws greyed, exactly the live
/// bar's empty state.
class PrLabUndoRedoButtons extends StatelessWidget {
  const PrLabUndoRedoButtons({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.deletedExercises = const [],
    this.onPickDeletedExercise,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  final List<String> deletedExercises;
  final void Function(int index)? onPickDeletedExercise;

  Widget _button(
    IconData icon,
    String semanticsLabel,
    bool enabled,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : () {},
        child: Container(
          width: kPrLabBarControlSize,
          height: kPrLabBarControlSize,
          alignment: Alignment.center,
          decoration: enabled
              ? glassBox(AppColors.primary, radius: AppRadius.md)
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Icon(
            icon,
            size: 24,
            color: enabled ? AppColors.primary : AppColors.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.undo, 'Undo', canUndo, onUndo),
        const SizedBox(width: AppSpacing.xs),
        _button(Icons.redo, 'Redo', canRedo, onRedo),
        if (onPickDeletedExercise != null) ...[
          const SizedBox(width: AppSpacing.xs),
          PrLabDeletedExercisesButton(
            deletedExercises: deletedExercises,
            onPickDeletedExercise: onPickDeletedExercise!,
          ),
        ],
      ],
    );
  }
}

/// The trash slot on its own: a menu of the deleted exercises while there is
/// something in it, a plain greyed button while there is not.
class PrLabDeletedExercisesButton extends StatelessWidget {
  const PrLabDeletedExercisesButton({
    super.key,
    required this.deletedExercises,
    required this.onPickDeletedExercise,
  });

  final List<String> deletedExercises;
  final void Function(int index) onPickDeletedExercise;

  Widget _button(bool enabled, VoidCallback onTap) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Deleted exercises',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : () {},
        child: Container(
          width: kPrLabBarControlSize,
          height: kPrLabBarControlSize,
          alignment: Alignment.center,
          decoration: enabled
              ? glassBox(AppColors.primary, radius: AppRadius.md)
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Icon(
            Icons.restore_from_trash,
            size: 24,
            color: enabled ? AppColors.primary : AppColors.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (deletedExercises.isEmpty) return _button(false, () {});
    return MenuPopover(
      align: MenuPopoverAlign.start,
      semanticsLabel: 'Deleted exercises',
      trigger: (context, open) => _button(true, open),
      contentBuilder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < deletedExercises.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            PrLabDeletedExerciseRow(
              name: deletedExercises[i],
              // The lab has nothing to restore or view — the tap answers by
              // closing the menu, so the row is never a dead press.
              onTap: () {
                onPickDeletedExercise(i);
                dismiss();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of the deleted-exercises menu: the exercise's name and the eye,
/// the live bar's reading.
class PrLabDeletedExerciseRow extends StatelessWidget {
  const PrLabDeletedExerciseRow({
    super.key,
    required this.name,
    required this.onTap,
  });

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: glassBox(AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.visibility_outlined, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
