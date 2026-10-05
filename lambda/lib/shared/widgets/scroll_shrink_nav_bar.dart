import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';

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
/// shrinks and fades while the content scrolls down, and springs back the
/// moment the user scrolls up.
///
/// UI only — taps come out of [onTap] and navigation stays with the caller.
/// Wrap the page body, and have the scrollable and the bar share one
/// [controller] (that is where the direction is read from):
///
/// ```dart
/// Scaffold(
///   body: ScrollShrinkNavBar(
///     controller: _controller,
///     currentIndex: _index,
///     onTap: (i) => setState(() => _index = i),
///     items: items,
///     child: ListView(controller: _controller, …),
///   ),
/// )
/// ```
///
/// Give the end of the scrollable [contentInset] worth of padding so its last
/// item can clear the bar.
class ScrollShrinkNavBar extends StatefulWidget {
  const ScrollShrinkNavBar({
    super.key,
    required this.controller,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.child,
  });

  /// The scroll position the bar follows — the same one the [child] scrolls.
  final ScrollController controller;

  final int currentIndex;

  final ValueChanged<int> onTap;

  final List<ScrollShrinkNavItem> items;

  /// The page body. Painted under the bar, which is what the blur samples.
  final Widget child;

  /// Bar height at full size.
  static const double expandedHeight = 56;

  /// Bar height when the page is scrolled down.
  static const double collapsedHeight = 42;

  /// The bar shrinks as one piece — width and height at the same rate — so
  /// the side margins open up exactly as far as the height drops.
  static double get collapsedScale => collapsedHeight / expandedHeight;

  /// Side margins — the bar floats rather than touching the screen edges.
  static const double sideMargin = AppSpacing.lg;

  /// Gap between the bar and the top of the bottom safe area; the bar never
  /// reaches into the home-indicator strip.
  static const double floatGap = AppSpacing.sm;

  /// Corner radius of the floating bar.
  static const double cornerRadius = 24;

  /// Bottom padding a scrollable needs so its last item clears the bar.
  static double contentInset(BuildContext context) =>
      expandedHeight +
      floatGap +
      MediaQuery.paddingOf(context).bottom +
      AppSpacing.lg;

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

  double? _lastOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollShrinkNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _lastOffset = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _t.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final offset = position.pixels;
    final last = _lastOffset;
    _lastOffset = offset;
    if (last == null) return;

    // Waiting on the first sample above, and ignoring bounce: neither is the
    // user asking the bar to move.
    if (position.outOfRange) return;

    final delta = offset - last;
    if (offset <= position.minScrollExtent + 8) {
      _expand();
    } else if (delta > 1.5) {
      _collapse();
    } else if (delta < -1.5) {
      _expand();
    }
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: ScrollShrinkNavBar.sideMargin,
          right: ScrollShrinkNavBar.sideMargin,
          bottom: bottomInset + ScrollShrinkNavBar.floatGap,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value;
              return Transform.scale(
                // Uniform, and anchored at the bottom edge so the bar keeps
                // floating in place while it recedes.
                scale: ScrollShrinkNavBar.collapsedScale +
                    (1 - ScrollShrinkNavBar.collapsedScale) * t,
                alignment: Alignment.bottomCenter,
                child: _buildBar(context, t),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Paints the bar at full size: the size change is a [Transform.scale] over
  /// the finished box, so what is left for [t] here is the bar's *state* —
  /// tint, border and opacity.
  Widget _buildBar(BuildContext context, double t) {
    final radius = BorderRadius.circular(ScrollShrinkNavBar.cornerRadius);
    return DecoratedBox(
      // Shadow lives outside the clip — inside it would be cut off.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20 + 0.08 * t),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Semi-transparent, and a little more so when shrunk — the page
              // showing through is the point of the blur.
              color: AppColors.bg.withValues(alpha: 0.55 + 0.17 * t),
              borderRadius: radius,
              // A light rim, not the house hairline: `border` is all but
              // invisible against blurred dark content, so the edge is drawn
              // in the foreground cream instead.
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.16 + 0.14 * t),
                width: 1,
              ),
            ),
            child: SizedBox(
              height: ScrollShrinkNavBar.expandedHeight,
              child: Opacity(
                opacity: 0.55 + 0.45 * t,
                child: Row(
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
                ),
              ),
            ),
          ),
        ),
      ),
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
