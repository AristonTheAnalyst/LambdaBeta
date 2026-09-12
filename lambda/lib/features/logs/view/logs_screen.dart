import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../data/models/exercise_usage.dart';
import '../../../../data/models/session.dart';
import '../../../../data/models/session_exercise_set.dart';
import '../../../../shared/widgets/container_styles.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../shared/widgets/date_range_selector.dart';
import '../../../../shared/widgets/session_log_card.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../../../shared/widgets/slide_tab_view.dart';
import '../../../../shared/router/app_router.dart';
import '../viewmodel/logs_viewmodel.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with RouteAware {
  final _viewModel     = LogsViewModel();
  final _tabController = SlideTabController();
  String?   _selectedExercise;
  String?   _selectedVariation;

  /// The date filter — the same shared [DateRangeSelection] the exercises >
  /// insights page uses, defaulting to ALL (no filtering).
  DateRangeSelection _dateSelection =
      const DateRangeSelection.preset(DateRangePreset.all);

  static const _defaultDateSelection =
      DateRangeSelection.preset(DateRangePreset.all);

  /// Name-keyed comparator: most recently used first (nulls last, then name).
  static int _byNameRecency(String a, String b, Map<String, DateTime> lastUsed) {
    final da = lastUsed[a];
    final db = lastUsed[b];
    if (da != null && db != null) return db.compareTo(da);
    if (da != null) return -1;
    if (db != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _viewModel.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer here — ModalRoute.of(context) depends on
    // inherited widgets that aren't available during initState.
    AppRouter.routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    AppRouter.routeObserver.unsubscribe(this);
    _viewModel.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Refresh when returning from workout detail so edits (added sets,
    // changed notes, deleted sets) are reflected immediately.
    _viewModel.load();
  }

  static String _formatDate(DateTime dt) =>
      DateFormat('EEE, d MMM yyyy', 'en_GB').format(dt);

  String get _dateLabel => _dateSelection.label(DateTime.now());

  bool get _dateActive => _dateSelection != _defaultDateSelection;

  void _clearFilters() => setState(() {
        _selectedExercise = null;
        _selectedVariation = null;
        _dateSelection = _defaultDateSelection;
      });

  void _onTabChanged(int i) {
    setState(() {
      _selectedExercise = null;
      _selectedVariation = null;
      _dateSelection = _defaultDateSelection;
    });
    _viewModel.setTab(i);
    _tabController.jumpTo(i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<LogsState>(
        valueListenable: _viewModel.state,
        builder: (context, state, _) {
          final isWorkouts = state.activeTab == 0;

          // ── derive filter options ─────────────────────────────────────────────
          final allSets = isWorkouts
              ? state.sessions.expand((w) => w.sets).toList()
              : state.pastSets.cast<SessionExerciseSet>();

          // Most recently used first (names derived from the dated timeline).
          final byId = lastUsedByEntity(state.pastSets);
          final lastUsed = <String, DateTime>{};
          for (final s in state.pastSets) {
            final exId = s.exerciseId;
            if (exId == null) continue;
            final exD = byId[exId];
            final exName = s.exerciseName ?? exId;
            if (exD != null && (!lastUsed.containsKey(exName) || exD.isAfter(lastUsed[exName]!))) {
              lastUsed[exName] = exD;
            }
            final vName = s.variationName;
            if (vName != null && s.variationId != null) {
              final vD = byId[s.variationId!];
              if (vD != null && (!lastUsed.containsKey(vName) || vD.isAfter(lastUsed[vName]!))) {
                lastUsed[vName] = vD;
              }
            }
          }

          final exercises = allSets
              .where((s) => s.exerciseId != null)
              .map((s) => s.exerciseName ?? s.exerciseId!)
              .toSet()
              .toList()
            ..sort((a, b) => _byNameRecency(a, b, lastUsed));

          final variations = allSets
              .where((s) =>
                  _selectedExercise == null ||
                  (s.exerciseName ?? s.exerciseId) == _selectedExercise)
              .map((s) => s.variationName)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort((a, b) => _byNameRecency(a, b, lastUsed));

          // ── client-side filtering ─────────────────────────────────────────────
          bool matchesExercise(SessionExerciseSet s) =>
              _selectedExercise == null ||
              (s.exerciseName ?? s.exerciseId) == _selectedExercise;

          bool matchesVariation(SessionExerciseSet s) =>
              _selectedVariation == null ||
              s.variationName == _selectedVariation;

          bool matchesDate(DateTime dt) {
            final w = _dateSelection.window(DateTime.now());
            return !dt.isBefore(w.from) && dt.isBefore(w.to);
          }

          final filteredWorkouts = state.sessions.where((w) {
            if (!matchesDate(w.session.createdDatetime)) return false;
            return w.sets.any((s) => matchesExercise(s) && matchesVariation(s));
          }).toList();

          final filteredSets = state.pastSets
              .where((s) =>
                  matchesExercise(s) &&
                  matchesVariation(s) &&
                  matchesDate(s.sessionCreatedDate))
              .toList();

          return Column(
            children: [
              PageHeader(title: 'Training Logs'),
              SlideTabBar(
                tabs: ['Workouts', 'Sets'],
                activeIndex: state.activeTab,
                onTap: _onTabChanged,
              ),
              _FilterBar(
                exercises: exercises,
                variations: variations,
                selectedExercise: _selectedExercise,
                selectedVariation: _selectedVariation,
                dateLabel: _dateLabel,
                dateActive: _dateActive,
                onExerciseChanged: (v) => setState(() {
                  _selectedExercise = v;
                  _selectedVariation = null;
                }),
                onVariationChanged: (v) =>
                    setState(() => _selectedVariation = v),
                onDateTap: () async {
                  // The shared date-range selector — the same custom filter
                  // the exercises > insights page uses.
                  final sel = await showDateRangeSelector(
                    context,
                    initial: _dateSelection,
                  );
                  if (sel != null && mounted) {
                    setState(() => _dateSelection = sel);
                  }
                },
                onClear: (_selectedExercise != null ||
                        _selectedVariation != null ||
                        _dateActive)
                    ? _clearFilters
                    : null,
              ),
              if (state.isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else
                SlideTabView(
                  controller: _tabController,
                  onPageChanged: (i) {
                    setState(() {
                      _selectedExercise = null;
                      _selectedVariation = null;
                    });
                    _viewModel.setTab(i);
                  },
                  tabs: [
                    _WorkoutsPanel(
                      workouts: filteredWorkouts,
                      isRefreshing: state.isRefreshing,
                      onRefresh: _viewModel.refresh,
                      formatDate: _formatDate,
                      onTap: (id) => context.push('/logs/$id'),
                    ),
                    _SetsPanel(
                      pastSets: filteredSets,
                      isRefreshing: state.isRefreshing,
                      onRefresh: _viewModel.refresh,
                      formatDate: _formatDate,
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.exercises,
    required this.variations,
    required this.selectedExercise,
    required this.selectedVariation,
    required this.dateLabel,
    required this.dateActive,
    required this.onExerciseChanged,
    required this.onVariationChanged,
    required this.onDateTap,
    required this.onClear,
  });

  final List<String> exercises;
  final List<String> variations;
  final String? selectedExercise;
  final String? selectedVariation;
  final String dateLabel;
  final bool dateActive;
  final ValueChanged<String?> onExerciseChanged;
  final ValueChanged<String?> onVariationChanged;
  final VoidCallback onDateTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterChip(
              label: selectedExercise ?? 'Exercise',
              isActive: selectedExercise != null,
              onTap: exercises.isEmpty
                  ? null
                  : () => showDropdownPickerSheet<String>(
                        context,
                        options: exercises
                            .map((e) => DropdownOption(label: e, value: e))
                            .toList(),
                        value: selectedExercise,
                        searchable: true,
                        onSelect: onExerciseChanged,
                      ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FilterChip(
              label: selectedVariation ?? 'Variation',
              isActive: selectedVariation != null,
              onTap: variations.isEmpty
                  ? null
                  : () => showDropdownPickerSheet<String>(
                        context,
                        options: variations
                            .map((v) => DropdownOption(label: v, value: v))
                            .toList(),
                        value: selectedVariation,
                        searchable: true,
                        onSelect: onVariationChanged,
                      ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FilterChip(
              label: dateLabel,
              isActive: dateActive,
              onTap: onDateTap,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Generic filter chip (non-searchable, just opens a sheet) ───────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // The glass recipe — active in accent, inactive in primary.
        decoration: glassBox(isActive ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.accent : AppColors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14,
                color: isActive ? AppColors.accent : AppColors.muted),
          ],
        ),
      ),
    );
  }
}

// ── Workouts panel ──────────────────────────────────────────────────────────────

class _WorkoutsPanel extends StatelessWidget {
  const _WorkoutsPanel({
    required this.workouts,
    required this.isRefreshing,
    required this.onRefresh,
    required this.formatDate,
    required this.onTap,
  });

  final List<SessionWithSets> workouts;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final String Function(DateTime) formatDate;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) {
      return _EmptyState(
        onRefresh: onRefresh,
        message: 'No workouts yet',
        hint: 'Head to the Session tab to log your first workout.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: workouts.length,
        itemBuilder: (_, i) {
          final w = workouts[i];
          // THE session card — the same one the all-sessions sheet shows.
          return SessionLogCard(
            workout: w,
            onTap: () => onTap(w.session.sessionId),
          );
        },
      ),
    );
  }
}

// ── Sets panel ──────────────────────────────────────────────────────────────────

class _SetsPanel extends StatelessWidget {
  const _SetsPanel({
    required this.pastSets,
    required this.isRefreshing,
    required this.onRefresh,
    required this.formatDate,
  });

  final List<PastSetRow> pastSets;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final String Function(DateTime) formatDate;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (pastSets.isEmpty) {
      return _EmptyState(
        onRefresh: onRefresh,
        message: 'No sets yet',
        hint: 'Log your first workout from the Session tab.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: pastSets.length,
        itemBuilder: (_, i) {
          final row = pastSets[i];
          final prev = i > 0 ? pastSets[i - 1] : null;
          final isNewDate = prev == null ||
              !_sameDay(prev.sessionCreatedDate, row.sessionCreatedDate);

          final vals = row.reps;
          final valStr    = vals.isEmpty ? '—' : vals.join(', ');
          const unit = 'reps';
          final weightStr = row.weight != null ? '${row.weight} kg × ' : '';
          final exerciseLabel = row.exerciseName ?? '—';
          final metaLabel = [
            if (row.variationName != null) row.variationName!,
            if (row.notes?.isNotEmpty == true) row.notes!,
          ].join(' · ');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNewDate) ...[
                if (i > 0) const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg),
                  child: Text(
                    formatDate(row.sessionCreatedDate),
                    style: AppFonts.mono(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 0.8),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exerciseLabel,
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.sm,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$weightStr$valStr $unit',
                              style: AppFonts.mono(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                            ),
                            if (metaLabel.isNotEmpty)
                              Text(
                                metaLabel,
                                style: AppFonts.ui(
                                    fontSize: AppTextStyles.xs,
                                    color: AppColors.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onRefresh,
    required this.message,
    required this.hint,
  });

  final Future<void> Function() onRefresh;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(message,
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(hint,
                      textAlign: TextAlign.center,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm, color: AppColors.muted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
