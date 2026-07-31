import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'slide_up_modal.dart';

class DropdownOption<T> {
  const DropdownOption({required this.label, required this.value});
  final String label;
  final T value;
}

/// Wraps modal-sheet content (every [showLambdaModal] call gets one
/// automatically) so any [DropdownSelect] inside shows its option picker as
/// an in-place overlay confined to that sheet's own bounds, instead of
/// stacking a brand-new independent bottom sheet on top of it.
class DropdownSheetHost extends StatefulWidget {
  const DropdownSheetHost({super.key, required this.child});

  final Widget child;

  static DropdownSheetHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<DropdownSheetHostState>();

  @override
  State<DropdownSheetHost> createState() => DropdownSheetHostState();
}

class DropdownSheetHostState extends State<DropdownSheetHost> {
  Widget Function(VoidCallback dismiss)? _picker;

  void showPicker(Widget Function(VoidCallback dismiss) builder) {
    setState(() => _picker = builder);
  }

  void _dismiss() => setState(() => _picker = null);

  @override
  Widget build(BuildContext context) {
    final picker = _picker;
    return Stack(
      children: [
        widget.child,
        if (picker != null)
          Positioned.fill(
            child: Container(
              color: AppColors.surface,
              child: picker(_dismiss),
            ),
          ),
      ],
    );
  }
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
    this.compact = false,
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChange;
  final String placeholder;
  final bool searchable;
  // Called with whatever the user had typed in the search box (empty string
  // if nothing was typed), so callers can create-and-select in one step
  // instead of asking the user to type the name a second time.
  final ValueChanged<String>? onCreateNew;
  final String createNewLabel;
  // Minimal, borderless inline-text look (still fully tappable, opens the
  // same picker) — for a field that's dependent on/subordinate to another
  // one nearby, e.g. a variation breadcrumbed off its exercise.
  final bool compact;

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
      onTap: () {
        final host = DropdownSheetHost.maybeOf(context);
        if (host != null) {
          // In-modal path: defer to next frame so the host's setState
          // doesn't run during the parent's build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final h = DropdownSheetHost.maybeOf(context);
            if (h == null) return;
            h.showPicker((dismiss) => _DropdownSheetContent<T>(
                  options: options,
                  value: value,
                  searchable: searchable,
                  onCreateNew: onCreateNew,
                  createNewLabel: createNewLabel,
                  fillHeight: true,
                  onClose: dismiss,
                  onSelect: onChange,
                ));
          });
        } else {
          // Plain-page path: open the bottom sheet immediately — deferring
          // here makes it require a second tap to appear.
          showDropdownPickerSheet<T>(
            context,
            options: options,
            value: value,
            searchable: searchable,
            onCreateNew: onCreateNew,
            createNewLabel: createNewLabel,
            onSelect: onChange,
          );
        }
      },
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayLabel,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w500,
                    color: hasValue ? AppColors.accent : AppColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.muted),
              ],
            )
          : Container(
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
                      style: AppFonts.ui(
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
}

/// Shows the searchable option-picker as its own independent bottom sheet —
/// used as a fallback when there's no enclosing [DropdownSheetHost] to
/// confine to (e.g. a [DropdownSelect] on a plain page), and standalone by
/// callers that want to jump straight to picking an option — e.g. reopening
/// the picker right after the user creates a brand-new option from within it,
/// instead of dropping them back into a whole form first.
void showDropdownPickerSheet<T>(
  BuildContext context, {
  required List<DropdownOption<T>> options,
  required T? value,
  required ValueChanged<T?> onSelect,
  bool searchable = false,
  ValueChanged<String>? onCreateNew,
  String createNewLabel = 'Create new',
}) {
  showLambdaModal<T>(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _DropdownSheetContent<T>(
      options: options,
      value: value,
      searchable: searchable,
      onCreateNew: onCreateNew,
      createNewLabel: createNewLabel,
      fillHeight: false,
      onClose: () => Navigator.of(context, rootNavigator: true).pop(),
      onSelect: onSelect,
    ),
  );
}

class _DropdownSheetContent<T> extends StatefulWidget {
  const _DropdownSheetContent({
    required this.options,
    required this.value,
    required this.searchable,
    required this.onSelect,
    required this.createNewLabel,
    required this.onClose,
    required this.fillHeight,
    this.onCreateNew,
  });

  final List<DropdownOption<T>> options;
  final T? value;
  final bool searchable;
  final ValueChanged<String>? onCreateNew;
  final String createNewLabel;
  final ValueChanged<T?> onSelect;
  // Closes this picker — pops the route when shown standalone, or clears the
  // hosting sheet's overlay when shown in-place.
  final VoidCallback onClose;
  // true when confined inside a DropdownSheetHost (Positioned.fill gives a
  // definite height to fill); false when this is its own bottom sheet route
  // sizing itself to content, up to a max height.
  final bool fillHeight;

  @override
  State<_DropdownSheetContent<T>> createState() =>
      _DropdownSheetContentState<T>();
}

class _DropdownSheetContentState<T> extends State<_DropdownSheetContent<T>> {
  String _query = '';

  List<DropdownOption<T>> get _filtered => widget.options
      .where((o) => o.label.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      shrinkWrap: true,
      itemCount: _filtered.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final opt = _filtered[i];
        return _SheetRow(
          label: opt.label,
          isSelected: opt.value == widget.value,
          onTap: () {
            widget.onClose();
            // Defer selection past the frame so the picker dismiss
            // completes before any parent rebuild from the selection.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onSelect(opt.value);
            });
          },
        );
      },
    );

    final children = [
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            widget.onClose();
            final query = _query;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onCreateNew!(query);
            });
          },
        ),
      widget.fillHeight
          ? Expanded(child: list)
          : Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: list,
              ),
            ),
      const SizedBox(height: 8),
    ];

    if (widget.fillHeight) {
      return SafeArea(
        top: false,
        child: Column(children: children),
      );
    }

    final media = MediaQuery.of(context);
    // Bound the whole sheet by what's actually left above the keyboard, not
    // a fixed fraction of the full screen — otherwise a long list plus the
    // keyboard's own height can add up to more than the viewport and overflow.
    final maxSheetHeight = media.size.height - media.viewInsets.bottom;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight * 0.6),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
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
                style: AppFonts.ui(
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

/// Stands in for a [DropdownSelect] while a quick-create is in flight —
/// matches its container styling exactly so the field doesn't jump.
class DropdownLoadingField extends StatelessWidget {
  const DropdownLoadingField({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Creating…',
                style: AppFonts.ui(
                    fontSize: AppTextStyles.md, color: AppColors.muted),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
