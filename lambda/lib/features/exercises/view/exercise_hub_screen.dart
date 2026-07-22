import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';

class ExerciseHubScreen extends StatelessWidget {
  const ExerciseHubScreen({super.key});

  static const _sections = [
    _Section(
      route: '/exercises/library',
      label: 'Exercises & Variations',
      description: 'Create and manage exercises and variations',
      icon: Icons.fitness_center,
    ),
    _Section(
      route: '/exercises/guide',
      label: 'User Guide',
      description: 'Learn how to set up and use the app',
      icon: Icons.menu_book_outlined,
    ),
    _Section(
      route: '/exercises/programs',
      label: 'Programs',
      description: 'Structured training programs and templates',
      icon: Icons.list_alt,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Exercise Configuration'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: _sections
                    .map((s) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            onTap: () =>
                                context.push(s.route),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(s.icon,
                                      color: AppColors.accent, size: 22),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(s.label,
                                          style: TextStyle(
                                              fontSize: AppTextStyles.lg,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary)),
                                      const SizedBox(height: 2),
                                      Text(s.description,
                                          style: TextStyle(
                                              fontSize: AppTextStyles.sm,
                                              color: AppColors.muted)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 18, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section({
    required this.route,
    required this.label,
    required this.description,
    required this.icon,
  });
  final String route;
  final String label;
  final String description;
  final IconData icon;
}
