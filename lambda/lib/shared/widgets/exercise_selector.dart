import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';

/// The workout exercise selector — a field that opens an anchored popover
/// over the screen: the selected exercise shows highlighted, up/down arrows
/// reorder, Add Exercise is pinned at the bottom, and holding the X for one
/// second requests deletion (the caller shows the warning). The caller owns
/// the list; every action reports back through callbacks.
class ExerciseSelector extends StatefulWidget {
  const ExerciseSelector({
    super.key,
    required this.exercises,
    required this.activeIndex,
    required this.onSelect,
    required this.onMove,
    required this.onAdd,
    required this.onDeleteRequest,
  });

  /// Display names, in order.
  final List<String> exercises;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// Reorder: move [index] by [direction] (-1 up, +1 down).
  /// Null greys the reorder arrows (read-only contexts).
  final void Function(int index, int direction)? onMove;

  /// Null greys the Add Exercise row (kept visible but inert so the popover
  /// still reads complete in read-only contexts).
  final VoidCallback? onAdd;

  /// Fired after the 1-second hold on the X — the caller shows the warning
  /// dialog and performs the delete. Null hides the X entirely — a dead
  /// hold-to-delete ring would be worse than absent.
  final VoidCallback? onDeleteRequest;

  @override
  State<ExerciseSelector> createState() => _ExerciseSelectorState();
}

class _ExerciseSelectorState extends State<ExerciseSelector> {
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  double _fieldWidth = 0;
  bool _open = false;

  void _close() {
    _portal.hide();
    if (_open) setState(() => _open = false);
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _fieldWidth = box?.size.width ?? 0;
      _open = true;
    });
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // The field fills the full width its parent offers.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Left/right flanking arrows — step between exercises without
            // opening the popover. Greyed at the ends of the list.
            _arrow(
              Icons.keyboard_arrow_left,
              widget.exercises.length > 1 && widget.activeIndex > 0,
              () => widget.onSelect(widget.activeIndex - 1),
              key: const ValueKey('exercise-selector-prev'),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: CompositedTransformTarget(
                link: _link,
                child: GestureDetector(
                  key: const ValueKey('exercise-selector-field'),
                  onTap: _toggle,
                  child: Container(
                    key: _fieldKey,
                    // Glass compact — the neutral translucent treatment.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(77),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.exercises.isEmpty
                                ? ''
                                : widget.exercises[widget.activeIndex],
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Chevron right of the exercise name — the field's
                        // dropdown affordance. Points up while the popover
                        // is open.
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        if (widget.onDeleteRequest != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _HoldToDeleteX(onComplete: widget.onDeleteRequest!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _arrow(
              Icons.keyboard_arrow_right,
              widget.exercises.length > 1 &&
                  widget.activeIndex < widget.exercises.length - 1,
              () => widget.onSelect(widget.activeIndex + 1),
              key: const ValueKey('exercise-selector-next'),
            ),
          ],
        ),
        // The popover lives in the app's Overlay, anchored to the field via
        // the LayerLink — exact field width, fixed height, scrollable rows,
        // sticky Add Exercise.
        OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _open
              ? Stack(
                  children: [
                    // Scrim barrier — dims the screen behind the popover and
                    // dismisses on any tap outside it.
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _close,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    CompositedTransformFollower(
                      link: _link,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: const Offset(0, 4),
                      child: Container(
                        width: _fieldWidth,
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: lambdaBox(ContainerTone.surface, radius: AppRadius.md),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < widget.exercises.length;
                                      i++
                                    )
                                      _row(i),
                                  ],
                                ),
                              ),
                            ),
                            _addRow(),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _row(int i) {
    final selected = i == widget.activeIndex;
    return GestureDetector(
      onTap: () {
        if (selected) {
          // Already selected — just close the menu.
          _close();
          return;
        }
        widget.onSelect(i);
        _close();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // The selected exercise shows with the neutral glass highlight.
          color: selected
              ? AppColors.primary.withAlpha(26)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.exercises[i],
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            ),
            _arrow(
              Icons.keyboard_arrow_up,
              widget.onMove != null && i > 0,
              () => widget.onMove!(i, -1),
              size: 28,
              iconSize: 15,
            ),
            const SizedBox(width: 2),
            _arrow(
              Icons.keyboard_arrow_down,
              widget.onMove != null && i < widget.exercises.length - 1,
              () => widget.onMove!(i, 1),
              size: 28,
              iconSize: 15,
            ),
          ],
        ),
      ),
    );
  }

  /// Arrow button — [size] is the full tap target (icon-button 32×32 for the
  /// flanking field arrows, chevron 28×28 inside the popover rows).
  Widget _arrow(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
    Key? key,
    double size = 32,
    double iconSize = 18,
  }) {
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : () {},
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        // The glass recipe — the same chrome as every other pressable.
        decoration: enabled
            ? glassBox(AppColors.primary, radius: 6)
            : BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }

  /// Pinned at the bottom of the popover — the caller opens its own
  /// add-exercise flow. When [widget.onAdd] is null the row stays visible
  /// but renders greyed and inert, so read-only contexts keep the popover's
  /// shape without a dead action.
  Widget _addRow() {
    final enabled = widget.onAdd != null;
    final color = enabled ? AppColors.primary : AppColors.muted.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: enabled
          ? () {
              _close();
              widget.onAdd!();
            }
          : () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: enabled ? glassBox(AppColors.primary) : null,
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Add Exercise',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hold-to-delete X — the container's background and outline fill with
/// danger red over one second; once complete, fires [onComplete].
class _HoldToDeleteX extends StatefulWidget {
  const _HoldToDeleteX({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_HoldToDeleteX> createState() => _HoldToDeleteXState();
}

class _HoldToDeleteXState extends State<_HoldToDeleteX>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _progress.forward(from: 0);
    _timer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _progress.reset();
        widget.onComplete();
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    if (mounted) _progress.stop();
    if (mounted) _progress.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('exercise-selector-delete'),
      // Claims the tap arena so holding the X never triggers the field's
      // own tap (which would open the menu on release).
      onTap: () {},
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              // The hold fills the container — background and outline
              // graduate from neutral to danger as the progress advances.
              final t = _progress.value;
              return Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.transparent, AppColors.dangerBg, t),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Color.lerp(
                      AppColors.border,
                      AppColors.danger,
                      t,
                    )!,
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: Color.lerp(AppColors.muted, AppColors.primary, t),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
