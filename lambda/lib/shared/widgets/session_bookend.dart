import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'feeling_rating.dart';
import 'lambda_input.dart';
import 'lambda_readout.dart';

/// One pre/post bookend section — the session questionnaire read back with
/// the same wording/styling as the live form: [question] above the rating
/// and [notesLabel] above the notes. Rating and notes always render: an
/// unrated session shows empty squares, and empty notes show [emptyNotes]
/// in the reflection sections' empty-note style. Notes sit in a lesson-row
/// container and scroll inside it when long.
///
/// Shared between the prep page's LAST SESSION card (read-only) and the
/// past-session viewer's Summary tab. When [onFeelingChanged] /
/// [onNotesChanged] are given (the viewer's edit mode), the stars become
/// tappable and the notes render as an editable multiline field; null keeps
/// the read-only rendering.
class SessionBookend extends StatefulWidget {
  const SessionBookend({
    super.key,
    required this.label,
    required this.feeling,
    required this.notes,
    required this.emptyNotes,
    required this.question,
    required this.notesLabel,
    this.onFeelingChanged,
    this.onNotesChanged,
    this.fieldHint,
  });

  final String label;
  final int? feeling;
  final String? notes;
  final String emptyNotes;
  final String question;
  final String notesLabel;
  final void Function(int n)? onFeelingChanged;
  final void Function(String v)? onNotesChanged;

  /// The placeholder the editable field draws when the read side shows a
  /// different sentence — the ratings sheet's wizard prompt in edit, its
  /// "no notes" line in read (2026-10-28). The hollow read box reserves this
  /// text's height too, exactly as a field reserves its hint's, so the mode
  /// toggle never changes the box's height. Null means [emptyNotes] is both.
  final String? fieldHint;

  @override
  State<SessionBookend> createState() => _SessionBookendState();
}

class _SessionBookendState extends State<SessionBookend> {
  late final TextEditingController _notesCtrl = TextEditingController(
    text: widget.notes ?? '',
  );
  final FocusNode _notesFocus = FocusNode();

  @override
  void didUpdateWidget(SessionBookend oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bookend can rebuild from VM state while the user types (drafts
    // live in state). Re-seed only when the value genuinely changed
    // externally — never clobber the field mid-edit.
    if (!_notesFocus.hasFocus && widget.notes != _notesCtrl.text) {
      _notesCtrl.text = widget.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onNotesChanged != null;
    // One hint in both modes: the field draws it while editing, and the
    // hollow read box reserves its height so the swap moves only the fill.
    final hint = widget.fieldHint ?? widget.emptyNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.question,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Full-size squares — the usual rating size, centered like the
        // prep page's THIS SESSION input. Tappable only in edit mode; the
        // pill is filled in edit and hollow in read (2026-10-28), so the
        // mode reads off one fill, exactly like the notes box below it.
        FeelingRating(
          value: widget.feeling,
          onChanged: widget.onFeelingChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.notesLabel,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (editable)
          LambdaInput(
            controller: _notesCtrl,
            focusNode: _notesFocus,
            placeholder: hint,
            minLines: 2,
            maxLines: 6,
            // The editable bookend lives on surface grounds (the viewer's
            // AppCards); the fill steps up so the field reads as one.
            elevated: true,
            onChanged: widget.onNotesChanged,
          )
        else
          // The very field above, hollowed: same box, same words, same
          // reserved hint height, no fill — the toggle moves the fill and
          // nothing else (2026-10-28). An unwritten note draws [emptyNotes]
          // in the same box rather than dropping to a bare line, because a
          // box that disappears is the loudest move of all.
          LambdaReadout(
            value: widget.notes ?? '',
            placeholder: widget.emptyNotes,
            fieldHint: hint,
          ),
      ],
    );
  }
}
