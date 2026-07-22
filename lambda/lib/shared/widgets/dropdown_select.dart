import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_text_styles.dart';
import 'slide_up_modal.dart';

class DropdownOption<T> {
  const DropdownOption({required this.label, required this.value});
  final String label;
  final T value;
}

class DropdownSelect<T> extends StatelessWidget {
  const DropdownSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
    this.placeholder = 'Select…',
    this.searchable = false,
    this.onCreateNew,
    this.createNewLabel = 'Create new',
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChange;
  final String placeholder;
  final bool searchable;
  final VoidCallback? onCreateNew;
  final String createNewLabel;

  String get _displayLabel {
    if (value == null) return placeholder;
    return options
        .firstWhere(
          (o) => o.value == value,
          orElse: () => DropdownOption(label: placeholder, value: value as T),
        )
        .label;
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _displayLabel,
                style: TextStyle(
                  fontSize: AppTextStyles.md,
                  color: hasValue ? AppColors.primary : AppColors.muted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showLambdaModal<T>(
      context,
      fitContent: true,
      child: _DropdownSheet<T>(
        options: options,
        value: value,
        searchable: searchable,
        onCreateNew: onCreateNew,
        createNewLabel: createNewLabel,
        onSelect: (v) {
          Navigator.of(context, rootNavigator: true).pop();
          onChange(v);
        },
      ),
    );
  }
}

class _DropdownSheet<T> extends StatefulWidget {
  const _DropdownSheet({
    required this.options,
    required this.value,
    required this.searchable,
    required this.onSelect,
    required this.createNewLabel,
    this.onCreateNew,
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final bool searchable;
  final VoidCallback? onCreateNew;
  final String createNewLabel;
  final ValueChanged<T?> onSelect;

  @override
  State<_DropdownSheet<T>> createState() => _DropdownSheetState<T>();
}

class _DropdownSheetState<T> extends State<_DropdownSheet<T>> {
  String _query = '';

  List<DropdownOption<T>> get _filtered => widget.options
      .where((o) => o.label.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                style: TextStyle(
                    fontSize: AppTextStyles.md, color: AppColors.primary),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  prefixIcon:
                      Icon(Icons.search, size: 18, color: AppColors.muted),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          if (widget.onCreateNew != null)
            _SheetRow(
              label: widget.createNewLabel,
              color: AppColors.accent,
              isSelected: false,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                widget.onCreateNew!();
              },
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final opt = _filtered[i];
                return _SheetRow(
                  label: opt.label,
                  isSelected: opt.value == widget.value,
                  onTap: () => widget.onSelect(opt.value),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? (isSelected ? AppColors.accent : AppColors.primary);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        color: isSelected ? AppColors.accentBg : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextStyles.md,
                  color: effectiveColor,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
