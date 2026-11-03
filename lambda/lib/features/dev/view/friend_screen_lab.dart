import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/lambda_avatar.dart';
import '../../../shared/widgets/menu_popover.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import 'exercise_lab_screen.dart';
import 'friend_lab_detail_screens.dart';
import 'lab_goal_columns.dart';
import 'lab_toolbar.dart';
import 'session_cards_screen.dart';
import 'session_lab_screen.dart';

/// A static, non-interactive prototype of the friend profile (2026-10-31).
///
/// It exists to settle the layout before the real screen changes: identity
/// left-aligned, numbers instead of a paragraph, then one strip of six —
/// the Session view and the library's own five tabs — with the person's
/// recent training under it, and every setting behind the header's `⋯`.
/// Nothing here reads a database or writes anything; the buttons are drawn
/// but spent, and the data is typed in. The Session tab's content is the
/// **ledger-chips card** from Dev → Session Cards (the design that won), so
/// the two pages can never drift.
///
/// Experiments land here first. When a direction is chosen, the real
/// `FriendProfileScreen` is rebuilt to match and this page becomes the
/// decision's record (the `/dev/visual-pairings` precedent).
class FriendScreenLab extends StatefulWidget {
  const FriendScreenLab({super.key});

  @override
  State<FriendScreenLab> createState() => _FriendScreenLabState();
}

class _FriendScreenLabState extends State<FriendScreenLab> {
  /// The strip is live in this prototype: tapping a glyph swaps the content
  /// below for that tab's preview.
  int _tab = 0;

  /// The toolbar under the strip is one element shared by every tab — for
  /// now it sorts and filters nothing, it just shows the shape.
  LabSortBy _sort = LabSortBy.newest;
  bool _descending = true;
  LabRange _range = LabRange.all;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Switches tab. The page's scroll offset and the content's minimum height
  /// (see [build]) do the rest: switched from while the strip is pinned, the
  /// new tab has at least a screen's worth below the strip, so the scroll
  /// rests on the pin in the same frame — no second pass, no jump, no
  /// jitter (2026-11-02).
  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  /// Session · the library's five, with Goals pulled forward to sit beside
  /// Variations (experiment, 2026-11-01).
  static const _tabs = <IconData>[
    LucideIcons.circlePlay,
    LucideIcons.dumbbell,
    LucideIcons.dna,
    LucideIcons.crosshair,
    LucideIcons.clipboardList,
    LucideIcons.clipboardCheck,
  ];

