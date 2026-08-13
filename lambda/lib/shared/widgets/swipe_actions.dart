import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';

/// One action button exposed in a [SwipeActions] drawer.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

const _buttonWidth = 64.0;

/// Wraps [child] with a left-swipe-to-reveal action drawer.
///
/// A thin accent line sits on the right edge of [child] and fades as the card
/// is dragged left, revealing one or two fixed-width action buttons behind it.
/// Release past 50 % or a fast-enough flick snaps the drawer fully open;
/// otherwise it closes.  Tapping an open drawer closes it immediately.
///
/// The entire widget is clipped to [borderRadius] so action buttons never
/// bleed through rounded card corners.  The indicator and action button area
/// are inset by the same amount so they stay inside the flat part of the edge.
/// Defaults to [AppRadius.lg] (12), which is the largest corner radius used by
/// child cards; `AppCard` uses the same value, and set rows use
/// [AppRadius.md] (8) — 12 is safe for both.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.borderRadius = AppRadius.lg,
  });

  final Widget child;
  final List<SwipeAction> actions;

  /// Clip radius for the whole widget — keeps action buttons from showing
  /// through the child's rounded corners.  Also used as the vertical inset
  /// for the indicator stripe and action button area.
  final double borderRadius;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 0,
  );

  double get _drawerWidth => widget.actions.length * _buttonWidth;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------

  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;
    _ctrl.value =
        (_ctrl.value - details.delta.dx / _drawerWidth).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else if (velocity > 300) {
      _close();
    } else if (_ctrl.value > 0.5) {
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else {
      _close();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;

    final r = widget.borderRadius;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // ClipRRect is the key fix: without it, the outer Stack's action
        // buttons bleed through the child's rounded corners.  A single clip
        // on the whole widget keeps every layer clean.
        return ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Stack(
            children: [
              // ── Action buttons (behind the card) ──────────────────────
              // Opacity tracks the drawer position: invisible at rest, so
              // child effects like PressSquash 75 % opacity on tap-hold
              // don't reveal the buttons through a semi-transparent card.
              Positioned.fill(
                child: Opacity(
                  opacity: _ctrl.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.actions.map(_actionButton).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Card + indicator (slides as a unit) ────────────────────
              Transform.translate(
                offset: Offset(-_ctrl.value * _drawerWidth, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: _handleDragEnd,
                  onTap: _ctrl.value > 0 ? _close : null,
                  child: Stack(
                    children: [
                      widget.child,

                      // Indicator hairline at the right edge, inset from the
                      // top & bottom so it stays on the flat part of the card.
                      // A plain 1px line in the border color — just enough to
                      // say "swipable" without competing with the content.
                      Positioned(
                        top: r,
                        bottom: r,
                        right: 0,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 1.0 - _ctrl.value,
                            child: Container(width: 1, color: AppColors.border),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton(SwipeAction action) {
    return SizedBox(
      width: _buttonWidth,
      child: GestureDetector(
        onTap: () {
          _close();
          action.onTap();
        },
        child: Container(
          color: action.color,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 16, color: Colors.white),
              const SizedBox(height: 2),
              Text(
                action.label,
                style: AppFonts.ui(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
