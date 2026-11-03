import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/lambda_search_field.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import '../../../shared/widgets/stats_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../session/model/pr_engine.dart';
import 'friend_lab_detail_screens.dart';
import 'lab_goal_columns.dart';
import 'lab_toolbar.dart';

/// One exercise on the Exercise screen: its PR total and its goals.
class ExerciseLabEntry {
  const ExerciseLabEntry({
    required this.name,
    required this.prs,
    required this.sessions,
    required this.setsLastMonth,
    required this.goals,
  });

  final String name;
  final int prs;

  /// The sample's all-time session count for the exercise.
  final int sessions;

  /// How many sets the exercise has logged in the last 30 days — the
  /// picker's ranking and its one line of meta.
  final int setsLastMonth;
  final List<GoalLabRow> goals;
}

/// The Exercise screen, planned fresh (2026-11-03).
///
/// The person's name in the header, an exercise selector, then the page's
/// own toolbar (search · sort · filter) and a PRs | Goals switch. Goals wear
/// the Goals preview's two-column ledger; PRs wear the app's shared
/// `PrEventRow`, newest first, each under its written date — so an
/// exercise's history reads the same whether it is yours or a friend's.
class ExerciseLabScreen extends StatefulWidget {
  const ExerciseLabScreen({
    super.key,
    required this.personName,
    required this.entries,
    required this.initialIndex,
  });

  final String personName;
  final List<ExerciseLabEntry> entries;
  final int initialIndex;

  static Route<void> route({
    required String personName,
    required List<ExerciseLabEntry> entries,
    required int initialIndex,
  }) => MaterialPageRoute(
    builder: (_) => ExerciseLabScreen(
      personName: personName,
      entries: entries,
      initialIndex: initialIndex,
    ),
  );

  @override
  State<ExerciseLabScreen> createState() => _ExerciseLabScreenState();
}

class _ExerciseLabScreenState extends State<ExerciseLabScreen> {
  late int _index;

  /// 0 = Summary stats (the landing tab), 1 = PRs, 2 = Goals.
  int _tab = 0;
  final _search = TextEditingController();
  LabSortBy _sort = LabSortBy.newest;
  bool _descending = true;
  LabRange _range = LabRange.all;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ExerciseLabEntry get _entry => widget.entries[_index];

  String get _query => _search.text.trim().toLowerCase();

  DateTime? _inRange(DateTime? date) {
    if (_range == LabRange.all || date == null) return date;
    final now = DateTime.now();
    final span = _range == LabRange.week
        ? const Duration(days: 7)
        : const Duration(days: 30);
    return now.difference(date) <= span ? date : null;
  }

  /// The selected exercise's PR feed, generated from its sample count: the
  /// newest event is the heaviest, each older one a step below it, dated
  /// back from today.
  List<PrEvent> get _prEvents {
    final (base, reps) = _prPrescription(_entry.name);
    return [
      for (var i = 0; i < _entry.prs; i++)
        PrEvent(
          exerciseId: _entry.name,
          exerciseName: _entry.name,
          weight: base + (_entry.prs - 1 - i) * 5,
          reps: reps,
          achievedDate: DateTime.now().subtract(Duration(days: 5 + i * 9)),
          sessionId: 'sample-${_entry.name}-$i',
          beforeWeight: i + 1 < _entry.prs
              ? base + (_entry.prs - 2 - i) * 5
              : null,
        ),
    ];
  }

  List<PrEvent> get _visiblePrs {
    final rows = [
      for (final event in _prEvents)
        if (_query.isEmpty ||
            '${formatPrNumber(event.weight)}kg × '
                    '${formatPrNumber(event.reps)}'
                .toLowerCase()
                .contains(_query))
          event,
    ];
    rows.sort((a, b) {
      if (_sort == LabSortBy.name) {
        final d = a.weight.compareTo(b.weight);
        return _descending ? -d : d;
      }
      final d = a.achievedDate.compareTo(b.achievedDate);
      return _descending ? -d : d;
    });
    return rows;
  }

  List<GoalLabRow> _goalsFor({required bool met}) {
    final rows = [
      for (final goal in _entry.goals)
        if (goal.met == met &&
            (_query.isEmpty || goal.name.toLowerCase().contains(_query)) &&
            (_range == LabRange.all || _inRange(goal.date) != null))
          goal,
    ];
    rows.sort((a, b) {
      if (_sort == LabSortBy.name) {
        final d = a.name.compareTo(b.name);
        return _descending ? -d : d;
      }
      final aDate = a.date ?? DateTime(0);
      final bDate = b.date ?? DateTime(0);
      final d = aDate.compareTo(bDate);
      return _descending ? -d : d;
    });
    return rows;
  }

