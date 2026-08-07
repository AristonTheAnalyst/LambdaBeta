import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';

/// "New Variation" name prompt. Owns its [TextEditingController] so the
/// controller is disposed when the dialog route is fully removed (after the
/// exit animation) — disposing it right after `showDialog` returns crashes,
/// because the TextField is still mounted and rebuilding during the pop
/// animation.
class VariationNameDialog extends StatefulWidget {
  const VariationNameDialog({super.key});

  @override
  State<VariationNameDialog> createState() => _VariationNameDialogState();
}

class _VariationNameDialogState extends State<VariationNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('New Variation', style: TextStyle(color: AppColors.primary)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: TextStyle(color: AppColors.primary),
        decoration: InputDecoration(
            hintText: 'Variation name',
            hintStyle: TextStyle(color: AppColors.muted)),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
        TextButton(
            onPressed: _submit,
            child: Text('Create',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
