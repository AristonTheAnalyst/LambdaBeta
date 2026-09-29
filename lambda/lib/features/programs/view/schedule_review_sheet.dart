import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/date_picker_sheet.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/segmented_control.dart';

/// What the user asked for when scheduling a review.
class ScheduledReviewRequest {
  const ScheduledReviewRequest({
    required this.title,
    required this.notes,
    required this.scheduledFor,
    required this.isChange,
  });

  final String? title;
  final String? notes;
  final DateTime scheduledFor;

  /// A **change** carries the program's contents as a proposal — see
  /// `ProgramHistoryViewModel.scheduleReview`.
  final bool isChange;
}

/// Schedules the program's next checkpoint.
///
/// A review and a change are the same act — "look at this on that day" — so
/// they share one sheet and one date picker. The difference is what the prompt
/// carries when it comes due, and that is one switch, not a second screen.
///
/// Title and notes are not garnish: a change with no rationale is a diff with
/// no story, so the placeholder asks for the intent rather than the date.
Future<ScheduledReviewRequest?> showScheduleReviewSheet(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showLambdaModal<ScheduledReviewRequest>(
    context,
    keyboardAware: true,
    child: SafeArea(
      child: _ScheduleSheet(
        initialDate: initialDate ?? DateTime.now().add(const Duration(days: 28)),
      ),
    ),
  );
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
    widget.initialDate.day,
  );

  bool _isChange = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePickerSheet(
      context,
      initial: _date,
      // Yesterday is allowed: a review is often scheduled after the fact
      // ("check in on the 1st") and a past date simply means due now, which
      // is the honest reading rather than silently shifting it to tomorrow.
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5, 12, 31),
      title: 'SCHEDULE REVIEW',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    Navigator.of(context).pop(ScheduledReviewRequest(
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      scheduledFor: _date,
      isChange: _isChange,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Schedule a checkpoint',
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedControl<bool>(
            value: _isChange,
            onChange: (v) => setState(() => _isChange = v),
            options: const [
              SegmentOption(label: 'Review', value: false),
              SegmentOption(label: 'Change', value: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _isChange
                ? 'A change attaches what the program looks like now, so the '
                    'prompt can ask about it later.'
                : 'A review looks at what you have achieved since the last one.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'On',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
              child: Text(
                DateFormat('EEE, d MMM yyyy').format(_date),
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LambdaInput(
            controller: _title,
            label: 'Title',
            placeholder: _isChange
                ? 'Swap the bench variation'
                : 'End of block 1',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.md),
          LambdaInput(
            controller: _notes,
            label: 'Notes',
            placeholder: _isChange
                ? 'Why this change, and what it is for'
                : 'What to look at when this comes due',
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: 'Schedule',
              solid: true,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
