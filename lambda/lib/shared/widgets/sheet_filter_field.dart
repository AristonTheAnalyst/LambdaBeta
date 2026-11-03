import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';
import 'menu_popover.dart';

/// One narrowing control inside a session sheet (2026-10-26) — the goals
/// sheet's date-row recipe (glass, a compact line, a chevron) hung off the
/// shared [MenuPopover]. Accent while it is doing something, the way the
/// library's funnel does. Generic over the answer's type — a weight, a rep
/// count, a variation id — with null as "any" in both.
///
/// Extracted from the PR History sheet when the exercise goals sheet asked
/// for the same furniture (2026-10-26): the two sheets open onto one header,
/// so they open onto one control row too, and a second copy of this recipe
/// could drift from the first.
class SheetFilterField<T> extends StatelessWidget {
  const SheetFilterField({
    super.key,
    required this.label,
    required this.anyLabel,
    this.anyShort = 'Any',
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.align,
    required this.onChanged,
  });

  /// The field's uppercase label, in front of its answer.
  final String label;

  /// The menu's "no narrowing" row — "Any weight", "All goals".
  final String anyLabel;

  /// How that row reads on the closed field — "Any", "All".
  final String anyShort;

  /// The answer in force; null = no narrowing.
  final T? value;

  final List<T> options;
  final String Function(T option) optionLabel;

  /// Which edge the menu hangs off — the left field of a pair opens start,
  /// the right one end.
  final MenuPopoverAlign align;

  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    final color = active ? AppColors.accent : AppColors.primary;
    return MenuPopover(
      tone: ContainerTone.ghost,
      align: align,
      semanticsLabel: label,
      trigger: (context, open) => GestureDetector(
        onTap: open,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: AppSpacing.sm,
          ),
          decoration: glassBox(color),
          // Scale-to-fit: a wide value in a narrow half-row narrows rather
          // than overflows (the goal card's squeeze, 2026-10-20).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The field-label recipe the app's own inputs use — a
                // readable label over its value, not a caption under it.
                Text(
                  label,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  value == null ? anyShort : optionLabel(value as T),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(LucideIcons.chevronDown, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
      contentBuilder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceRow(
            label: anyLabel,
            active: value == null,
            onTap: () {
              onChanged(null);
              dismiss();
            },
          ),
          for (final option in options)
            ChoiceRow(
              label: optionLabel(option),
              active: value == option,
              onTap: () {
                onChanged(option);
                dismiss();
              },
            ),
        ],
      ),
    );
  }
}