  static const _labels = [
    'Session',
    'Exercises',
    'Variations',
    'Goals',
    'Workouts',
    'Reviews',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Jamie',
            left: HeaderIconButton(
              icon: LucideIcons.arrowLeft,
              semanticsLabel: 'Back',
              onPressed: () {},
            ),
            // The ⋯ carries the relationship verbs — the same three doors
            // the real profile's menu will.
            right: MenuPopover(
              semanticsLabel: 'More',
              trigger: (context, open) => HeaderIconButton(
                icon: LucideIcons.ellipsis,
                semanticsLabel: 'More',
                onPressed: open,
              ),
              contentBuilder: (context, dismiss) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChoiceRow(label: 'Coaching', active: false, onTap: dismiss),
                  const SizedBox(height: AppSpacing.xs),
                  ChoiceRow(
                    label: 'Request to be a coach',
                    active: false,
                    onTap: dismiss,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ChoiceRow(
                    label: 'Request to be a client',
                    active: false,
                    onTap: dismiss,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Hold the content below the strip to at least a viewport's
                // height less the strip's own. That is exactly the room the
                // header needs to scroll away, so a short tab pins like a
                // long one — and because it is a LAYOUT constraint, the first
                // frame of a tab switch is already right: no appended tail
                // measured after the frame, no second pass, no jump, no
                // jitter (2026-11-02).
                final minContentHeight =
                    (constraints.maxHeight - _StickyToolbar._height).clamp(
                      0.0,
                      double.maxFinite,
                    );
                return CustomScrollView(
                  // No iOS bounce: an overscroll drags the pinned strip off
                  // its line for a beat before it springs back. Clamping
                  // keeps the strip exactly where it belongs at every scroll
                  // velocity.
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Instagram's header: avatar left, the three counts
                            // right, the name already in the bar ──────────────────────
                            Row(
                              children: [
                                const LambdaAvatar(size: 88),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          _stat('12', 'SESSIONS'),
                                          _stat('4', 'PRS'),
                                          _stat('3d', 'TRAINED'),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      // The bar spans the COUNTS' column, not the page:
                                      // centred label, chevron, whole width is the tap.
                                      GestureDetector(
                                        onTap: () {},
                                        behavior: HitTestBehavior.opaque,
                                        // A 40pt tap band around a 30pt pill: the look is
                                        // tight, the target is not.
                                        child: SizedBox(
                                          height: 40,
                                          child: Center(
                                            child: Container(
                                              height: 30,
                                              width: double.infinity,
                                              alignment: Alignment.center,
                                              decoration: glassBox(
                                                AppColors.primary,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Coaching',
                                                    style: AppFonts.ui(
                                                      fontSize:
                                                          AppTextStyles.sm,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    LucideIcons.chevronRight,
                                                    size: 16,
                                                    color:
                                                        AppColors.inkSecondary,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // A word about them, then the two pills that say how you
                            // stand: the relationship (Instagram's Following menu) and
                            // the coaching edge.
                            Text(
                              'Powerlifting 3× a week. Chasing a 140 squat and a calmer '
                              'bar path.',
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                height: 1.4,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                    // The strip and the bar pin together: once the header
                    // scrolls away they hold the top, and the content runs
                    // beneath them.
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyToolbar(
                        // The strip's indicator lives inside the delegate, so
                        // the active tab is part of its identity: a stale
                        // shouldRebuild froze the underline on Session.
                        tab: _tab,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── One strip: Session, then the library's five ──
                            SlideIconTabBar(
                              tabs: [
                                for (var i = 0; i < _tabs.length; i++)
                                  SlideIconTab(
                                    icon: _tabs[i],
                                    label: _labels[i],
                                  ),
                              ],
                              activeIndex: _tab,
                              onTap: _selectTab,
                            ),
                            LabToolbar(
                              search: _search,
                              sort: _sort,
                              descending: _descending,
                              range: _range,
                              onSort: (value, descending) => setState(() {
                                _sort = value;
                                _descending = descending;
                              }),
                              onRange: (value) =>
                                  setState(() => _range = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: ConstrainedBox(
                          // The content's own bottom padding belongs inside the
                          // minimum: it is part of the room a finger scrolls
                          // through.
                          constraints: BoxConstraints(
                            minHeight: minContentHeight,
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  AppSpacing.lg +
                                  ScrollShrinkNavBar.contentInset(context),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── The Session tab's content: the ledger-chips card ──────
                                // No gap here: the card's own 16pt padding is the same 16pt
                                // that separates every other block from its bottom rule, so
                                // the first content sits in the same rhythm as the rest.
                                // The design settled on Dev → Session Cards: the day in a
                                // left rail, the ratings on one line, exercises as chips
                                // with their own PR badges, at a constant height.
                                if (_tab == 0)
                                  // Newest first, the way a person's history reads. The
                                  // first card hugs the toolbar: its top padding belongs to
                                  // the card stack, not to the bar.
                                  for (final (i, sample)
                                      in ([...kSessionCardSamples]..sort(
                                            (a, b) => b.date.compareTo(a.date),
                                          ))
                                          .indexed)
                                    GestureDetector(
                                      // The card opens its own empty screen
                                      // for now (2026-11-03).
                                      onTap: () => Navigator.of(context).push(
                                        SessionLabScreen.route(sample),
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      child: LedgerChipsCard(
                                        sample: sample,
                                        // First card: the toolbar's own 8 plus this 8
                                        // makes the 16 the cards use below their rules.
                                        topPadding: i == 0
                                            ? AppSpacing.sm
                                            : AppSpacing.lg,
                                      ),
                                    )
                                else if (_tab == 1)
                                  const _ExercisePreviewList(
                                    rows: _exercisePreviews,
                                  )
                                else if (_tab == 2)
                                  const _VariationList(rows: _variationPreviews)
                                else if (_tab == 3)
                                  GoalLabColumns(
                                    complete: _completeGoals,
                                    open: _openGoals,
                                    onTap: (goal) =>
                                        Navigator.of(context).push(
                                          GoalLabScreen.route(goal.name),
                                        ),
                                  )
                                else if (_tab == 4)
                                  _WorkoutList(rows: _workoutPreviews)
                                else
                                  _ReviewList(rows: _reviewPreviews),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the header's three counts: the number over its label.
Widget _stat(String value, String label) {
  return Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: AppFonts.ui(
            fontSize: AppTextStyles.lg,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    ),
  );
}

/// A local copy of the pill, so the prototype never drags the real screen's
/// state in with it.
class CoachingPillFake extends StatelessWidget {
  const CoachingPillFake({
    super.key,
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

/// Sample rows for the five library tabs — enough to see the shape of each
/// preview, not real data.
/// One exercise, with the five numbers the preview carries: how often, how
/// much, what it won, and what the friend's goals say about it.
class _ExercisePreview {
  const _ExercisePreview(
    this.name, {
    required this.lastUsed,
    required this.sessions,
    required this.sets,
    required this.prs,
    required this.goalsMet,
    required this.goalsOpen,
  });

  final String name;
  final String lastUsed;
  final int sessions;
  final int sets;
  final int prs;
  final int goalsMet;
  final int goalsOpen;
}

const _exercisePreviews = <_ExercisePreview>[
  _ExercisePreview(
    'Back Squat',
    lastUsed: '2d ago',
    sessions: 12,
    sets: 124,
    prs: 3,
    goalsMet: 1,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Bench Press',
    lastUsed: '3d ago',
    sessions: 10,
    sets: 62,
    prs: 2,
    goalsMet: 0,
    goalsOpen: 1,
  ),
  _ExercisePreview(
    'Cable Row',
    lastUsed: '3d ago',
    sessions: 9,
    sets: 54,
    prs: 1,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Leg Press',
    lastUsed: '3d ago',
    sessions: 8,
    sets: 40,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Leg Curl',
    lastUsed: '3d ago',
    sessions: 7,
    sets: 35,
    prs: 0,
    goalsMet: 1,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Pull-ups',
    lastUsed: '5d ago',
    sessions: 6,
    sets: 30,
    prs: 2,
    goalsMet: 1,
    goalsOpen: 1,
  ),
  _ExercisePreview(
    'Overhead Press',
    lastUsed: '1w ago',
    sessions: 4,
    sets: 20,
    prs: 1,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Leg Extension',
    lastUsed: '1w ago',
    sessions: 5,
    sets: 25,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Calf Raise',
    lastUsed: '1w ago',
    sessions: 5,
    sets: 25,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Hip Thrust',
    lastUsed: '2w ago',
    sessions: 3,
    sets: 15,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 1,
  ),
  _ExercisePreview(
    'Bench Press (incline)',
    lastUsed: '2w ago',
    sessions: 2,
    sets: 10,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Seated Row',
    lastUsed: '3w ago',
    sessions: 2,
    sets: 10,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Deadlift',
    lastUsed: '3w ago',
    sessions: 7,
    sets: 28,
    prs: 2,
    goalsMet: 1,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Front Squat',
    lastUsed: '3w ago',
    sessions: 5,
    sets: 20,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 1,
  ),
  _ExercisePreview(
    'Dip',
    lastUsed: '4w ago',
    sessions: 4,
    sets: 16,
    prs: 1,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Lateral Raise',
    lastUsed: '4w ago',
    sessions: 6,
    sets: 24,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Face Pull',
    // Last year: the row's written date carries its year (2026-11-02).
    lastUsed: '52w ago',
    sessions: 3,
    sets: 12,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Lunge',
    lastUsed: '5w ago',
    sessions: 2,
    sets: 8,
    prs: 0,
    goalsMet: 1,
    goalsOpen: 0,
  ),
  _ExercisePreview(
    'Dead Bug',
    lastUsed: '6w ago',
    sessions: 2,
    sets: 6,
    prs: 0,
    goalsMet: 0,
    goalsOpen: 0,
  ),
];

/// One workout, the day it was last logged, and how it has been used: the
/// sessions it has run, the PRs it has won and the goals it has hit.
class _WorkoutPreview {
  const _WorkoutPreview(
    this.name,
    this.lastLogged, {
    required this.sessions,
    required this.prs,
    required this.goals,
  });

  final String name;
  final DateTime lastLogged;
  final int sessions;
  final int prs;
  final int goals;
}

/// Most recently logged first — the app's own workout order (2026-11-02).
final _workoutPreviews = <_WorkoutPreview>[
  _WorkoutPreview(
    'Leg Day',
    DateTime(2026, 10, 31),
    sessions: 8,
    prs: 3,
    goals: 2,
  ),
  _WorkoutPreview(
    'Push A + Accessories',
    DateTime(2026, 10, 28),
    sessions: 6,
    prs: 2,
    goals: 1,
  ),
  _WorkoutPreview(
    'Full Body',
    DateTime(2026, 10, 26),
    sessions: 7,
    prs: 1,
    goals: 0,
  ),
  _WorkoutPreview(
    'Upper Hypertrophy',
    DateTime(2026, 10, 16),
    sessions: 5,
    prs: 2,
    goals: 1,
  ),
  _WorkoutPreview(
    'Lower Power',
    DateTime(2026, 10, 12),
    sessions: 4,
    prs: 1,
    goals: 0,
  ),
  _WorkoutPreview(
    'Push B',
    DateTime(2026, 10, 10),
    sessions: 4,
    prs: 0,
    goals: 1,
  ),
  _WorkoutPreview(
    'Leg Day B',
    DateTime(2026, 10, 5),
    sessions: 3,
    prs: 1,
    goals: 0,
  ),
  _WorkoutPreview(
    'Upper Power',
    DateTime(2026, 9, 28),
    sessions: 3,
    prs: 1,
    goals: 1,
  ),
  _WorkoutPreview(
    'Arms + Delts',
    DateTime(2026, 9, 21),
    sessions: 2,
    prs: 0,
    goals: 0,
  ),
  _WorkoutPreview(
    'Conditioning',
    DateTime(2026, 9, 14),
    sessions: 2,
    prs: 0,
    goals: 0,
  ),
  _WorkoutPreview(
    'Push C',
    DateTime(2026, 9, 7),
    sessions: 2,
    prs: 0,
    goals: 1,
  ),
  _WorkoutPreview(
    'Leg Day C',
    DateTime(2026, 8, 31),
    sessions: 1,
    prs: 0,
    goals: 0,
  ),
  _WorkoutPreview(
    'Upper B',
    DateTime(2026, 8, 10),
    sessions: 1,
    prs: 0,
    goals: 0,
  ),
  // Last year: the line carries the year (2026-11-02).
  _WorkoutPreview(
    'Lower C',
    DateTime(2025, 10, 14),
    sessions: 1,
    prs: 0,
    goals: 0,
  ),
];

/// One recorded pass: its name, the day it was finished, the workouts it
/// covered, and what the pass won — PRs and goals hit.
class _ReviewPreview {
  const _ReviewPreview(
    this.name,
    this.date,
    this.workouts, {
    required this.prs,
    required this.goals,
  });

  final String name;
  final DateTime date;
  final List<String> workouts;
  final int prs;
  final int goals;
}

final _reviewPreviews = <_ReviewPreview>[
  _ReviewPreview('October pass', DateTime(2026, 10, 31), [
    'Leg Day',
    'Push A + Accessories',
    'Full Body',
    'Lower Power',
  ], prs: 6, goals: 3),
  _ReviewPreview('September pass', DateTime(2026, 9, 1), [
    'Upper Hypertrophy',
    'Lower Power',
    'Push B',
  ], prs: 4, goals: 2),
  _ReviewPreview('August pass', DateTime(2026, 8, 3), [
    'Leg Day B',
    'Upper Power',
    'Arms + Delts',
    'Conditioning',
    'Push C',
  ], prs: 7, goals: 2),
  _ReviewPreview('July pass', DateTime(2026, 6, 30), [
    'Push A + Accessories',
    'Full Body',
    'Leg Day',
    'Upper Hypertrophy',
  ], prs: 5, goals: 1),
  _ReviewPreview('June pass', DateTime(2026, 6, 2), [
    'Lower Power',
    'Push B',
    'Leg Day B',
  ], prs: 3, goals: 2),
  _ReviewPreview('May pass', DateTime(2026, 4, 28), [
    'Upper Power',
    'Arms + Delts',
    'Conditioning',
    'Push C',
    'Leg Day C',
  ], prs: 6, goals: 1),
  _ReviewPreview('April pass', DateTime(2026, 3, 31), [
    'Push A + Accessories',
    'Upper Hypertrophy',
    'Lower Power',
    'Push B',
  ], prs: 4, goals: 1),
  _ReviewPreview('March pass', DateTime(2026, 3, 3), [
    'Leg Day',
    'Full Body',
    'Upper Power',
    'Leg Day B',
    'Arms + Delts',
    'Conditioning',
  ], prs: 5, goals: 2),
  _ReviewPreview('February pass', DateTime(2026, 2, 2), [
    'Push C',
    'Leg Day C',
    'Upper B',
    'Lower C',
  ], prs: 3, goals: 0),
  _ReviewPreview('January pass', DateTime(2025, 12, 31), [
    'Push A + Accessories',
    'Full Body',
    'Leg Day',
  ], prs: 2, goals: 1),
  _ReviewPreview('Start of the year', DateTime(2026, 1, 2), [
    'Upper Hypertrophy',
    'Lower Power',
    'Push B',
    'Leg Day B',
    'Upper Power',
  ], prs: 4, goals: 1),
  _ReviewPreview('The first pass', DateTime(2025, 10, 14), [
    'Leg Day',
    'Push A + Accessories',
    'Full Body',
    'Lower Power',
  ], prs: 2, goals: 0),
];

/// The Reviews tab in the session ledger's shape: the same date rail, the
/// review's name where a session's plan name sits, its PRs and goals hit
/// beside it, and the workouts it covered stacked where the exercise pills
/// would be. No stars: a pass is a record, not a session (2026-11-03).
class _ReviewList extends StatelessWidget {
  const _ReviewList({required this.rows});

  final List<_ReviewPreview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final review in rows)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              ReviewLabScreen.route(review.name),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _reviewRail(review.date),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.only(right: AppSpacing.md),
                    color: AppColors.border,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                review.name,
                                maxLines: 2,
                                style: AppFonts.ui(
                                  fontSize: AppTextStyles.lg,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _MetricCell(
                              LucideIcons.trophy,
                              '${review.prs}',
                              lit: AppColors.accent,
                              width: 48,
                            ),
                            const SizedBox(width: 10),
                            _MetricCell(
                              LucideIcons.crosshair,
                              '${review.goals}',
                              lit: AppColors.success,
                              width: 48,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final workout in review.workouts)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              workout,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// The review's date rail, the session card's own: the day and month, then
/// the weekday — or the year when it is not this one — with the day count
/// under it inside the 99-day window (2026-11-03).
Widget _reviewRail(DateTime date) {
  final days = railDaysReading(date);
  final lastLine = days == null && date.year != DateTime.now().year
      ? '${date.year}'
      : _weekday(date);
  return SizedBox(
    width: 62,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${date.day}',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xxl,
            fontWeight: FontWeight.w600,
            height: 1.0,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _months[date.month - 1].toUpperCase(),
          style: AppFonts.mono(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.accent,
          ),
        ),
        Text(
          lastLine,
          maxLines: 1,
          style: AppFonts.mono(
            fontSize: AppTextStyles.sm,
            color: AppColors.inkSecondary,
          ),
        ),
        if (days != null)
          Text(
            days,
            maxLines: 1,
            style: AppFonts.mono(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
            ),
          ),
      ],
    ),
  );
}

String _weekday(DateTime d) =>
    const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d.weekday - 1];

/// The Workouts tab's ledger: the name and its exercise count on the first
/// line, then when it was last logged — `last logged 31 oct · 2d` — under
/// it, the way every dated row in the lab reads (2026-11-02).
class _WorkoutList extends StatelessWidget {
  const _WorkoutList({required this.rows});

  final List<_WorkoutPreview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              WorkoutLabScreen.route(row.name),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.name,
                        maxLines: 2,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.body,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Sessions run, PRs won and goals hit — the same metric
                    // grid the Exercises tab uses, with the sessions glyph
                    // standing in for the word (2026-11-03).
                    SizedBox(
                      width: 172,
                      child: Row(
                        children: [
                          _MetricCell(
                            LucideIcons.circlePlay,
                            '${row.sessions}',
                          ),
                          const SizedBox(width: 8),
                          _MetricCell(
                            LucideIcons.trophy,
                            '${row.prs}',
                            lit: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          _MetricCell(
                            LucideIcons.crosshair,
                            '${row.goals}',
                            lit: AppColors.success,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _lastLoggedLabel(row.lastLogged),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The workout row's date line: the written date, with the count of days
/// while it is inside the 99-day window — `logged 31 oct · 2d`. Outside it
/// the date stands alone and carries its year when it is not this one —
/// `logged 14 oct 2025` (2026-11-03).
String _lastLoggedLabel(DateTime date) {
  final days = daysReading(date);
  if (days == null) {
    return 'logged ${goalDate(date, withYear: true)}';
  }
  return 'logged ${goalDate(date)} · $days';
}

/// One icon metric in a row's right-hand grid: a fixed width, the glyph and
/// a fixed value box, so the columns hold their places from row to row. A
/// zero stays quiet; a count that means something wears its lit ink.
class _MetricCell extends StatelessWidget {
  const _MetricCell(this.icon, this.value, {this.lit, this.width = 52});

  final IconData icon;
  final String value;
  final Color? lit;

  /// The cell's outer width. The grids use the default 52 to hold their
  /// columns; a lone pair can tighten to 48, giving a title more room.
  final double width;

  @override
  Widget build(BuildContext context) {
    final quiet = value == '0' || value == '—';
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(icon, size: 14, color: AppColors.inkSecondary),
          const SizedBox(width: 6),
          // A fixed value box, left-aligned: a one-digit and a two-digit
          // number start at the same x right beside the icon, and the box
          // holds the column's icon at one position either way.
          SizedBox(
            // Three digits fit (a 13pt mono digit is ~7.8pt); a fourth
            // would ellipsize rather than paint over the neighbouring
            // column.
            width: 28,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: AppFonts.mono(
                fontSize: AppTextStyles.caption,
                fontWeight: FontWeight.w600,
                color: quiet
                    ? AppColors.inkSecondary
                    : lit ?? AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Exercises preview: the name with when it was last trained on the
/// same line, then every icon metric in one 3 × 2 grid underneath — PRs,
/// goals met and goals open on the first row, sessions and sets on the
/// second. A zero stays quiet; counts that mean something wear their ink.
class _ExercisePreviewList extends StatelessWidget {
  const _ExercisePreviewList({required this.rows});

  final List<_ExercisePreview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              ExerciseLabScreen.route(
                personName: 'Jamie',
                initialIndex: rows.indexOf(row),
                entries: [
                  for (final entry in rows)
                    ExerciseLabEntry(
                      name: entry.name,
                      prs: entry.prs,
                      sessions: entry.sessions,
                      setsLastMonth: _setsLastMonth(entry),
                      goals: [
                        for (final goal in [
                          ..._completeGoals,
                          ..._openGoals,
                        ])
                          if (goal.name.startsWith('${entry.name} ')) goal,
                      ],
                    ),
                ],
              ),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 2,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.body,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // The grid's first row takes the top-right space.
                    SizedBox(
                      width: 172,
                      child: Row(
                        children: [
                          _MetricCell(
                            LucideIcons.trophy,
                            '${row.prs}',
                            lit: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          _MetricCell(
                            LucideIcons.crosshair,
                            '${row.goalsMet}',
                            lit: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          _MetricCell(
                            LucideIcons.crosshair,
                            '${row.goalsOpen}',
                            lit: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // The second line: the sentence on the left, the grid's
                // short row on the right — right-anchored so the grid's
                // outer edge stays whole.
                Row(
                  children: [
                    // Within 99 days the written date joins the age —
                    // `logged 31 oct · 2d` — held to the space left of the
                    // fixed grid so the row never grows (2026-11-02).
                    Expanded(
                      child: Text(
                        _lastUsedLabel(row.lastUsed),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.mono(
                          fontSize: AppTextStyles.xs,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      // The short row holds two cells, not three: 52 + 8 +
                      // 52. Right-aligned, they land in the same columns as
                      // the three above, and the sentence beside them keeps
                      // the width the unused third cell was reserving.
                      width: 112,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _MetricCell(LucideIcons.circlePlay, '${row.sessions}'),
                          const SizedBox(width: 8),
                          _MetricCell(LucideIcons.menu, '${row.sets}'),
                        ],
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One variation and the exercises it has been done on — each with the sets
/// that exercise spent under it.
class _VariationPreview {
  const _VariationPreview(this.name, this.exercises);

  final String name;

  /// Exercise name, sets done with this variation.
  final List<(String, int)> exercises;
}

const _variationPreviews = <_VariationPreview>[
  _VariationPreview('Pause', [
    ('Back Squat', 12),
    ('Bench Press', 8),
    ('Overhead Press', 4),
  ]),
  _VariationPreview('Wide', [
    ('Cable Row', 6),
    ('Seated Row', 5),
    ('Bench Press', 3),
  ]),
  _VariationPreview('Tempo', [
    ('Leg Press', 9),
    ('Leg Curl', 6),
    ('Hip Thrust', 4),
  ]),
  _VariationPreview('Deficit', [('Hip Thrust', 3)]),
  _VariationPreview('Slow', [
    ('Bench Press', 5),
    ('Cable Row', 4),
    ('Overhead Press', 2),
  ]),
  _VariationPreview('Banded', [('Pull-ups', 6), ('Dip', 3)]),
  _VariationPreview('Half rep', [('Leg Press', 2)]),
];

/// The Variations tab's ledger: the variation's name, then the exercises it
/// has served as pills — each pill naming the exercise and the sets done
/// under this variation.
class _VariationList extends StatelessWidget {
  const _VariationList({required this.rows});

  final List<_VariationPreview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              VariationLabScreen.route(row.name),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The name takes only the width it needs — up to 172, the
                  // room a 20-character name needs — so the pills start right
                  // beside it instead of after a fixed column's padding.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 172),
                  child: Text(
                    row.name,
                    maxLines: 2,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (exercise, sets) in row.exercises)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                exercise,
                                maxLines: 1,
                                style: AppFonts.ui(
                                  fontSize: AppTextStyles.xs,
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$sets',
                                style: AppFonts.mono(
                                  fontSize: AppTextStyles.xs,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final _completeGoals = <GoalLabRow>[
  GoalLabRow(
    'Deadlift 160 × 3',
    DateTime(2026, 10, 12),
    met: true,
    created: DateTime(2026, 8, 4),
  ),
  GoalLabRow(
    'Bench Press 90 × 3',
    DateTime(2026, 10, 24),
    met: true,
    created: DateTime(2026, 9, 12),
  ),
  GoalLabRow(
    'Leg Curl 45 × 10',
    DateTime(2026, 10, 12),
    met: true,
    created: DateTime(2026, 8, 20),
  ),
  GoalLabRow(
    'Back Squat 100 × 5',
    DateTime(2026, 9, 1),
    met: true,
    created: DateTime(2026, 6, 14),
  ),
  GoalLabRow(
    'Pull-ups 10 reps',
    DateTime(2026, 9, 20),
    met: true,
    created: DateTime(2026, 7, 2),
  ),
  GoalLabRow(
    'Overhead Press 45 × 5',
    DateTime(2026, 9, 14),
    met: true,
    created: DateTime(2026, 7, 21),
  ),
  GoalLabRow(
    'Leg Press 180 × 8',
    DateTime(2026, 9, 2),
    met: true,
    created: DateTime(2026, 6, 30),
  ),
  GoalLabRow(
    'Cable Row 65 × 8',
    DateTime(2026, 8, 25),
    met: true,
    created: DateTime(2026, 7, 8),
  ),
  GoalLabRow(
    'Leg Curl 40 × 10',
    DateTime(2026, 8, 18),
    met: true,
    created: DateTime(2026, 6, 19),
  ),
  GoalLabRow(
    'Hip Thrust 120 × 8',
    DateTime(2026, 8, 4),
    met: true,
    created: DateTime(2026, 5, 26),
  ),
  GoalLabRow(
    'Bench Press 80 × 5',
    DateTime(2026, 7, 21),
    met: true,
    created: DateTime(2026, 4, 15),
  ),
  // Last year: both dates carry the year (2026-11-02).
  GoalLabRow(
    'Back Squat 90 × 5',
    DateTime(2025, 7, 9),
    met: true,
    created: DateTime(2025, 5, 20),
  ),
];

final _openGoals = <GoalLabRow>[
  GoalLabRow(
    'Back Squat 120 × 5',
    DateTime(2026, 11, 15),
    met: false,
    created: DateTime(2026, 10, 20),
  ),
  GoalLabRow(
    'Pull-ups 12 reps',
    null,
    met: false,
    created: DateTime(2026, 10, 18),
  ),
  GoalLabRow(
    'Hip Thrust 140 × 8',
    DateTime(2026, 11, 30),
    met: false,
    created: DateTime(2026, 10, 24),
  ),
  GoalLabRow(
    'Overhead Press 50 × 6',
    null,
    met: false,
    created: DateTime(2026, 9, 30),
  ),
  GoalLabRow(
    'Deadlift 180 × 1',
    DateTime(2026, 12, 20),
    met: false,
    created: DateTime(2026, 10, 28),
  ),
  GoalLabRow(
    'Dip 25',
    DateTime(2026, 12, 5),
    met: false,
    created: DateTime(2026, 10, 10),
  ),
  GoalLabRow(
    'Back Squat 130 × 3',
    DateTime(2027, 2, 1),
    met: false,
    created: DateTime(2026, 10, 31),
  ),
  GoalLabRow(
    'Bench Press 100 × 1',
    DateTime(2027, 2, 14),
    met: false,
    created: DateTime(2026, 10, 15),
  ),
  GoalLabRow(
    'Pull-ups 15 reps',
    null,
    met: false,
    created: DateTime(2026, 9, 22),
  ),
  GoalLabRow(
    'Leg Press 220 × 8',
    DateTime(2027, 3, 2),
    met: false,
    created: DateTime(2026, 11, 1),
  ),
  GoalLabRow(
    'Cable Row 80 × 8',
    DateTime(2027, 4, 1),
    met: false,
    created: DateTime(2026, 10, 5),
  ),
  GoalLabRow(
    'Overhead Press 60 × 3',
    DateTime(2027, 5, 1),
    met: false,
    created: DateTime(2026, 10, 26),
  ),
  GoalLabRow(
    'Hip Thrust 160 × 8',
    null,
    met: false,
    created: DateTime(2026, 8, 30),
  ),
  GoalLabRow(
    'Leg Curl 50 × 10',
    DateTime(2027, 6, 1),
    met: false,
    created: DateTime(2026, 9, 18),
  ),
];

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// The exercise row's typed age (`2d ago`, `1w ago`) in days.
int _daysFromAge(String age) {
  final value = int.parse(age.substring(0, age.indexOf(RegExp('[dw]'))));
  return age.contains('w') ? value * 7 : value;
}

/// The exercise's sample usage in the last month: a third of its lifetime
/// sets, and nothing when it has not been trained in 30 days (2026-11-03).
int _setsLastMonth(_ExercisePreview entry) {
  if (_daysFromAge(entry.lastUsed) > 30) return 0;
  return (entry.sets / 3).round();
}

/// The exercise row's line: the written date, with the count of days while
/// it is inside the 99-day window — `logged 31 oct · 2d`. Outside it the date
/// stands alone and carries its year when it is not this one —
/// `logged 3 nov 2025` (2026-11-02).
String _lastUsedLabel(String age) {
  final days = _daysFromAge(age);
  final date = DateTime.now().subtract(Duration(days: days));
  if (daysReading(date) == null) {
    return 'logged ${goalDate(date, withYear: true)}';
  }
  return 'logged ${goalDate(date)} · ${days}d';
}

/// Pins the strip and the toolbar under the header once the page scrolls.
class _StickyToolbar extends SliverPersistentHeaderDelegate {
  const _StickyToolbar({required this.child, required this.tab});

  final Widget child;

  /// The active tab, so a change repaints the pinned strip.
  final int tab;

  /// The strip's 45 (22pt glyph, 11pt padding each side, its own rule) plus
  /// the toolbar's 51 (32pt field, 8pt above and below, and the field's own
  /// inner height rounding).
  static const double _height = 96;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      // The rule belongs to the pinned state: at rest the first ledger
      // flows straight out of the bar, with no divider of its own.
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: overlapsContent
            ? Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyToolbar oldDelegate) => oldDelegate.tab != tab;
}
