import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// One workout's note inside an open review — what was said about the workout
/// as a whole, rather than about one lift inside it.
///
/// A sheet, where an exercise's note is a box on its card: a workout has no
/// single card to sit on, so the way in is the review bar's Note button. The
/// contract is the same either way: the note belongs to the PASS, it rides
/// the review's record (never the dim row), and it is written as it is taken
/// rather than held until Finish — a review can stay open for days, and a
/// note typed on the first look must survive leaving the screen.
///
/// Returns the note — possibly empty, which CLEARS it — or null when the sheet
/// was dismissed. The caller must not treat those the same: one writes, the
/// other changes nothing.
Future<String?> showReviewWorkoutNoteSheet(
  BuildContext context, {
  required String workoutName,
  required String initialValue,
}) =>
    showLambdaModal<String>(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _ReviewWorkoutNoteSheet(
        workoutName: workoutName,
        initialValue: initialValue,
      ),
    );

class _ReviewWorkoutNoteSheet extends StatefulWidget {
  const _ReviewWorkoutNoteSheet({
    required this.workoutName,
    required this.initialValue,
  });

  final String workoutName;
  final String initialValue;

  @override
  State<_ReviewWorkoutNoteSheet> createState() =>
      _ReviewWorkoutNoteSheetState();
}

class _ReviewWorkoutNoteSheetState extends State<_ReviewWorkoutNoteSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialValue,
  );

  // The field takes focus on the first frame — the sheet exists to take a
  // note, so keyboard-up is the state it should open in.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The Save button's enabled state is derived from the text, so the field
    // has to repaint the header as the user types.
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasNote => widget.initialValue.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Review note',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GlassButton(
                  label: 'Save',
                  compact: true,
                  // Nothing to write until the text differs from what the
                  // sheet opened with — a Save that saves nothing is a button
                  // telling a small lie.
                  disabled: _ctrl.text.trim() == widget.initialValue.trim(),
                  onPressed: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop(_ctrl.text.trim()),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Which workout this is about. The sheet floats over the workout
            // it came from, but a note is a claim about ONE workout and the
            // header has to be able to say whose.
            Text(
              widget.workoutName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LambdaInput(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              placeholder: 'What this workout is for, or what you changed and '
                  'why…',
              // The sheet's default background is a surface ground.
              elevated: true,
            ),
            if (_hasNote) ...[
              const SizedBox(height: AppSpacing.md),
              GlassButton(
                label: 'Delete note',
                color: AppColors.danger,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(''),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
