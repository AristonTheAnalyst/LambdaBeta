import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import 'achievements_panel.dart';
import 'review_container.dart';

/// Closes a review: what to say about it, then finish.
///
/// Notes come in at the END, not the start. A review's notes explain the
/// changes it made, and at the start there is nothing yet to explain — the
/// user would be asked to write a summary of a pass they have not taken. This
/// is the only input the ceremony adds; everything else happens in the real
/// editors, which is the whole point of the design.
///
/// Returns the notes (possibly empty, for a review finished without any) or
/// null when the sheet was dismissed — the caller must not treat those the
/// same, since one finishes the review and the other leaves it open.
Future<String?> showReviewNotesSheet(
  BuildContext context, {
  required ReviewSession session,
}) {
  return showLambdaModal<String>(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _ReviewNotesSheet(session: session),
  );
}

class _ReviewNotesSheet extends StatefulWidget {
  const _ReviewNotesSheet({required this.session});

  final ReviewSession session;

  @override
  State<_ReviewNotesSheet> createState() => _ReviewNotesSheetState();
}

class _ReviewNotesSheetState extends State<_ReviewNotesSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            Text(
              'Finish review',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ScopeLine(session: widget.session),
            // What the window produced, when there is one to show. It is here
            // rather than on the review because it is the context for the notes
            // below: "why did I change this?" is answered by what happened.
            if (widget.session.achievements != null) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SectionLabel('SINCE THE LAST CHECKPOINT'),
              const SizedBox(height: AppSpacing.sm),
              // Capped and scrollable: a long PR list must not push the notes
              // field — the actual input — off the sheet.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: AchievementsPanel(
                    achievements: widget.session.achievements,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Anything to note about what changed, or why? The plan as it "
              "stands now is saved with this review either way.",
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
              decoration: InputDecoration(
                hintText: 'Why you changed it, what to watch, how it went…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassButton(
              label: 'Finish review',
              solid: true,
              color: AppColors.accent,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(_ctrl.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is being reviewed, and since when — the two facts that make the notes
/// below make sense a month later.
class _ScopeLine extends StatelessWidget {
  const _ScopeLine({required this.session});

  final ReviewSession session;

  @override
  Widget build(BuildContext context) {
    final since = session.sinceDate;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              session.scopeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: AppColors.accentText,
              ),
            ),
          ),
          if (since != null)
            Text(
              'since ${_shortDate(since)}',
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                color: AppColors.accentText,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: AppColors.muted,
    ),
  );
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}
