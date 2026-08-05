import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../programs/view/program_library_screen.dart';
import '../../programs/view/workout_library_screen.dart';

/// Exercises hub: two tabs — Workouts (standalone planned sessions) and
/// Programs — plus quick links to the exercise library and guide.
class ExerciseHubScreen extends StatefulWidget {
  const ExerciseHubScreen({super.key});

  @override
  State<ExerciseHubScreen> createState() => _ExerciseHubScreenState();
}

class _ExerciseHubScreenState extends State<ExerciseHubScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Exercise Configuration'),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                _quickLink('Library', Icons.fitness_center, '/exercises/library'),
                const SizedBox(width: AppSpacing.md),
                _quickLink('Guide', Icons.menu_book_outlined, '/exercises/guide'),
              ],
            ),
          ),
          SlideTabBar(
            tabs: const ['Workouts', 'Programs'],
            activeIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: _tab == 0
                ? const WorkoutLibraryScreen()
                : const ProgramLibraryScreen(),
          ),
        ],
      ),
    );
  }

  Widget _quickLink(String label, IconData icon, String route) {
    return Expanded(
      child: AppCard(
        onTap: () => context.push(route),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}
