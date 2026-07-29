import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';

void showNotesModal(
  BuildContext context, {
  required int setIndex,
  required String initialValue,
  String? plannedNote,
  required ValueChanged<String> onSave,
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
    ),
  );
}

class _NotesModalContent extends StatefulWidget {
  const _NotesModalContent({
    required this.setIndex,
    required this.initialValue,
    required this.onSave,
    this.plannedNote,
  });

  final int setIndex;
  final String initialValue;
  final String? plannedNote;
  final ValueChanged<String> onSave;

  @override
  State<_NotesModalContent> createState() => _NotesModalContentState();
}

class _NotesModalContentState extends State<_NotesModalContent> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialValue);

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
                  child: Text('Set ${widget.setIndex} Notes',
                      style: AppFonts.ui(
                          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
                GlassButton(label: 'Save', compact: true, onPressed: _save),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.plannedNote != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PLANNED  ',
                        style: AppFonts.mono(
                            fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success)),
                    Expanded(
                      child: Text(widget.plannedNote!,
                          style: AppFonts.ui(fontSize: 13, color: AppColors.muted)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 5,
              style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
              decoration: InputDecoration(
                hintText: widget.plannedNote ?? 'Form cues, how it felt, adjustments…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            if (_ctrl.text.trim().isNotEmpty) ...[
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
