import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/menu_popover.dart';

/// The dev lab's one toolbar: a compact search field, sort and a range
/// filter. Extracted so the Friend Screen's tabs and the Exercise screen
/// wear the same strip instead of two near-copies (2026-11-03).
enum LabSortBy { newest, oldest, name }

enum LabRange { all, week, month }

/// Search, sort and a range filter — one narrow strip rather than a second
/// header: 32pt controls inside 8pt of padding above and below.
class LabToolbar extends StatelessWidget {
  const LabToolbar({
    super.key,
    required this.search,
    required this.sort,
    required this.descending,
    required this.range,
    required this.onSort,
    required this.onRange,
  });

  final TextEditingController search;
  final LabSortBy sort;
  final bool descending;
  final LabRange range;
  final void Function(LabSortBy value, bool descending) onSort;
  final ValueChanged<LabRange> onRange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: _CompactSearch(controller: search)),
          const SizedBox(width: AppSpacing.sm),
          _ToolbarMenuButton(
            icon: LucideIcons.arrowUpDown,
            semanticsLabel: 'Sort',
            contentBuilder: (context, dismiss) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoiceRow(
                  label: 'Newest',
                  active: sort == LabSortBy.newest,
                  onTap: () {
                    dismiss();
                    onSort(LabSortBy.newest, true);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                ChoiceRow(
                  label: 'Oldest',
                  active: sort == LabSortBy.oldest,
                  onTap: () {
                    dismiss();
                    onSort(LabSortBy.oldest, false);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                ChoiceRow(
                  label: 'Name',
                  active: sort == LabSortBy.name,
                  onTap: () {
                    dismiss();
                    onSort(LabSortBy.name, false);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ToolbarMenuButton(
            icon: LucideIcons.listFilter,
            semanticsLabel: 'Filter',
            active: range != LabRange.all,
            contentBuilder: (context, dismiss) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (label, value) in const [
                  ('All', LabRange.all),
                  ('This week', LabRange.week),
                  ('This month', LabRange.month),
                ]) ...[
                  ChoiceRow(
                    label: label,
                    active: range == value,
                    onTap: () {
                      dismiss();
                      onRange(value);
                    },
                  ),
                  if (value != LabRange.month)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The toolbar's search: a 32pt box with the magnifier and a dense field.
class _CompactSearch extends StatelessWidget {
  const _CompactSearch({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              textAlignVertical: TextAlignVertical.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search…',
                hintStyle: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 32pt square that opens an anchored menu — the toolbar's compact answer
/// to `SortButton` / `FilterButton`, which wear the standard 40pt button.
class _ToolbarMenuButton extends StatelessWidget {
  const _ToolbarMenuButton({
    required this.icon,
    required this.semanticsLabel,
    required this.contentBuilder,
    this.active = false,
  });

  final IconData icon;
  final String semanticsLabel;
  final Widget Function(BuildContext context, VoidCallback dismiss)
  contentBuilder;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ink = active ? AppColors.accent : AppColors.primary;
    return MenuPopover(
      semanticsLabel: semanticsLabel,
      trigger: (context, open) => GestureDetector(
        onTap: open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: glassBox(ink),
          child: Icon(icon, size: 16, color: ink),
        ),
      ),
      contentBuilder: contentBuilder,
    );
  }
}
