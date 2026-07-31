import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/styles/app_spacing.dart';

class BottomNavItem {
  const BottomNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

const _navItems = [
  BottomNavItem(label: 'Statistics', icon: Icons.bar_chart, route: '/statistics'),
  BottomNavItem(label: 'Logs',       icon: Icons.list_alt,  route: '/logs'),
  BottomNavItem(label: 'Session',    icon: Icons.play_circle_outline, route: '/session'),
  BottomNavItem(label: 'Exercises',  icon: Icons.fitness_center, route: '/exercises'),
  BottomNavItem(label: 'Profile',    icon: Icons.person_outline, route: '/profile'),
  BottomNavItem(label: 'Dev',        icon: Icons.code,      route: '/dev'),
];

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentRoute,
    required this.onTap,
  });

  final String currentRoute;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: _navItems.map((item) {
            final isActive = currentRoute.startsWith(item.route);
            final color = isActive ? AppColors.accent : AppColors.muted;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(item.route),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 24, color: color),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.xs,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
