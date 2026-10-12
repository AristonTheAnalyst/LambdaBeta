import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_spacing.dart';
import './container_styles.dart';
import './glass_button.dart';
import './menu_popover.dart';

/// One narrowing a filter menu offers — the label to draw and the value the
/// caller filters by.
class FilterOption<T> {
  const FilterOption({required this.label, required this.value});

  final String label;
  final T value;
}

/// The toolbar's filter control: a compact icon button that opens an anchored
/// menu of [options], the one in force ticked (2026-10-10).
///
/// The sibling of `SortButton`: where sort answers "in what order", filter
/// answers "which ones" — and unlike sort, filtering has an off state, so the
/// caller hands [active] and the button goes accent whenever a narrowing
/// other than its first option is in force. An unfiltered list needs no mark;
/// a list quietly missing rows because of a filter must say so somewhere, and
/// the button is where.
///
/// One question, one answer: a pick closes the menu, and so does re-picking
/// the narrowing in force — that tap answers the same question with the same
/// answer, so nothing is written.
class FilterButton<T> extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.active = false,
    this.elevated = false,
  });

  final List<FilterOption<T>> options;

  /// The narrowing in force right now — what the menu opens showing as
  /// ticked.
  final T value;

  /// Fires when the user picks an option other than the one already in
  /// force. A dismissed menu answers nothing.
  final void Function(T value) onChanged;

  /// True when [value] is a narrowing, not the unfiltered state — the caller
  /// saying which of its options is the plain one.
  final bool active;

  /// Steps the panel's fill up one tier — for a button standing on a
  /// `surface` ground (a default sheet) rather than the page.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return MenuPopover(
      semanticsLabel: 'Filter',
      tone: elevated ? ContainerTone.ghost : ContainerTone.surface,
      trigger: (context, open) => GlassButton(
        label: '',
        icon: Icons.filter_list,
        compact: true,
        color: active ? AppColors.accent : null,
        onPressed: open,
      ),
      contentBuilder: (context, dismiss) => _FilterMenu<T>(
        options: options,
        value: value,
        onChanged: onChanged,
        dismiss: dismiss,
      ),
    );
  }
}

/// The menu's body: one row per option, the chosen one ticked.
class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.dismiss,
  });

  final List<FilterOption<T>> options;
  final T value;
  final void Function(T value) onChanged;
  final VoidCallback dismiss;

  void _pick(FilterOption<T> option) {
    dismiss();
    if (option.value != value) onChanged(option.value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          ChoiceRow(
            label: options[i].label,
            active: options[i].value == value,
            onTap: () => _pick(options[i]),
          ),
        ],
      ],
    );
  }
}
