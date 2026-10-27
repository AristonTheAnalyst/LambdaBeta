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
///
/// A surface whose read/edit is a MODE — the past-session viewer — passes
/// [onEditingChanged] and the sheet grows its own pencil, in the close
/// button's container just left of it (2026-10-27): the toggle drives the
/// caller's mode (the viewer's `startEditing`/`cancelEditing`), wears the
/// accent while editing and primary glass while reading, and the draft
/// callbacks are handed in for both modes — the sheet gates them on its own
/// [_SessionRatingsSheetState._editing], so flipping in place is instant.
/// Where there is no mode to switch (the live session is always editable; a
/// friend's record never is) the pencil is simply absent.
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
  bool editing = true,
  ValueChanged<bool>? onEditingChanged,
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
      editing: editing,
      onEditingChanged: onEditingChanged,
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
    required this.editing,
    required this.onEditingChanged,
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

  /// The mode the sheet opened in, and the caller's way of moving it. The
  /// callbacks above are handed in for BOTH modes; [editing] only says where
  /// to start, and whether the pencil exists at all (a null
  /// [onEditingChanged] means the surface has one mode and draws no pencil).
  final bool editing;
  final ValueChanged<bool>? onEditingChanged;

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

  /// The sheet's own read of the mode, seeded at open. Local, not read back
  /// off the caller, so the pencil flips the sections the moment it is
  /// tapped: the caller's mode moves behind the sheet and the sheet is not
  /// rebuilt by it (the values it opened with are the mode's values, and no
  /// stored answer can change while a modal sheet is up).
  late bool _editing = widget.editing;

  /// The shared toggle rule: tapping the selected star clears the rating.
  int? _toggled(int? current, int n) => current == n ? null : n;

  void _toggleEditing() {
    final next = !_editing;
    setState(() {
      _editing = next;
      // The sheet shows the mode it opened in: leaving a mode discards what
      // was typed in it (the caller's cancel does, and a re-entered edit
      // reseeds its drafts from the record), so the values snap back to the
      // ones the sheet opened with rather than lingering as a read-only copy
      // of edits that were just dropped.
      _preFeeling = widget.preFeeling;
      _postFeeling = widget.postFeeling;
      _preNotes = widget.preNotes;
      _postNotes = widget.postNotes;
    });
    widget.onEditingChanged!(next);
  }

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
                  // The mode's own control, in the close button's container
                  // (2026-10-27): the viewer's edit glyph — the same
                  // `edit_outlined` its header pencil wears — accent glass
                  // while editing, primary glass while reading. Absent where
                  // the surface has no mode to switch.
                  if (widget.onEditingChanged != null) ...[
                    GlassButton(
                      key: const ValueKey('session-ratings-edit'),
                      label: '',
                      icon: Icons.edit_outlined,
                      semanticsLabel: _editing
                          ? 'Stop editing ratings'
                          : 'Edit ratings',
                      compact: true,
                      color: _editing ? AppColors.accent : null,
                      onPressed: _toggleEditing,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
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
                        // The pencil's mode gates the draft callbacks: a
                        // surface that can edit hands them in for both
                        // modes, and the sheet only lets them through while
                        // it is editing.
                        onFeelingChanged:
                            widget.onPreFeelingChanged == null || !_editing
                            ? null
                            : (n) {
                                setState(
                                  () => _preFeeling = _toggled(_preFeeling, n),
                                );
                                widget.onPreFeelingChanged!(n);
                              },
                        onNotesChanged:
                            widget.onPreNotesChanged == null || !_editing
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
                        notesLabel: 'What could have made this session better',
                        placeholder:
                            'How did it go?\nStrong sets?\nAnything to fix?',
                        emptyNotes: 'No post-workout notes',
                        feeling: _postFeeling,
                        notes: _postNotes,
                        onFeelingChanged:
                            widget.onPostFeelingChanged == null || !_editing
                            ? null
                            : (n) {
                                setState(
                                  () =>
                                      _postFeeling = _toggled(_postFeeling, n),
                                );
                                widget.onPostFeelingChanged!(n);
                              },
                        onNotesChanged:
                            widget.onPostNotesChanged == null || !_editing
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
        // The edit hint is the same in both modes; the read box reserves
        // its height so the pencil's toggle never resizes the section
        // (2026-10-28).
        fieldHint: placeholder,
        onFeelingChanged: onFeelingChanged,
        onNotesChanged: onNotesChanged,
      ),
    );
  }
}
