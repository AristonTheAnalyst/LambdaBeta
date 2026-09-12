import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
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
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Optional tint — e.g. [AppColors.plannedBg] for planned-session cards.
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: lambdaBox(ContainerTone.surface).copyWith(
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
