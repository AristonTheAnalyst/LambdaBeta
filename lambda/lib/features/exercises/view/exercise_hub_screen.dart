import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../data/models/custom_exercise.dart';
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
  const ExerciseHubScreen({
    super.key,
    this.userId,
    this.readOnly = false,
    this.canDelete = true,
    this.openExercise,
    this.showReviews = true,
  });

  /// Whose library this is. Null = the signed-in user (the normal mount).
  ///
  /// Non-null mounts the hub over **another user's** library — the coach
  /// reading an athlete's, paired with [readOnly] (2026-10-28).
  final String? userId;

  /// Browse only (2026-10-28): every tab hides its add, edit, duplicate,
  /// archive and delete affordances, and the taps that would open an editor
  /// are spent. Coach mode's mount, never the app's own Library.
  final bool readOnly;

  /// What an exercise tap opens. Null pushes the app's own route; coach mode
  /// passes a coach-scoped detail (2026-10-28).
  final void Function(CustomExercise exercise)? openExercise;

  /// Whether the tabs offer deletion. Coach mode passes false while keeping
  /// [readOnly] false, so the athlete's library can be created in and edited
  /// but never pruned (2026-10-28).
  final bool canDelete;

  /// Whether the Reviews tab is there. A pass is the library owner's own
  /// work, so a hub scoped to someone else's library drops it (2026-10-28).
  final bool showReviews;

  @override
  State<ExerciseHubScreen> createState() => _ExerciseHubScreenState();
}

/// One tab the hub draws: its strip label, the ⓘ copy that explains it, and
/// the IndexedStack page it shows.
typedef _HubTab = ({
  String label,
  String title,
  IconData icon,
  String body,
  int page,
});

class _ExerciseHubScreenState extends State<ExerciseHubScreen> {
  int _tab = 0;

  /// The tabs in force, in strip order — the one list the strip, the stack
  /// and the header's ⓘ all read, so the three can never disagree about
  /// which tab is which (2026-10-28).
  ///
  /// The body of each entry is the caption the tabs used to carry above
  /// their lists, said once and where it is asked for — the lists stay for
  /// the things in them.
  ///
  /// A tab's [page] is not its index: Exercises and Variations share page 0,
  /// because ONE library instance serves both (2026-10-13). Reviews, being
  /// the owner's own passes, is absent when [ExerciseHubScreen.showReviews]
  /// is false, which shifts Goals onto page 2.
  List<_HubTab> get _tabs => [
    (
      label: 'Exercises',
      title: 'Exercises',
      icon: Icons.fitness_center,
      body:
          'Every movement you can log. Create an exercise, open one to see '
          'its history and PRs, or archive the ones you no longer use.',
      page: 0,
    ),
    (
      label: 'Variations',
      title: 'Variations',
      icon: Icons.tune,
      body:
          'Modifiers a set can carry — a grip, a pause, a tempo. The list is '
          'shared by every exercise; pick one while logging a set.',
      page: 0,
    ),
    (
      label: 'Workouts',
      title: 'Workouts',
      icon: Icons.assignment_outlined,
      body:
          'Reusable session templates: the exercises and target sets you '
          'plan to do. Start one from the Session tab, or keep it as a '
          'reference.',
      page: 1,
    ),
    if (widget.showReviews)
      (
        label: 'Reviews',
        title: 'Reviews',
        icon: Icons.rate_review_outlined,
        body:
            'A pass over the workouts and goals you pick. Open each workout, '
            'make changes, add notes, then finish — the record keeps what you '
            'decided.',
        page: 2,
      ),
    (
      label: 'Goals',
      title: 'Goals',
      icon: Icons.flag_outlined,
      body:
          'A weight × reps target on one exercise — a set to beat. Every '
          'logged set is measured against it, and a hit shows the set that '
          'did it.',
      page: widget.showReviews ? 3 : 2,
    ),
  ];

  /// The stack pages, in the order [_tabs]' `page` fields index them.
  List<Widget> _pages(int activeTab) => [
    ExerciseLibraryScreen(
      embedded: true,
      panel: activeTab <= 1 ? activeTab : 0,
      userId: widget.userId,
      readOnly: widget.readOnly,
      canDelete: widget.canDelete,
      openExercise: widget.openExercise,
    ),
    WorkoutLibraryScreen(
      showHeader: false,
      userId: widget.userId,
      readOnly: widget.readOnly,
      canDelete: widget.canDelete,
    ),
    if (widget.showReviews)
      ReviewsScreen(
        showHeader: false,
        userId: widget.userId,
        canDelete: widget.canDelete,
      ),
    GoalsScreen(
      showHeader: false,
      userId: widget.userId,
      readOnly: widget.readOnly,
      canDelete: widget.canDelete,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    // A host that drops Reviews under an open hub can leave the index past
    // the shortened strip — read the last tab instead of throwing.
    final active = _tab < tabs.length ? _tab : tabs.length - 1;
    final tab = tabs[active];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Library',
            right: InfoButton(title: tab.title, body: tab.body, icon: tab.icon),
          ),
          SlideTabBar(
            tabs: [for (final tab in tabs) tab.label],
            activeIndex: active,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            // ONE library instance serves the Exercises and Variations tabs —
            // two instances used to each fetch the whole catalog + timeline
            // on hub open (2026-10-13). Tabs 0/1 both map to page 0, with
            // `panel` telling it which of its own two panels to show.
            child: IndexedStack(index: tab.page, children: _pages(active)),
          ),
        ],
      ),
    );
  }
}
