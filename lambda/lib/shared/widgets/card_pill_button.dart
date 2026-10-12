import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import './container_styles.dart';

/// The card-header pill button shared by the three session surfaces — the
/// Lessons / History / PRs chrome. Greyed (`enabled` false) renders the
/// placeholder state (the PRs placeholder, the planner's disabled pills).
class CardPillButton extends StatelessWidget {
  const CardPillButton({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.enabled = true,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Active pills get the glass recipe in their semantic color —
        // the same chrome as GlassButton and every other pressable.
        decoration: active
            ? glassBox(c, radius: 6)
            : BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
        child: Row(
          // Fill the expanded button and center its content.
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: enabled
                  ? (active ? c : AppColors.muted)
                  : AppColors.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 5),
            // Flexible so three pills sharing a card row shrink the label
            // instead of overflowing (the icon stays fixed).
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.mono(
                  fontSize: 13,
                  letterSpacing: 0.4,
                  color: enabled
                      ? (active ? c : AppColors.muted)
                      : AppColors.muted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
