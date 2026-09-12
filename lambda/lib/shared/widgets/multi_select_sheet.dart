import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'glass_button.dart';
import 'slide_up_modal.dart';

class MultiSelectOption<T> {
  const MultiSelectOption({required this.label, required this.value});
  final String label;
  final T value;
}

/// Shows a multi-select bottom sheet. Returns selected values or null if dismissed.
Future<List<T>?> showMultiSelectSheet<T>(
  BuildContext context, {
  required List<MultiSelectOption<T>> options,
  required List<T> selected,
  required String title,
  bool searchable = false,
  String confirmLabel = 'Add',
  VoidCallback? onCreateNew,
  String createNewLabel = 'Create new',
}) {
  return showLambdaModal<List<T>>(
    context,
    child: _MultiSelectSheet<T>(
      options: options,
      initial: selected,
      title: title,
      searchable: searchable,
      confirmLabel: confirmLabel,
      onCreateNew: onCreateNew,
      createNewLabel: createNewLabel,
    ),
  );
}

class _MultiSelectSheet<T> extends StatefulWidget {
  const _MultiSelectSheet({
    required this.options,
    required this.initial,
    required this.title,
    required this.searchable,
    required this.confirmLabel,
    this.onCreateNew,
    required this.createNewLabel,
  });

  final List<MultiSelectOption<T>> options;
  final List<T> initial;
  final String title;
  final bool searchable;
  final String confirmLabel;
  final VoidCallback? onCreateNew;
  final String createNewLabel;

  @override
  State<_MultiSelectSheet<T>> createState() => _MultiSelectSheetState<T>();
}

class _MultiSelectSheetState<T> extends State<_MultiSelectSheet<T>> {
  late final Set<T> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initial);
  }

  List<MultiSelectOption<T>> get _filtered => widget.options
      .where((o) => o.label.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final confirmCount = _selected.length - widget.initial.length;
    final effectiveLabel = confirmCount > 0
        ? '$confirmCount selected — ${widget.confirmLabel}'
        : widget.confirmLabel;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ),
                if (widget.onCreateNew != null)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context, rootNavigator: true).pop(null);
                      widget.onCreateNew!();
                    },
                    child: Text(
                      '+ ${widget.createNewLabel}',
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                style: AppFonts.ui(
                    fontSize: AppTextStyles.md, color: AppColors.primary),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: AppFonts.ui(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: AppColors.muted),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final opt = _filtered[i];
                final isSelected = _selected.contains(opt.value);
                return InkWell(
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selected.remove(opt.value);
                    } else {
                      _selected.add(opt.value);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    color: isSelected
                        ? AppColors.accentBg
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            opt.label,
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.md,
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.primary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check,
                              size: 18, color: AppColors.accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: effectiveLabel,
                color: AppColors.accent,
                solid: true,
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .pop(_selected.toList()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
