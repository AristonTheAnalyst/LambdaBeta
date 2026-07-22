import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_text_styles.dart';

class SegmentOption<T> {
  const SegmentOption({required this.label, required this.value});
  final String label;
  final T value;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) {
        final isActive = opt.value == value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChange(opt.value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isActive ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Center(
                child: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.accentText : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
