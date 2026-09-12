import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../programs/view/program_library_screen.dart';
import '../../programs/view/workout_library_screen.dart';
import 'exercise_library_screen.dart';

/// Exercises hub: four tabs — Exercises, Variations, Workouts (standalone
/// planned sessions), Programs — plus an ⓘ guide icon in the header.
/// The library's Exercises/Variations tabs are embedded first; the guide is
/// no longer a quick link, just the header information icon.
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
          PageHeader(
            title: 'Library',
            right: GestureDetector(
              onTap: () => context.push('/exercises/guide'),
              child: Icon(
                Icons.info_outline,
                size: 22,
                color: AppColors.accent,
              ),
            ),
          ),
          SlideTabBar(
            tabs: const ['Exercises', 'Variations', 'Workouts', 'Programs'],
            activeIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                ExerciseLibraryScreen(embedded: true, initialTab: 0),
                ExerciseLibraryScreen(embedded: true, initialTab: 1),
                WorkoutLibraryScreen(showHeader: false),
                ProgramLibraryScreen(showHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
