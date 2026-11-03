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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
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
                          color: isActive
                              ? AppColors.primary
                              : AppColors.inkSecondary,
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

/// One glyph in a [SlideIconTabBar] — the icon and the word it stands for,
/// which rides only the semantics (the header above names the active tab).
class SlideIconTab {
  const SlideIconTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The icon half of the strip (2026-10-31): the same even split, hairline
/// base and active underline as [SlideTabBar], with glyphs in place of the
/// words. The Library uses it so five tabs fit without shrinking their
/// labels — and the page header names whichever tab is open, so nothing is
/// lost when the words come off the strip.
class SlideIconTabBar extends StatelessWidget {
  const SlideIconTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  final List<SlideIconTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == activeIndex;
          final tab = tabs[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                selected: isActive,
                label: tab.label,
                child: Container(
                  // 22 + 11 × 2 = the 44pt target floor.
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isActive
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Icon(
                    tab.icon,
                    size: 22,
                    color: isActive
                        ? AppColors.primary
                        : AppColors.inkSecondary,
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
