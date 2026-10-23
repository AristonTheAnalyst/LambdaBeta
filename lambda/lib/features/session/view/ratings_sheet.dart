import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/session_bookend.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// The action bar's pencil: one session's pre/post questionnaire in a sheet —
/// another door to the same four values the two wizard pages collect
/// (2026-10-22).
///
/// The sections repeat the wizard's wording through the shared
/// [SessionBookend], so the sheet and the pages read as one feature. Null
/// callbacks keep a section read-only: the live session opens it editable on
/// the session in progress, and the past-session viewer opens it read-only in
/// view mode, editable in edit mode.
///
/// The star callback carries the tapped number, not the resulting value — the
/// caller's setter owns the toggle rule (tap the selected star to clear), so
/// the sheet and the wizard pages can never disagree about it.
Future<void> showSessionRatingsSheet(
  BuildContext context, {
  int? preFeeling,
  String preNotes = '',
  int? postFeeling,
  String postNotes = '',
  String? eyebrow,
  void Function(int n)? onPreFeelingChanged,
  ValueChanged<String>? onPreNotesChanged,
  void Function(int n)? onPostFeelingChanged,
  ValueChanged<String>? onPostNotesChanged,
}) {
  return showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _SessionRatingsSheet(
      preFeeling: preFeeling,
      preNotes: preNotes,
      postFeeling: postFeeling,
      postNotes: postNotes,
      eyebrow: eyebrow,
      onPreFeelingChanged: onPreFeelingChanged,
      onPreNotesChanged: onPreNotesChanged,
      onPostFeelingChanged: onPostFeelingChanged,
      onPostNotesChanged: onPostNotesChanged,
    ),
  );
}

class _SessionRatingsSheet extends StatefulWidget {
  const _SessionRatingsSheet({
    required this.preFeeling,
    required this.preNotes,
    required this.postFeeling,
    required this.postNotes,
    required this.eyebrow,
    required this.onPreFeelingChanged,
    required this.onPreNotesChanged,
    required this.onPostFeelingChanged,
    required this.onPostNotesChanged,
  });

  final int? preFeeling;
  final String preNotes;
  final int? postFeeling;
  final String postNotes;
  final String? eyebrow;
  final void Function(int n)? onPreFeelingChanged;
  final ValueChanged<String>? onPreNotesChanged;
  final void Function(int n)? onPostFeelingChanged;
  final ValueChanged<String>? onPostNotesChanged;

  @override
  State<_SessionRatingsSheet> createState() => _SessionRatingsSheetState();
}

class _SessionRatingsSheetState extends State<_SessionRatingsSheet> {
  // Local copies so a tap or a keystroke redraws the sheet now; every edit
  // also goes to the caller, which writes the VM (and so the wizard pages)
  // through the same setters they use.
  late int? _preFeeling = widget.preFeeling;
  late int? _postFeeling = widget.postFeeling;
  late String _preNotes = widget.preNotes;
  late String _postNotes = widget.postNotes;

  /// The shared toggle rule: tapping the selected star clears the rating.
  int? _toggled(int? current, int n) => current == n ? null : n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('session-ratings-sheet'),
      child: ConstrainedBox(
        // Two bookends plus the header can outgrow the screen; the sheet
        // stays under a ceiling and scrolls its body instead.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.eyebrow?.isNotEmpty == true)
                          Text(
                            widget.eyebrow!.toUpperCase(),
                            key: const ValueKey('session-ratings-eyebrow'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.mono(
                              fontSize: AppTextStyles.caption,
                              fontWeight: FontWeight.w500,
                              color: AppColors.inkSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        Text(
                          'Session Ratings',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlassButton(
                    key: const ValueKey('session-ratings-close'),
                    label: '',
                    icon: Icons.close,
                    semanticsLabel: 'Close ratings',
                    compact: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(
                        key: const ValueKey('session-ratings-pre'),
                        label: 'PRE-WORKOUT',
                        question: "How well do you think you're going to do",
                        notesLabel: 'Why do you feel that way',
                        placeholder:
                            'Sleep and eat well?\nHydrated?\nGoals today?',
                        emptyNotes: 'No pre-workout notes',
                        feeling: _preFeeling,
                        notes: _preNotes,
                        onFeelingChanged: widget.onPreFeelingChanged == null
                            ? null
                            : (n) {
                                setState(
                                  () => _preFeeling = _toggled(
                                    _preFeeling,
                                    n,
                                  ),
                                );
                                widget.onPreFeelingChanged!(n);
                              },
                        onNotesChanged: widget.onPreNotesChanged == null
                            ? null
                            : (v) {
                                setState(() => _preNotes = v);
                                widget.onPreNotesChanged!(v);
                              },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _section(
                        key: const ValueKey('session-ratings-post'),
                        label: 'POST-WORKOUT',
                        question: 'How well did you do this session',
                        notesLabel:
                            'What could have made this session better',
                        placeholder:
                            'How did it go?\nStrong sets?\nAnything to fix?',
                        emptyNotes: 'No post-workout notes',
                        feeling: _postFeeling,
                        notes: _postNotes,
                        onFeelingChanged: widget.onPostFeelingChanged == null
                            ? null
                            : (n) {
                                setState(
                                  () => _postFeeling = _toggled(
                                    _postFeeling,
                                    n,
                                  ),
                                );
                                widget.onPostFeelingChanged!(n);
                              },
                        onNotesChanged: widget.onPostNotesChanged == null
                            ? null
                            : (v) {
                                setState(() => _postNotes = v);
                                widget.onPostNotesChanged!(v);
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One bookend in its own panel — a bare outline, no fill, so the two
  /// halves read as two groups without a second ground stacking on the
  /// sheet's. [ContainerTone.outlineBright], not the house hairline: the
  /// sheet's ground is `surface`, one 10/255 step off `border`, so the
  /// standard rim would be all but invisible here (the lab found the same,
  /// 2026-10-22).
  ///
  /// The editable bookend lifts its notes field one tier above the sheet —
  /// the text-box rule (frontend-design §6). An empty read-only note passes
  /// null through so the bookend draws its placeholder line.
  Widget _section({
    Key? key,
    required String label,
    required String question,
    required String notesLabel,
    required String placeholder,
    required String emptyNotes,
    required int? feeling,
    required String notes,
    required void Function(int n)? onFeelingChanged,
    required ValueChanged<String>? onNotesChanged,
  }) {
    final editable = onNotesChanged != null;
    return LambdaContainer(
      key: key,
      tone: ContainerTone.outlineBright,
      radius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SessionBookend(
        label: label,
        question: question,
        notesLabel: notesLabel,
        feeling: feeling,
        notes: notes.trim().isEmpty ? null : notes,
        // The editable field's placeholder is the wizard's own prompt;
        // the read-only line states that there is nothing written yet.
        emptyNotes: editable ? placeholder : emptyNotes,
        onFeelingChanged: onFeelingChanged,
        onNotesChanged: onNotesChanged,
      ),
    );
  }
}
