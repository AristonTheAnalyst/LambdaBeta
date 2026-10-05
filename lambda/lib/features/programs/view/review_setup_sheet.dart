import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/date_picker_sheet.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/program_history_viewmodel.dart';

/// Whether the review happens now or is scheduled for later.
///
/// The one distinction this sheet exists to draw. Both write the same row and
/// both end in a snapshot; "now" just means the user is about to take it, so
/// the ceremony opens behind the sheet and the things that only matter to a
/// future prompt — a date, a rationale — are not asked for.
enum ReviewStartMode { now, scheduled }

/// What a review is a review **of**. One of these is always the answer, so
/// there is no "none" case to guard.
enum ReviewScopeChoice { program, block, session }

/// What the user asked for when they set a review up.
class ReviewSetupRequest {
  const ReviewSetupRequest({
    required this.mode,
    required this.scope,
    this.scheduledFor,
    this.title,
    this.notes,
    this.isChange = false,
  });

  final ReviewStartMode mode;

  /// The thing to review. Its [ScopeOption.kind] and ids are what the review
  /// row is scoped by — the label is only for the bar.
  final ScopeOption scope;

  /// When it comes due. Null for [ReviewStartMode.now], where the answer is
  /// "already".
  final DateTime? scheduledFor;

  /// Carried by both modes: naming a review now is as useful as naming one you
  /// will be prompted about later.
  final String? title;

  /// Scheduled only. Notes at the START are the intent; notes at the END (the
  /// finish sheet) are the record.
  final String? notes;

  /// A **change** attaches the program's contents as a proposal, so the prompt
  /// can name what it is asking about. Meaningless for a review being taken
  /// now — the user is looking at the program, not at a description of it.
  final bool isChange;
}

/// Sets a review up: what to review, and whether to do it now or later.
///
/// The two questions are one sheet because they are one decision — "review
/// block 2" and "review block 2 on the 14th" are the same sentence with a date
/// attached. Splitting them would make the common case (review this now) pay
/// for the rarer one.
Future<ReviewSetupRequest?> showReviewSetupSheet(
  BuildContext context, {
  required List<ScopeOption> scopes,
  bool usesBlocks = false,

  /// Prefills the scope to this block rather than silently scoping to it: a
  /// filtered timeline is a hint about what the user is looking at, and turning
  /// a view filter into a decision would review the wrong thing on a mis-tap.
  String? initialBlockId,
}) {
  return showLambdaModal<ReviewSetupRequest>(
    context,
    keyboardAware: true,
    child: SafeArea(
      child: _ReviewSetupSheet(
        scopes: scopes,
        usesBlocks: usesBlocks,
        initialBlockId: initialBlockId,
      ),
    ),
  );
}

class _ReviewSetupSheet extends StatefulWidget {
  const _ReviewSetupSheet({
    required this.scopes,
    required this.usesBlocks,
    required this.initialBlockId,
  });

  final List<ScopeOption> scopes;
  final bool usesBlocks;
  final String? initialBlockId;

  @override
  State<_ReviewSetupSheet> createState() => _ReviewSetupSheetState();
}

