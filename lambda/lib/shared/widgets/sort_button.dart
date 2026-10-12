import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_spacing.dart';
import './container_styles.dart';
import './glass_button.dart';
import './menu_popover.dart';

/// One criterion in a sort menu — the label to draw, the value the caller
/// sorts by, and the direction that criterion naturally reads in.
class SortOption<T> {
  const SortOption({
    required this.label,
    required this.value,
    this.naturalDescending = false,
  });

  final String label;
  final T value;

  /// The direction this criterion reads in when it is freshly picked — true
  /// for "last used" / "most used" (newest or biggest first), false for A–Z.
  /// The menu opens on this reading, the active row's arrow says which way it
  /// currently points, and re-tapping the active row flips it — a criterion
  /// can land in either reading, but never by accident.
  final bool naturalDescending;
}

/// The toolbar's sort control: a compact icon button that opens an anchored
/// menu of [options] — the criterion in force arrowed ↓/↑, one pick per
/// answer (2026-10-10).
///
/// There is no Ascending/Descending switch: a freshly picked criterion lands
/// in its natural direction, and re-tapping the criterion in force flips it —
/// the two readings every one of these lists passes through. One question,
/// one answer: a pick closes the menu, which is why the arrow (not a tick)
/// marks the active row — the reading is what has to come back with it.
class SortButton<T> extends StatelessWidget {
  const SortButton({
    super.key,
    required this.options,
    required this.value,
    required this.descending,
    required this.onChanged,
    this.elevated = false,
  });

  final List<SortOption<T>> options;

  /// The criterion and direction in force right now — what the menu opens
  /// showing as chosen.
  final T value;
  final bool descending;

  /// Fires when the menu answers: a new criterion in its natural direction,
  /// or the criterion in force flipped.
  final void Function(T value, bool descending) onChanged;

  /// Steps the panel's fill up one tier — for a button standing on a
  /// `surface` ground (a default sheet) rather than the page.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return MenuPopover(
      semanticsLabel: 'Sort',
      tone: elevated ? ContainerTone.ghost : ContainerTone.surface,
      trigger: (context, open) => GlassButton(
        label: '',
        icon: Icons.sort,
        compact: true,
        onPressed: open,
      ),
      contentBuilder: (context, dismiss) => _SortMenu<T>(
        options: options,
        value: value,
        descending: descending,
        onChanged: onChanged,
        dismiss: dismiss,
      ),
    );
  }
}

/// The menu's body: one arrowed row per criterion.
///
/// Stateless on purpose — the rows render from the button's props, not from a
/// local mirror, so whatever the caller does with an answer comes straight
/// back should the menu ever redraw while up.
class _SortMenu<T> extends StatelessWidget {
  const _SortMenu({
    required this.options,
    required this.value,
    required this.descending,
    required this.onChanged,
    required this.dismiss,
  });

  final List<SortOption<T>> options;
  final T value;
  final bool descending;
  final void Function(T value, bool descending) onChanged;
  final VoidCallback dismiss;

  void _pick(SortOption<T> option) {
    // The row knows what the bool-only callback cannot say: a tap on a new
    // criterion lands it in its natural direction, a tap on the one in force
    // flips the direction and leaves the criterion alone.
    final same = option.value == value;
    dismiss();
    onChanged(option.value, same ? !descending : option.naturalDescending);
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
            // The active criterion wears the direction it reads in — the
            // arrow IS the reading, since these menus never say the words.
            trailing: Icon(
              descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 14,
              color: AppColors.accent,
            ),
          ),
        ],
      ],
    );
  }
}
