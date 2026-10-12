import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_spacing.dart';
import 'container_styles.dart';

/// The app's floating bottom container — the nav bar's pill, as an element.
///
/// A rounded, translucent, blurred surface that hovers inside the screen edges
/// and above the bottom safe area. The nav bar is its first tenant; it is not
/// its only one. Anything that belongs at the floor of the screen without
/// owning its full width wears the same container — a running review's own
/// controls, a persistent notification, any screen whose navbar is suppressed —
/// so the bottom of the app reads as one surface whatever is sitting there.
///
/// This is the container alone: chrome, a height, and nothing else.
/// [FloatingBarOverlay] is the arrangement that floats one over a page, and
/// [ScrollShrinkNavBar] is the nav bar built out of it.
class FloatingBar extends StatelessWidget {
  const FloatingBar({
    super.key,
    required this.child,
    this.height = barHeight,
    this.rimColor,
  });

  /// The bar's content, laid out across the container. One row's worth by
  /// default, per [height].
  final Widget child;

  final double height;

  /// The colour of the container's rim. Null keeps the floor's own —
  /// [floatingRim], the faint cream every surface here wears. A bar passes a
  /// colour when it has something to SAY: the editor's counts wear the accent
  /// while they show the record instead of the plan, so what is on screen is
  /// legible from the floor alone.
  final Color? rimColor;

  /// Height of a bar at full size.
  static const double barHeight = 56;

  /// Side margins — the bar floats rather than touching the screen edges.
  static const double sideMargin = AppSpacing.lg;

  /// Gap between the bar and the top of the bottom safe area; the bar never
  /// reaches into the home-indicator strip.
  static const double floatGap = AppSpacing.sm;

  /// Corner radius of the floating bar.
  static const double cornerRadius = 24;

  @override
  Widget build(BuildContext context) {
    return FloatingGlass(
      radius: cornerRadius,
      rimColor: rimColor,
      child: SizedBox(height: height, child: child),
    );
  }
}

/// The glass every floating surface wears: the nav bar's pill, a review's bar.
///
/// One recipe, because these things float over the content — a surface styled
/// apart from the others on the same layer reads as a second, unrelated thing
/// hovering nearby, which is the opposite of what a floor made of one surface
/// says. Anything that floats belongs here rather than hand-rolling the blur.
/// The controls standing on that layer are drawn flat with the same rim
/// (`ContainerTone.outlineBright`) instead — they share the edge, not the
/// glass.
class FloatingGlass extends StatelessWidget {
  const FloatingGlass({
    super.key,
    required this.child,
    required this.radius,
    this.rimColor,
  });

  final Widget child;

  /// Corner radius. A circle passes half its width.
  final double radius;

  /// The colour of the rim. Null keeps the floating layer's own —
  /// [floatingRim], the light cream every surface on the blurred floor shares.
  /// A colour is for a surface that is saying something rather than simply
  /// floating: the editor's counts turn accent while they hold the record.
  final Color? rimColor;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      // Shadow lives outside the clip — inside it would be cut off.
      decoration: BoxDecoration(
        borderRadius: corners,
        // The shared floating recipe — the toolbar menus wear the same one.
        boxShadow: floatingShadow,
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Semi-transparent the whole time — the page showing through is
              // the point of the blur.
              color: AppColors.bg.withValues(alpha: 0.72),
              borderRadius: corners,
              // A light rim, not the house hairline: `border` is all but
              // invisible against blurred dark content, so the edge is drawn
              // in the foreground cream instead — [ContainerTone.outlineBright],
              // the rim the flat controls on this layer wear too.
              border: Border.all(color: rimColor ?? floatingRim),
            ),
            // A Material ancestor for whatever is carried, and the reason it is
            // part of the container rather than each caller's business: these
            // float ABOVE the page, outside the Scaffold's own Material. Text
            // down here would otherwise inherit MaterialApp's error style — the
            // debug yellow double underline — which is exactly what a review's
            // labels showed before this moved in.
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// Floats a bar over the bottom of a page.
///
/// The bar paints *over* [child] rather than being laid out beside it, which
/// is what lets content scroll under the blur. Give the end of the scrollable
/// [contentInset] worth of padding or its last item ends up underneath.
class FloatingBarOverlay extends StatelessWidget {
  const FloatingBarOverlay({
    super.key,
    required this.bar,
    required this.child,
    this.above,
  });

  /// What floats. Built by the caller, because the tenants differ: the nav bar
  /// shrinks with the scroll, a review's bar does not move at all.
  final Widget bar;

  /// A second bar floating directly above [bar] — the editor's counts over the
  /// nav bar or a review's. It shares [bar]'s margins and floats on the same
  /// gap, so the floor reads as one stack however many bars are standing on
  /// it, and the page scrolls under all of them. A bar's worth of height is
  /// what [contentInset] makes room for.
  final Widget? above;

  /// The page body. Painted under the bar, which is what the blur samples.
  final Widget child;

  /// Bottom padding a scrollable under a floating bar needs so its last item
  /// clears it.
  ///
  /// Zero where there is no bar — a page built under a bar answers for the
  /// bar, and the same page opened full-screen (Training Logs, say), answers
  /// nothing, so one screen can serve both without a flag.
  static double contentInset(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_FloatingBarScope>();
    if (scope == null) return 0;
    return FloatingBar.barHeight +
        scope.aboveInset +
        FloatingBar.floatGap +
        MediaQuery.paddingOf(context).bottom +
        AppSpacing.lg;
  }

  @override
  Widget build(BuildContext context) {
    // A bar stacked above is a bar's height plus the gap it floats on: bars
    // stack at the rhythm they float at.
    final aboveInset =
        above == null ? 0.0 : FloatingBar.barHeight + FloatingBar.floatGap;
    return Stack(
      children: [
        _FloatingBarScope(aboveInset: aboveInset, child: child),
        Positioned(
          left: FloatingBar.sideMargin,
          right: FloatingBar.sideMargin,
          bottom: MediaQuery.paddingOf(context).bottom + FloatingBar.floatGap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Stretched, not centred: every bar on the floor takes the full
            // width between the margins. A bar is a bar, whatever its content
            // measures, and two of them stacked have to be the same width —
            // a narrow one would float as a separate object beside the stack
            // rather than a storey of it.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (above != null) ...[
                above!,
                const SizedBox(height: FloatingBar.floatGap),
              ],
              bar,
            ],
          ),
        ),
      ],
    );
  }
}

/// Tells the subtree below that a bar is painting over it, and how much more
/// than one bar is stacked there. Exists only so
/// [FloatingBarOverlay.contentInset] can answer from the tree instead of from
/// a flag every caller would have to thread through.
class _FloatingBarScope extends InheritedWidget {
  const _FloatingBarScope({required this.aboveInset, required super.child});

  /// Height claimed by a second bar above the floating one, its gap included.
  /// Zero when the floor holds one bar.
  final double aboveInset;

  @override
  bool updateShouldNotify(covariant _FloatingBarScope oldWidget) =>
      oldWidget.aboveInset != aboveInset;
}