class _ReviewSetupSheetState extends State<_ReviewSetupSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date = () {
    final now = DateTime.now().add(const Duration(days: 28));
    return DateTime(now.year, now.month, now.day);
  }();

  ReviewStartMode _mode = ReviewStartMode.now;
  ReviewScopeChoice _choice = ReviewScopeChoice.program;
  bool _isChange = false;

  String? _blockId;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    // Prefill, in the order that makes the empty cases fall through: a block
    // id that names one of the blocks on offer opens on that block, and with
    // nothing to prefill the program is the answer because it always exists.
    //
    // The id has to *resolve*, not merely be present: an id naming a block
    // that is no longer in the list would otherwise open on an empty picker
    // with a dead primary action — the same dead end the fall-through exists
    // to avoid.
    final block = widget.initialBlockId;
    if (block != null && _blockOptions.any((s) => s.blockId == block)) {
      _choice = ReviewScopeChoice.block;
      _blockId = block;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<ScopeOption> get _blockOptions => [
    for (final s in widget.scopes)
      if (s.kind == ReviewScopeKind.block) s,
  ];

  List<ScopeOption> get _sessionOptions => [
    for (final s in widget.scopes)
      if (s.kind == ReviewScopeKind.session) s,
  ];

  /// The scopes this program can actually offer. A blockless program has no
  /// block scope to choose and, with no workouts in it, no workout scope
  /// either — offering either would open an empty picker.
  List<ReviewScopeChoice> get _available => [
    ReviewScopeChoice.program,
    if (_blockOptions.isNotEmpty) ReviewScopeChoice.block,
    if (_sessionOptions.isNotEmpty) ReviewScopeChoice.session,
  ];

  /// The scope being submitted, or null when the choice names nothing — a
  /// block scope with no block picked yet.
  ScopeOption? get _scope => switch (_choice) {
    // Always present: the program scope is the one every program has, and the
    // viewmodel builds it first. The literal covers a caller that handed in a
    // list without it.
    ReviewScopeChoice.program =>
      widget.scopes.where((s) => s.kind == ReviewScopeKind.program).firstOrNull ??
          const ScopeOption(
            kind: ReviewScopeKind.program,
            label: 'Whole program',
          ),
    ReviewScopeChoice.block => _blockId == null
        ? null
        : _blockOptions.where((s) => s.blockId == _blockId).firstOrNull,
    ReviewScopeChoice.session => _sessionId == null
        ? null
        : _sessionOptions.where((s) => s.sessionId == _sessionId).firstOrNull,
  };

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
    final scope = _scope;
    if (scope == null) return;
    final title = _title.text.trim();
    final scheduled = _mode == ReviewStartMode.scheduled;
    Navigator.of(context).pop(
      ReviewSetupRequest(
        mode: _mode,
        scope: scope,
        scheduledFor: scheduled ? _date : null,
        title: title.isEmpty ? null : title,
        notes: scheduled
            ? (_notes.text.trim().isEmpty ? null : _notes.text.trim())
            : null,
        isChange: scheduled && _isChange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = _mode == ReviewStartMode.now;

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
            now ? 'Review' : 'Schedule a checkpoint',
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedControl<ReviewStartMode>(
            value: _mode,
            onChange: (v) => setState(() => _mode = v),
            options: const [
              SegmentOption(label: 'Now', value: ReviewStartMode.now),
              SegmentOption(label: 'Schedule', value: ReviewStartMode.scheduled),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            now
                ? 'Opens the plan so you can look through it and change what '
                      'needs changing. What it looks like when you finish is '
                      'saved with the review.'
                : 'Asks you to look at it on the day. Nothing changes until '
                      'you do.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Label('What to review'),
          const SizedBox(height: 6),
          SegmentedControl<ReviewScopeChoice>(
            subtle: true,
            value: _choice,
            onChange: (v) => setState(() => _choice = v),
            options: [
              for (final c in _available)
                SegmentOption(label: _choiceLabel(c), value: c),
            ],
          ),
          if (_choice == ReviewScopeChoice.block) ...[
            const SizedBox(height: AppSpacing.sm),
            _ScopeDropdown(
              options: _blockOptions,
              value: _blockId,
              placeholder: 'Choose a block',
              onSelect: (id) => setState(() => _blockId = id),
            ),
          ],
          if (_choice == ReviewScopeChoice.session) ...[
            const SizedBox(height: AppSpacing.sm),
            _ScopeDropdown(
              options: _sessionOptions,
              value: _sessionId,
              placeholder: 'Choose a workout',
              onSelect: (id) => setState(() => _sessionId = id),
            ),
          ],
          if (!now) ...[
            const SizedBox(height: AppSpacing.lg),
            _Label('Kind'),
            const SizedBox(height: 6),
            SegmentedControl<bool>(
              subtle: true,
              value: _isChange,
              onChange: (v) => setState(() => _isChange = v),
              options: const [
                SegmentOption(label: 'Checkpoint', value: false),
                SegmentOption(label: 'Planned change', value: true),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _isChange
                  ? 'A planned change attaches what the program looks like '
                        'now, so the prompt can ask about it later.'
                  : 'A checkpoint looks at what you have achieved since the '
                        'last one.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Label('On'),
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
          ],
          const SizedBox(height: AppSpacing.lg),
          LambdaInput(
            controller: _title,
            label: now ? 'Title (optional)' : 'Title',
            placeholder: _isChange
                ? 'Swap the bench variation'
                : 'End of block 1',
            textCapitalization: TextCapitalization.sentences,
          ),
          if (!now) ...[
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
          ],
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: now ? 'Start review' : 'Schedule',
              solid: true,
              // A scope that names nothing cannot be reviewed, and the DB
              // refuses a half-scoped row — so the primary action waits rather
              // than failing at the write.
              disabled: _scope == null,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }

  static String _choiceLabel(ReviewScopeChoice c) => switch (c) {
    ReviewScopeChoice.program => 'Program',
    ReviewScopeChoice.block => 'Block',
    ReviewScopeChoice.session => 'Workout',
  };
}

/// The block or workout picker. One widget for both because they are the same
/// choice at two sizes — which one, of these.
class _ScopeDropdown extends StatelessWidget {
  const _ScopeDropdown({
    required this.options,
    required this.value,
    required this.placeholder,
    required this.onSelect,
  });

  final List<ScopeOption> options;
  final String? value;
  final String placeholder;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    String? current;
    for (final o in options) {
      final id = o.sessionId ?? o.blockId;
      if (id == value) current = o.label;
    }

    return DropdownSelect<String>(
      options: [
        for (final o in options)
          DropdownOption(label: o.label, value: o.sessionId ?? o.blockId ?? ''),
      ],
      // The picker is keyed by id; `current` is only read above to prove the
      // id still resolves to a label after the list reloads.
      value: current == null ? null : value,
      placeholder: placeholder,
      title: placeholder,
      onChange: (v) {
        if (v != null) onSelect(v);
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.ui(
      fontSize: AppTextStyles.sm,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    ),
  );
}
