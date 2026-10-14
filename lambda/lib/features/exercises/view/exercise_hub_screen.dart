import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../goals/view/goals_screen.dart';
import '../../programs/view/program_library_screen.dart';
import '../../programs/view/workout_library_screen.dart';
import '../../reviews/view/reviews_screen.dart';
import 'exercise_library_screen.dart';

/// Exercises hub: six tabs — Exercises, Variations, Workouts (standalone
/// planned sessions), Programs, Reviews, Goals — plus an ⓘ guide icon in the
/// header. The library's Exercises/Variations tabs are embedded first; the
/// guide is no longer a quick link, just the header information icon.
///
/// Reviews and Goals sit here because neither is a thing any one program owns
/// — both are passes and targets the whole library draws from, so they belong
/// beside it. A review picks from the goals below it.
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
            tabs: const [
              'Exercises',
              'Variations',
              'Workouts',
              'Programs',
              'Reviews',
              'Goals',
            ],
            activeIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            // ONE library instance serves the Exercises and Variations tabs —
            // two instances used to each fetch the whole catalog + timeline
            // on hub open (2026-10-13). Tabs 0/1 both map to child 0, with
            // `panel` telling it which of its own two panels to show.
            child: IndexedStack(
              index: _tab <= 1 ? 0 : _tab - 1,
              children: [
                ExerciseLibraryScreen(embedded: true, panel: _tab <= 1 ? _tab : 0),
                const WorkoutLibraryScreen(showHeader: false),
                const ProgramLibraryScreen(showHeader: false),
                const ReviewsScreen(showHeader: false),
                const GoalsScreen(showHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
