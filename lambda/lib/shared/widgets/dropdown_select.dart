import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
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
            child: Container(color: AppColors.surface, child: picker(_dismiss)),
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
    this.valueColor,
    this.title = 'Choose variation',
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

  /// Color of the selected value text (defaults to accent orange). The planner
  /// and session set rows pass green so variation matches the kg/reps cells.
  final Color? valueColor;

  /// The picker sheet's header title.
  final String title;

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
            h.showPicker(
              (dismiss) => _DropdownSheetContent<T>(
                options: options,
                value: value,
                searchable: searchable,
                onCreateNew: onCreateNew,
                createNewLabel: createNewLabel,
                title: title,
                fillHeight: true,
                onClose: dismiss,
                onSelect: onChange,
              ),
            );
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
            title: title,
            onSelect: onChange,
          );
        }
      },
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // Truncated to fit the cell — the picker and the cell's
                  // tooltip show the full name.
                  truncateName(_displayLabel),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w500,
                    color: hasValue
                        ? (valueColor ?? AppColors.primary)
                        : AppColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: AppColors.muted,
                ),
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
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.muted,
                  ),
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
  String title = 'Choose variation',
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
      title: title,
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
    required this.title,
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

  /// Header title — mirrors the add-exercise sheet ("Choose variation").
  final String title;

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
    // Same anatomy as the add-exercise sheet: title + close, search field,
    // container-style rows, accent create row, centered empty note.
    // The currently selected variation pins to the top, just under the
    // search bar — tapping it unselects. While one is selected, the
    // "No Variation" entry hides (the pinned row IS the way back to none).
    final selectedOpt = widget.value != null
        ? widget.options.where((o) => o.value == widget.value).firstOrNull
        : null;
    final list = ListView(
      shrinkWrap: !widget.fillHeight,
      children: [
        if (selectedOpt != null)
          _row(
            selectedOpt,
            onTap: () {
              widget.onClose();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onSelect(null);
              });
            },
          ),
        for (final opt in _filtered)
          if (opt.value != widget.value &&
              (opt.value != null || widget.value == null))
            _row(opt),
        // Create only surfaces once the user has typed — no standalone
        // "New Variation" button when the picker is idle.
        if (widget.onCreateNew != null && _query.trim().isNotEmpty)
          _createRow(),
        if (_filtered.isEmpty && _query.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Text(
                'No variations found',
                style: AppFonts.ui(fontSize: 13, color: AppColors.muted),
              ),
            ),
          ),
      ],
    );

    final header = Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            style: AppFonts.ui(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        GestureDetector(
          onTap: widget.onClose,
          child: Icon(Icons.close, size: 20, color: AppColors.muted),
        ),
      ],
    );
    final search = TextField(
      autofocus: true,
      style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
      decoration: InputDecoration(
        hintText: 'Search variations…',
        hintStyle: AppFonts.ui(color: AppColors.muted),
        prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
      onChanged: (v) => setState(() => _query = v),
    );

    if (widget.fillHeight) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpacing.lg),
              search,
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: list),
            ],
          ),
        ),
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpacing.lg),
              search,
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: list,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// An option row in the add-exercise sheet's container style — the
  /// soft-highlight border + check marks the currently selected one.
  Widget _row(DropdownOption<T> opt, {VoidCallback? onTap}) {
    final selected = opt.value == widget.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap:
            onTap ??
            () {
              widget.onClose();
              // Defer selection past the frame so the picker dismiss
              // completes before any parent rebuild from the selection.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onSelect(opt.value);
              });
            },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  opt.label,
                  style: AppFonts.ui(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.check, size: 18, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The accent create row — "+ Create "query"" for whatever the user typed.
  Widget _createRow() {
    final query = _query.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          widget.onClose();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onCreateNew!(_query);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            '+ Create "$query"',
            style: AppFonts.ui(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
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
              strokeWidth: 1.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Creating…',
              style: AppFonts.ui(
                fontSize: AppTextStyles.md,
                color: AppColors.muted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
