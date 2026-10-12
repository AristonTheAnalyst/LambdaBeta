import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/slide_up_modal.dart';

void showNotesModal(
  BuildContext context, {
  required int setIndex,
  required String initialValue,
  String? plannedNote,
  required ValueChanged<String> onSave,
  bool readOnly = false,
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _NotesModalContent(
      setIndex: setIndex,
      initialValue: initialValue,
      plannedNote: plannedNote,
      onSave: onSave,
      readOnly: readOnly,
    ),
  );
}

class _NotesModalContent extends StatefulWidget {
  const _NotesModalContent({
    required this.setIndex,
    required this.initialValue,
    required this.onSave,
    this.plannedNote,
    this.readOnly = false,
  });

  final int setIndex;
  final String initialValue;
  final String? plannedNote;
  final ValueChanged<String> onSave;
  final bool readOnly;

  @override
  State<_NotesModalContent> createState() => _NotesModalContentState();
}

class _NotesModalContentState extends State<_NotesModalContent> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  void _save() {
    widget.onSave(_ctrl.text);
    Navigator.of(context, rootNavigator: true).pop();
  }

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Set ${widget.setIndex} Notes',
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GlassButton(
                  label: widget.readOnly ? 'Done' : 'Save',
                  compact: true,
                  // Done dismisses whatever the state; Save has nothing to
                  // write until the note differs from the one it opened with.
                  disabled: !widget.readOnly && _ctrl.text == widget.initialValue,
                  onPressed: widget.readOnly
                      ? () => Navigator.of(context, rootNavigator: true).pop()
                      : _save,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.plannedNote != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.plannedBg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.planned.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLANNED  ',
                      style: AppFonts.mono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.planned,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.plannedNote!,
                        style: AppFonts.ui(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (widget.readOnly)
              if (widget.initialValue.trim().isEmpty)
                Text(
                  widget.plannedNote ?? 'Form cues, how it felt, adjustments…',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.muted,
                  ),
                )
              else
                LambdaReadout(value: widget.initialValue)
            else
              LambdaInput(
                controller: _ctrl,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                placeholder:
                    widget.plannedNote ?? 'Form cues, how it felt, adjustments…',
                // The sheet's default background is a surface ground.
                elevated: true,
              ),
            if (_ctrl.text.trim().isNotEmpty && !widget.readOnly) ...[
              const SizedBox(height: AppSpacing.sm),
              GlassButton(
                label: 'Delete Note',
                color: AppColors.danger,
                onPressed: () {
                  widget.onSave('');
                  Navigator.of(context, rootNavigator: true).pop();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
