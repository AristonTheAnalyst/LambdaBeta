import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import 'container_styles.dart';
import 'press_squash.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.background,
    this.borderColor,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// The corner — the house lg unless a caller says otherwise. The review
  /// landing's cards wear the goals' tighter md, so the workouts and the goals
  /// read as one stack of the same rows (2026-10-10).
  final double radius;

  /// Optional tint — e.g. [AppColors.plannedBg] for planned-session cards.
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: lambdaBox(ContainerTone.surface, radius: radius).copyWith(
        color: background,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    if (onTap == null) return card;
    return PressSquash(onTap: onTap!, child: card);
  }
}
