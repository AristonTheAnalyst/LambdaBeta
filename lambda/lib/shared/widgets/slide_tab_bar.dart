import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_text_styles.dart';

class SlideTabBar extends StatelessWidget {
  const SlideTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  final List<String> tabs;
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
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.accent : AppColors.muted,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
