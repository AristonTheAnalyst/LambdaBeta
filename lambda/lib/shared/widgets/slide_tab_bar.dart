import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_text_styles.dart';

class SlideTabBar extends StatelessWidget {
  const SlideTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
    this.dotTabs = const <int>{},
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  /// Tab indices whose label wears the attention dot at its right — the
  /// review landing's "this half still has something unreviewed" (2026-10-10).
  /// Empty by default: a strip with nothing pending is the ordinary strip,
  /// and every other caller is that.
  final Set<int> dotTabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == activeIndex;
          // Each tab takes an even share of the width — any tab count fits
          // without overflow, and the bar reads as one divided strip.
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                // Each label scales down to its own share of the width, so a
                // crowded bar (the Library's six) shrinks the long words —
                // "Variations" — instead of clipping them. Wide bars render
                // every label at full size. A dot rides inside the same
                // FittedBox so it stays against its label at any scale.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tabs[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: isActive ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                      if (dotTabs.contains(i)) ...[
                        const SizedBox(width: 6),
                        // The accent dot: the app's orange. A mark, not a
                        // message — it says "something here is still open",
                        // and clearing it is how the tab goes quiet.
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
