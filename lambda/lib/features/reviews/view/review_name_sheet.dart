import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// What the pass is called — the first question the + button asks.
///
/// Name first, then what to review: the name is how the pass is found
/// afterwards, and asking it up front lets the selection screen carry it as its
/// title, so the set is picked under the name it will be filed as. Required
/// here — Next stays disabled until there is one — because an unnamed review
/// falls back to a run of workout names in the list, which is not what a review
/// is for.
///
/// Returns the trimmed name, or null when the sheet was dismissed.
Future<String?> showReviewNameSheet(BuildContext context) =>
    showLambdaModal<String>(
      context,
      fitContent: true,
      keyboardAware: true,
      child: const _ReviewNameSheet(),
    );

class _ReviewNameSheet extends StatefulWidget {
  const _ReviewNameSheet();

  @override
  State<_ReviewNameSheet> createState() => _ReviewNameSheetState();
}

class _ReviewNameSheetState extends State<_ReviewNameSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The Next button's enabled state is derived from the text, so the header
    // has to repaint as the user types.
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasName => _ctrl.text.trim().isNotEmpty;

  void _next() {
    if (!_hasName) return;
    Navigator.of(context, rootNavigator: true).pop(_ctrl.text.trim());
  }

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
                    'Start a review',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GlassButton(
                  label: 'Next',
                  compact: true,
                  disabled: !_hasName,
                  onPressed: _next,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: _ctrl,
              autofocus: true,
              label: 'Name',
              placeholder: 'End of block 1',
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              // The sheet's default background is a surface ground.
              elevated: true,
              onSubmitted: (_) => _next(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'A review is a pass over workouts and goals you pick: open each '
              'workout, change what needs changing, note what you think — then '
              'finish it and it is kept here.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
