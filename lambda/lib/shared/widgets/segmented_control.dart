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
    this.subtle = false,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChange;
  // Low-contrast outlined treatment for secondary mode switches that
  // shouldn't compete with a nearby primary CTA.
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) {
        final isActive = opt.value == value;
        final Color bg;
        final Color borderColor;
        final Color fg;
        if (subtle) {
          bg = Colors.transparent;
          borderColor = isActive ? AppColors.primary : AppColors.border;
          fg = isActive ? AppColors.primary : AppColors.muted;
        } else {
          // Active segment = the glass recipe — the pressable chrome.
          bg = isActive ? AppColors.primary.withAlpha(26) : AppColors.surface;
          borderColor =
              isActive ? AppColors.primary.withAlpha(77) : AppColors.border;
          fg = isActive ? AppColors.primary : AppColors.muted;
        }
        return Expanded(
          child: GestureDetector(
            onTap: () => onChange(opt.value),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: subtle ? 8 : 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: subtle ? AppTextStyles.xs : AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: fg,
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
