import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';

/// One action button exposed in a [SwipeActions] drawer.
class SwipeAction {
  const SwipeAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

const _swipeButtonWidth = 64.0;

/// Swipe-left-to-reveal action drawer (delete, duplicate, …) tucked behind
/// [child] — snaps fully open or closed on release rather than resting
/// part-way.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, required this.actions});

  final Widget child;
  final List<SwipeAction> actions;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 0);

  double get _drawerWidth => widget.actions.length * _swipeButtonWidth;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;
    _ctrl.value = (_ctrl.value - details.delta.dx / _drawerWidth).clamp(0.0, 1.0);
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

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Action buttons behind the card, right-aligned — the card's child
            // covers exactly this width when open, so no gap shows.
            Positioned.fill(
              child: Row(
                children: [
                  const Spacer(),
                  ...widget.actions.map((a) => SizedBox(
                        width: _swipeButtonWidth,
                        child: GestureDetector(
                          onTap: () {
                            _close();
                            a.onTap();
                          },
                          child: Container(
                            color: a.color,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(a.icon, size: 16, color: Colors.white),
                                const SizedBox(height: 2),
                                Text(a.label,
                                    style: AppFonts.ui(
                                        fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            ),
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
                    // Swipe hint: solid line on the card's right edge, slides
                    // with the card. Inset by the corner radius so it stays on
                    // the card's flat edge instead of bleeding over the rounded
                    // corners and showing the action color behind them.
                    Positioned(
                      top: AppRadius.lg,
                      bottom: AppRadius.lg,
                      right: 0,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 1 - _ctrl.value,
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.6),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(2),
                                bottomLeft: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