  Future<void> _openPicker() async {
    final picked = await showLambdaModal<int>(
      context,
      keyboardAware: true,
      child: _ExercisePickerSheet(
        entries: widget.entries,
        selectedIndex: _index,
      ),
    );
    if (picked != null && mounted) setState(() => _index = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: "${widget.personName}'s Exercises",
            left: HeaderIconButton(
              icon: LucideIcons.arrowLeft,
              semanticsLabel: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                bottom:
                    AppSpacing.xl + ScrollShrinkNavBar.contentInset(context),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: _ExerciseBar(
                    name: _entry.name,
                    onTap: _openPicker,
                  ),
                ),
                // The rule under the selector, edge to edge.
                Container(height: 1, color: AppColors.border),
                // The PRs | Goals navigator: the preview screens' icon strip,
                // two tabs wide, above the toolbar so the search below
                // belongs to the list it is filtering.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: SlideIconTabBar(
                    tabs: const [
                      SlideIconTab(
                        icon: LucideIcons.chartNoAxesColumnIncreasing,
                        label: 'Summary stats',
                      ),
                      SlideIconTab(icon: LucideIcons.trophy, label: 'PRs'),
                      SlideIconTab(
                        icon: LucideIcons.crosshair,
                        label: 'Goals',
                      ),
                    ],
                    activeIndex: _tab,
                    onTap: (i) => setState(() => _tab = i),
                  ),
                ),
                // A summary is not a list: the search/sort/filter strip is
                // spent there, so it only rides the two data tabs.
                if (_tab != 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: LabToolbar(
                      search: _search,
                      sort: _sort,
                      descending: _descending,
                      range: _range,
                      onSort: (value, descending) => setState(() {
                        _sort = value;
                        _descending = descending;
                      }),
                      onRange: (value) => setState(() => _range = value),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: switch (_tab) {
                    0 => _summaryView(),
                    1 => _prsView(),
                    _ => _goalsView(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryView() {
    final entry = _entry;
    final goalsMet = entry.goals.where((g) => g.met).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'SUMMARY',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        StatsRow(
          tiles: [
            StatsTile(
              label: 'PRs',
              value: '${entry.prs}',
              accent: entry.prs > 0,
            ),
            StatsTile(label: 'Sets', value: '${entry.setsLastMonth}'),
            StatsTile(label: 'Sessions', value: '${entry.sessions}'),
            StatsTile(label: 'Goals met', value: '$goalsMet'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sets are the last 30 days; the rest are all time.',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _prsView() {
    final rows = _visiblePrs;
    if (rows.isEmpty) return const _Empty('No PRs for this exercise.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in rows) ...[
          Text(
            _prDate(event.achievedDate),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 4),
          PrEventRow(event),
        ],
      ],
    );
  }

  Widget _goalsView() {
    final open = _goalsFor(met: false);
    final complete = _goalsFor(met: true);
    if (open.isEmpty && complete.isEmpty) {
      return const _Empty('No goals for this exercise.');
    }
    return GoalLabColumns(
      open: open,
      complete: complete,
      onTap: (goal) =>
          Navigator.of(context).push(GoalLabScreen.route(goal.name)),
    );
  }
}

/// A written PR date, month-caps with the year when it is not this one.
String _prDate(DateTime date) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final year = date.year == DateTime.now().year ? '' : ' ${date.year}';
  return '${date.day} ${months[date.month - 1]}$year';
}

/// The selector: the middle bar of the session exercise picker, alone. Tap
/// it to choose from the person's exercises, most done first.
class _ExerciseBar extends StatelessWidget {
  const _ExerciseBar({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              LucideIcons.chevronDown,
              size: 18,
              color: AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar's searchable dropdown: every exercise, most sets in the last
/// month first, each row stating that count. Pops with the picked index.
class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({
    required this.entries,
    required this.selectedIndex,
  });

  final List<ExerciseLabEntry> entries;
  final int selectedIndex;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = [
      for (final (index, entry) in widget.entries.indexed)
        if (query.isEmpty || entry.name.toLowerCase().contains(query))
          (index, entry),
    ]..sort((a, b) {
        final d = b.$2.setsLastMonth.compareTo(a.$2.setsLastMonth);
        return d != 0 ? d : a.$2.name.compareTo(b.$2.name);
      });
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exercises',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            LambdaSearchField(
              controller: _search,
              hint: 'Search exercises…',
              showIcon: true,
              elevated: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (index, entry) in rows)
                    _PickerRow(
                      onTap: () => Navigator.of(context).pop(index),
                      name: entry.name,
                      setsLastMonth: entry.setsLastMonth,
                      selected: index == widget.selectedIndex,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.onTap,
    required this.name,
    required this.setsLastMonth,
    required this.selected,
  });

  final VoidCallback onTap;
  final String name;
  final int setsLastMonth;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$setsLastMonth ${setsLastMonth == 1 ? 'set' : 'sets'} '
                    'in the last month',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                LucideIcons.check,
                size: 18,
                color: AppColors.success,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.inkSecondary,
        ),
      ),
    );
  }
}

/// A plausible PR prescription per exercise: the base lift and its reps.
/// The generated feed walks heavier toward today, so the newest event is
/// the best one.
const _prPrescriptions = <String, (double, int)>{
  'Back Squat': (100, 5),
  'Leg Press': (180, 8),
  'Leg Curl': (45, 10),
  'Leg Extension': (50, 12),
  'Calf Raise': (80, 12),
  'Hip Thrust': (120, 8),
  'Bench Press': (80, 5),
  'Cable Row': (65, 8),
  'Deadlift': (160, 3),
  'Front Squat': (90, 5),
  'Overhead Press': (50, 6),
  'Lateral Raise': (12, 12),
  'Face Pull': (25, 15),
  'Pull-ups': (20, 8),
  'Dip': (25, 10),
  'Seated Row': (55, 10),
  'Lunge': (40, 10),
  'Dead Bug': (10, 12),
};

(double, int) _prPrescription(String exercise) =>
    _prPrescriptions[exercise] ?? (60, 8);
