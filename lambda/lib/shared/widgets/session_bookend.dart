import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'feeling_rating.dart';
import 'lambda_input.dart';

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
  });

  final String label;
  final int? feeling;
  final String? notes;
  final String emptyNotes;
  final String question;
  final String notesLabel;
  final void Function(int n)? onFeelingChanged;
  final void Function(String v)? onNotesChanged;

  @override
  State<SessionBookend> createState() => _SessionBookendState();
}

class _SessionBookendState extends State<SessionBookend> {
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.notes ?? '');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppFonts.mono(
            fontSize: 13,
            letterSpacing: 0.8,
            color: AppColors.muted,
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
        // prep page's THIS SESSION input. Tappable only in edit mode.
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
            placeholder: widget.emptyNotes,
            minLines: 2,
            maxLines: 6,
            onChanged: widget.onNotesChanged,
          )
        else if (widget.notes != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
            child: ConstrainedBox(
              // Roomier than one line so short notes still read as a box;
              // long notes scroll inside it instead of stretching the card.
              constraints: const BoxConstraints(minHeight: 64, maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  widget.notes!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          )
        else
          Text(
            widget.emptyNotes,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
      ],
    );
  }
}
