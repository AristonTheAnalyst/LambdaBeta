import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../shared/widgets/info_button.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../goals/view/goals_screen.dart';
import '../../programs/view/workout_library_screen.dart';
import '../../reviews/view/reviews_screen.dart';
import 'exercise_library_screen.dart';

/// Exercises hub: five tabs — Exercises, Variations, Workouts (standalone
/// planned sessions), Reviews, Goals — each with a search-and-buttons
/// toolbar of its own, plus the header's ⓘ that explains **the tab in force**
/// (2026-10-19). The library's Exercises/Variations tabs are embedded first.
/// Programs are out of the UI for now (2026-10-26): their workouts were only
/// ever copies of regular ones and the two read as duplicates.
///
/// Reviews and Goals sit here because neither is a thing any one program owns
/// — both are passes and targets the whole library draws from, so they belong
/// beside it. A review picks from the goals below it.
///
/// The guide route stays mounted but dormant: the per-tab sheets say what a
/// tab is, where one generic guide used to.
class ExerciseHubScreen extends StatefulWidget {
  const ExerciseHubScreen({super.key});

  @override
  State<ExerciseHubScreen> createState() => _ExerciseHubScreenState();
}

class _ExerciseHubScreenState extends State<ExerciseHubScreen> {
  int _tab = 0;

  /// What the header's ⓘ says, one entry per tab in [SlideTabBar] order.
  ///
  /// The body is the caption the tabs used to carry above their lists, said
  /// once and where it is asked for — the lists stay for the things in them.
  static const _tabInfo = [
    (
      title: 'Exercises',
      icon: Icons.fitness_center,
      body:
          'Every movement you can log. Create an exercise, open one to see '
          'its history and PRs, or archive the ones you no longer use.',
    ),
    (
      title: 'Variations',
      icon: Icons.tune,
      body:
          'Modifiers a set can carry — a grip, a pause, a tempo. The list is '
          'shared by every exercise; pick one while logging a set.',
    ),
    (
      title: 'Workouts',
      icon: Icons.assignment_outlined,
      body:
          'Reusable session templates: the exercises and target sets you '
          'plan to do. Start one from the Session tab, or keep it as a '
          'reference.',
    ),
    (
      title: 'Reviews',
      icon: Icons.rate_review_outlined,
      body:
          'A pass over the workouts and goals you pick. Open each workout, '
          'make changes, add notes, then finish — the record keeps what you '
          'decided.',
    ),
    (
      title: 'Goals',
      icon: Icons.flag_outlined,
      body:
          'A weight × reps target on one exercise — a set to beat. Every '
          'logged set is measured against it, and a hit shows the set that '
          'did it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final info = _tabInfo[_tab];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Library',
            right: InfoButton(
              title: info.title,
              body: info.body,
              icon: info.icon,
            ),
          ),
          SlideTabBar(
            tabs: const [
              'Exercises',
              'Variations',
              'Workouts',
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
                ExerciseLibraryScreen(
                  embedded: true,
                  panel: _tab <= 1 ? _tab : 0,
                ),
                const WorkoutLibraryScreen(showHeader: false),
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
