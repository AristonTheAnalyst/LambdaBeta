import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import 'floating_bar.dart';

/// One destination on a [ScrollShrinkNavBar].
class ScrollShrinkNavItem {
  const ScrollShrinkNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = false,
  });

  /// Outline glyph, shown while the item is not selected.
  final IconData icon;

  /// Filled glyph, shown while it is. The swap is animated.
  final IconData activeIcon;

  /// Accessibility label — the bar itself is icon-only, Instagram-style.
  final String label;

  /// Draws the small "something new" dot in the corner.
  final bool badge;
}

/// An Instagram-style floating bar: a rounded, translucent, blurred pill
/// that hovers inside the screen's edges and above the bottom safe area. It
/// shrinks while the content scrolls down and springs back the moment the
/// user scrolls up, keeping its colour throughout — only the size moves.
///
/// The pill itself is [FloatingBar] — the app's bottom chrome, shared with
/// anything else that sits at the floor of the screen. This widget adds the
/// shrinking.
///
/// UI only — taps come out of [onTap] and navigation stays with the caller.
/// Wrap the page body; the bar reads direction from the scroll notifications
/// of whatever scrollable is under it, so no controller has to be threaded
/// through — which is what lets a shell own one bar for every page:
///
/// ```dart
/// Scaffold(
///   body: ScrollShrinkNavBar(
///     currentIndex: _index,
///     onTap: (i) => setState(() => _index = i),
///     items: items,
///     child: ListView(…),
///   ),
/// )
/// ```
///
/// The bar paints *over* the page, so give the end of the scrollable
/// [contentInset] worth of padding or its last item ends up underneath.
class ScrollShrinkNavBar extends StatefulWidget {
  const ScrollShrinkNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.child,
    this.aboveBar,
  });

  final int currentIndex;

  final ValueChanged<int> onTap;

  final List<ScrollShrinkNavItem> items;

  /// The page body. Painted under the bar, which is what the blur samples.
  final Widget child;

  /// A second bar floating above the nav bar — the editor's counts, which
  /// stand on the same floor. Only the nav bar shrinks with the scroll; what
  /// is stacked above it stays put.
  final Widget? aboveBar;

  /// Bar height at full size. The geometry lives on [FloatingBar] — the app's
  /// bottom chrome shares one container — and is re-exported here because
  /// every page that clears the bar reads its numbers from the bar.
  static const double expandedHeight = FloatingBar.barHeight;

  /// Bar height when the page is scrolled down.
  static const double collapsedHeight = 42;

  /// The bar shrinks as one piece — width and height at the same rate — so
  /// the side margins open up exactly as far as the height drops.
  static double get collapsedScale => collapsedHeight / expandedHeight;

  /// Gap between the bar and the top of the bottom safe area; the bar never
  /// reaches into the home-indicator strip.
  static const double floatGap = FloatingBar.floatGap;

  /// Bottom padding a scrollable needs so its last item clears the bar.
  static double contentInset(BuildContext context) =>
      FloatingBarOverlay.contentInset(context);

  @override
  State<ScrollShrinkNavBar> createState() => _ScrollShrinkNavBarState();
}

class _ScrollShrinkNavBarState extends State<ScrollShrinkNavBar>
    with SingleTickerProviderStateMixin {
  static const _collapseDuration = Duration(milliseconds: 200);
  static const _expandDuration = Duration(milliseconds: 260);

  /// 1 = full size, 0 = shrunk. Curved once, here, so every animated layer
  /// agrees on where the transition is.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _expandDuration,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(ScrollShrinkNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Swapping tabs is not a scroll: arrive on the new page with the bar at
    // full size rather than inheriting the last page's collapse.
    if (oldWidget.currentIndex != widget.currentIndex) _expand();
  }

  @override
  void dispose() {
    _t.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// Follows the page moving up and down. Depth is no use for telling the two
  /// apart: the Session tab keeps its list inside a horizontal pager, which
  /// puts every notification it sends at depth 1. The axis is the honest
  /// question — a sideways scroller is a child the page is not moving for.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    // Bounce at either end is the overscroll fighting back, not the user
    // asking the bar to move.
    final metrics = notification.metrics;
    if (metrics.outOfRange) return false;

    final delta = notification.scrollDelta ?? 0;
    if (metrics.pixels <= metrics.minScrollExtent + 8) {
      _expand();
    } else if (delta > 1.5) {
      _collapse();
    } else if (delta < -1.5) {
      _expand();
    }
    return false;
  }

  void _collapse() {
    if (_reveal.status != AnimationStatus.reverse) {
      _reveal.animateBack(0, duration: _collapseDuration);
    }
  }

  void _expand() {
    if (_reveal.status != AnimationStatus.forward) {
      _reveal.animateTo(1, duration: _expandDuration);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingBarOverlay(
      above: widget.aboveBar,
      bar: AnimatedBuilder(
        animation: _t,
        // Built once and handed to the builder: the bar inside does not
        // change with the animation, only the transform over it does.
        child: FloatingBar(child: _buildItems()),
        builder: (context, bar) => Transform.scale(
          // Uniform, and anchored at the bottom edge so the bar keeps
          // floating in place while it recedes.
          scale: ScrollShrinkNavBar.collapsedScale +
              (1 - ScrollShrinkNavBar.collapsedScale) * _t.value,
          alignment: Alignment.bottomCenter,
          child: bar,
        ),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.child,
      ),
    );
  }

  /// The destinations, filling the bar's width. Everything here is a constant
  /// — the only thing a scroll changes is the [Transform.scale] around the
  /// bar, so it keeps its full colour and weight as it recedes rather than
  /// fading out.
  Widget _buildItems() {
    return Row(
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Expanded(
            child: _NavButton(
              item: widget.items[i],
              selected: i == widget.currentIndex,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onTap(i);
              },
            ),
          ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ScrollShrinkNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 220),
            // A touch of overshoot — the tap should feel like a pop, not a
            // colour fading in.
            curve: Curves.easeOutBack,
            builder: (context, v, _) {
              // The overshoot is the point for scale, but alpha has no room
              // for it.
              final t = v.clamp(0.0, 1.0);
              return Transform.scale(
                scale: 1 + 0.08 * v,
                child: Container(
                  // A soft accent chip behind the selected icon. The padding
                  // is what makes it wrap the icon rather than the slot, and
                  // it stays clear of the bar's own edges.
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.18 * t),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.8, end: 1).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                            ),
                            child: child,
                          ),
                        ),
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          key: ValueKey<bool>(selected),
                          size: 24,
                          color:
                              Color.lerp(AppColors.primary, AppColors.accent, t),
                        ),
                      ),
                      if (item.badge)
                        Positioned(
                          top: -2,
                          right: -3,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.bg.withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
