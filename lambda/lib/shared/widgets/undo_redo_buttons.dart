import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import './bar_icon_button.dart';
import './container_styles.dart';
import './menu_popover.dart';

/// The undo/redo pair (2026-10-13) — the `_pagerButton` recipe (session
/// screen), promoted and paired: square boxes with the undo/redo glyphs.
/// Enabled wears the glass treatment; disabled goes transparent with a
/// hairline border and a muted icon, and still claims its tap (a dead spot
/// in a bar is a hole in the layout).
///
/// The trash slot rides along only when the caller hands it one — the live
/// session's stats bar restores from it directly; a screen whose trash
/// should stand on its own (the past-session viewer's view-mode header)
/// draws [DeletedExercisesButton] by itself.
class UndoRedoButtons extends StatelessWidget {
  const UndoRedoButtons({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.deletedExercises = const [],
    this.onPickDeletedExercise,
    this.compact = false,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// The trash slot (2026-10-13) — the deleted exercises: the glyph opens a
  /// menu of them, one row per name, and the row tapped fires
  /// [onPickDeletedExercise] with its index. What the pick MEANS is the
  /// caller's: the live session restores; the past-session viewer views (its
  /// Restore is a button under the card).
  final List<String> deletedExercises;
  final void Function(int index)? onPickDeletedExercise;

  final bool compact;

  // The square bar control is one shared recipe ([BarIconButton]) — the
  // pencil and the trash draw from it too (2026-10-22).
  Widget _button(
    IconData icon,
    String semanticsLabel,
    bool enabled,
    VoidCallback onTap,
  ) => BarIconButton(
    icon: icon,
    semanticsLabel: semanticsLabel,
    onPressed: onTap,
    enabled: enabled,
    compact: compact,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(LucideIcons.undo2, 'Undo', canUndo, onUndo),
        const SizedBox(width: AppSpacing.xs),
        _button(LucideIcons.redo2, 'Redo', canRedo, onRedo),
        if (onPickDeletedExercise != null) ...[
          const SizedBox(width: AppSpacing.xs),
          DeletedExercisesButton(
            deletedExercises: deletedExercises,
            onPickDeletedExercise: onPickDeletedExercise!,
            compact: compact,
            // The rows open the deleted exercise for READING (the live
            // stats bar's view-then-restore flow, 2026-10-14) — the eye
            // says what a tap does.
            rowIcon: LucideIcons.eye,
            semanticsLabel: 'Deleted exercises',
          ),
        ],
      ],
    );
  }
}

/// The trash slot on its own (2026-10-14): a menu of the deleted exercises
/// while there is something in it, a plain greyed button while there is not.
/// The swap matters when the last entry leaves the open menu — the panel's
/// portal goes with the widget, so the menu closes itself rather than
/// hanging there empty.
///
/// Both deleted-exercise surfaces draw it: the live session's stats bar
/// (inside [UndoRedoButtons], a tap restores) and the past-session viewer's
/// header in BOTH modes (a tap views — [rowIcon] wears the eye there).
class DeletedExercisesButton extends StatelessWidget {
  const DeletedExercisesButton({
    super.key,
    required this.deletedExercises,
    required this.onPickDeletedExercise,
    this.rowIcon = LucideIcons.rotateCcw,
    this.semanticsLabel = 'Deleted exercises',
    this.compact = false,
  });

  final List<String> deletedExercises;
  final void Function(int index) onPickDeletedExercise;

  /// The glyph on each menu row — what a tap does on this screen.
  final IconData rowIcon;
  final String semanticsLabel;

  final bool compact;

  Widget _button(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
    String? semanticsLabel,
  }) => BarIconButton(
    icon: icon,
    semanticsLabel: semanticsLabel ?? this.semanticsLabel,
    onPressed: onTap,
    enabled: enabled,
    compact: compact,
  );

  @override
  Widget build(BuildContext context) {
    if (deletedExercises.isEmpty) {
      // Lit while there is something to work through, grey while not. The
      // label is stated here because this branch has no [MenuPopover] to
      // carry one; the open branch would otherwise announce twice.
      return _button(
        LucideIcons.rotateCcw,
        false,
        () {},
        semanticsLabel: semanticsLabel,
      );
    }
    // The panel opens left-aligned ([MenuPopoverAlign.start]): this button
    // stands at the row's start, a thumb's width from the screen's left
    // edge, where a right-aligned panel would hang half off the screen.
    return MenuPopover(
      align: MenuPopoverAlign.start,
      semanticsLabel: semanticsLabel,
      trigger: (context, open) => _button(LucideIcons.rotateCcw, true, open),
      contentBuilder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < deletedExercises.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            // No dismiss on tap: the menu is a list to work down, not a
            // question to answer once — taking one leaves the rest on
            // screen, and it closes itself when the last one goes.
            DeletedExerciseRow(
              name: deletedExercises[i],
              icon: rowIcon,
              onTap: () => onPickDeletedExercise(i),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of the deleted-exercises menu: the exercise's name, with a glyph
/// saying what a tap does on this screen. The row's own chrome matches
/// [ChoiceRow] at rest — the same glass and padding — but wears no tick:
/// nothing here is "chosen", the tap acts.
class DeletedExerciseRow extends StatelessWidget {
  const DeletedExerciseRow({
    super.key,
    required this.name,
    this.icon = LucideIcons.rotateCcw,
    required this.onTap,
  });

  final String name;
  final IconData icon;
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
            Icon(icon, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
