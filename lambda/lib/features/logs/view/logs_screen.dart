import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../data/models/workout.dart';
import '../../../../data/models/workout_set.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../../../shared/widgets/slide_tab_view.dart';
import '../viewmodel/logs_viewmodel.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _viewModel     = LogsViewModel();
  final _tabController = SlideTabController();
  String?   _selectedExercise;
  String?   _selectedVariation;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _tabController.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime dt) =>
      DateFormat('EEE, d MMM yyyy', 'en_GB').format(dt);

  static String _formatDateShort(DateTime dt) =>
      DateFormat('d MMM', 'en_GB').format(dt);

  String get _dateLabel {
    if (_dateFrom == null && _dateTo == null) return 'Date';
    if (_dateFrom != null && _dateTo != null) {
      return '${_formatDateShort(_dateFrom!)} – ${_formatDateShort(_dateTo!)}';
    }
    if (_dateFrom != null) return 'After ${_formatDateShort(_dateFrom!)}';
    return 'Before ${_formatDateShort(_dateTo!)}';
  }

  void _clearFilters() => setState(() {
        _selectedExercise = null;
        _selectedVariation = null;
        _dateFrom = null;
        _dateTo = null;
      });

  void _onTabChanged(int i) {
    setState(() {
      _selectedExercise = null;
      _selectedVariation = null;
      _dateFrom = null;
      _dateTo = null;
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
              ? state.workouts.expand((w) => w.sets).toList()
              : state.pastSets.cast<WorkoutSet>();

          final exercises = allSets
              .map((s) => s.exerciseName ?? s.exerciseId)
              .toSet()
              .toList()
            ..sort();

          final variations = allSets
              .where((s) =>
                  _selectedExercise == null ||
                  (s.exerciseName ?? s.exerciseId) == _selectedExercise)
              .map((s) => s.variationName)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();

          // ── client-side filtering ─────────────────────────────────────────────
          bool matchesExercise(WorkoutSet s) =>
              _selectedExercise == null ||
              (s.exerciseName ?? s.exerciseId) == _selectedExercise;

          bool matchesVariation(WorkoutSet s) =>
              _selectedVariation == null ||
              s.variationName == _selectedVariation;

          bool matchesDate(DateTime dt) {
            final day = DateTime(dt.year, dt.month, dt.day);
            if (_dateFrom != null && day.isBefore(_dateFrom!)) return false;
            if (_dateTo != null && day.isAfter(_dateTo!)) return false;
            return true;
          }

          final filteredWorkouts = state.workouts.where((w) {
            if (!matchesDate(w.workout.createdDate)) return false;
            return w.sets.any((s) => matchesExercise(s) && matchesVariation(s));
          }).toList();

          final filteredSets = state.pastSets
              .where((s) =>
                  matchesExercise(s) &&
                  matchesVariation(s) &&
                  matchesDate(s.workoutCreatedDate))
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
                dateActive: _dateFrom != null || _dateTo != null,
                onExerciseChanged: (v) => setState(() {
                  _selectedExercise = v;
                  _selectedVariation = null;
                }),
                onVariationChanged: (v) =>
                    setState(() => _selectedVariation = v),
                onDateTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _DateRangeSheet(
                    initialFrom: _dateFrom,
                    initialTo: _dateTo,
                    onApply: (from, to) => setState(() {
                      _dateFrom = from;
                      _dateTo = to;
                    }),
                  ),
                ),
                onClear: (_selectedExercise != null ||
                        _selectedVariation != null ||
                        _dateFrom != null ||
                        _dateTo != null)
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
            child: _SearchableDropdownButton(
              placeholder: 'Exercise',
              value: selectedExercise,
              options: exercises,
              onChanged: onExerciseChanged,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SearchableDropdownButton(
              placeholder: 'Variation',
              value: selectedVariation,
              options: variations,
              onChanged: onVariationChanged,
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextStyles.sm,
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

// ── Date range sheet ────────────────────────────────────────────────────────────

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({
    required this.initialFrom,
    required this.initialTo,
    required this.onApply,
  });

  final DateTime? initialFrom;
  final DateTime? initialTo;
  final void Function(DateTime? from, DateTime? to) onApply;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  DateTime? _from;
  DateTime? _to;

  static final _fmt = DateFormat('d MMM yyyy', 'en_GB');

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to   = widget.initialTo;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? _to ?? now)
        : (_to ?? _from ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: AppColors.primary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
        if (_to != null && _to!.isBefore(_from!)) _to = null;
      } else {
        _to = DateTime(picked.year, picked.month, picked.day);
        if (_from != null && _from!.isAfter(_to!)) _from = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // handle
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // title row
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Text('Date Range',
                    style: TextStyle(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const Spacer(),
                if (_from != null || _to != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _from = null;
                      _to   = null;
                    }),
                    child: Text('Clear',
                        style: TextStyle(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.accent)),
                  ),
              ],
            ),
          ),
          // from / to rows
          _DateRow(
            label: 'From',
            date: _from,
            hint: 'Any start date',
            onTap: () => _pickDate(isFrom: true),
            onClear: _from == null ? null : () => setState(() => _from = null),
            fmt: _fmt,
          ),
          Container(height: 0.5, color: AppColors.border),
          _DateRow(
            label: 'To',
            date: _to,
            hint: 'Any end date',
            onTap: () => _pickDate(isFrom: false),
            onClear: _to == null ? null : () => setState(() => _to = null),
            fmt: _fmt,
          ),
          // apply button
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                widget.onApply(_from, _to);
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('Apply',
                    style: TextStyle(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.hint,
    required this.onTap,
    required this.onClear,
    required this.fmt,
  });

  final String label;
  final DateTime? date;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextStyles.sm, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(
                date != null ? fmt.format(date!) : hint,
                style: TextStyle(
                  fontSize: AppTextStyles.sm,
                  color: date != null ? AppColors.primary : AppColors.muted,
                  fontWeight: date != null ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: AppColors.muted),
              )
            else
              Icon(Icons.calendar_today_outlined,
                  size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

// ── Searchable dropdown button ──────────────────────────────────────────────────

class _SearchableDropdownButton extends StatelessWidget {
  const _SearchableDropdownButton({
    required this.placeholder,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String placeholder;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(
        title: placeholder,
        current: value,
        options: options,
        onSelected: (v) {
          Navigator.of(context).pop();
          onChanged(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = value != null;
    return GestureDetector(
      onTap: options.isEmpty ? null : () => _open(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? placeholder,
                style: TextStyle(
                  fontSize: AppTextStyles.sm,
                  color: isActive ? AppColors.accent : AppColors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: isActive ? AppColors.accent : AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search sheet ────────────────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.title,
    required this.current,
    required this.options,
    required this.onSelected,
  });

  final String title;
  final String? current;
  final List<String> options;
  final ValueChanged<String?> onSelected;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.options;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.options
            : widget.options
                .where((o) => o.toLowerCase().contains(q))
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.6;
    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // handle
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // title
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                      fontSize: AppTextStyles.md,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
                const Spacer(),
                if (widget.current != null)
                  GestureDetector(
                    onTap: () => widget.onSelected(null),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                          fontSize: AppTextStyles.sm, color: AppColors.accent),
                    ),
                  ),
              ],
            ),
          ),
          // search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.search, size: 16, color: AppColors.muted),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      style: TextStyle(
                          fontSize: AppTextStyles.sm, color: AppColors.primary),
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        hintStyle: TextStyle(
                            fontSize: AppTextStyles.sm, color: AppColors.muted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // list
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final opt = _filtered[i];
                final isSelected = opt == widget.current;
                return InkWell(
                  onTap: () => widget.onSelected(opt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontSize: AppTextStyles.sm,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.primary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check, size: 16, color: AppColors.accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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

  final List<WorkoutWithSets> workouts;
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
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: PressSquash(
              onTap: () => onTap(w.workout.workoutId),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      formatDate(w.workout.createdDate),
                      style: TextStyle(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent),
                    ),
                    if (w.workout.preNotes?.isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '"${w.workout.preNotes}"',
                        style: TextStyle(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (w.sets.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ..._exerciseSummaries(w.sets),
                    ],
                    if (w.workout.postNotes?.isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '"${w.workout.postNotes}"',
                        style: TextStyle(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _exerciseSummaries(List<WorkoutSet> sets) {
    final order  = <String>[];
    final counts = <String, int>{};
    final names  = <String, String>{};
    for (final s in sets) {
      if (!names.containsKey(s.exerciseId)) {
        order.add(s.exerciseId);
        names[s.exerciseId] = s.exerciseName ?? s.exerciseId;
      }
      counts[s.exerciseId] = (counts[s.exerciseId] ?? 0) + 1;
    }
    return order.map((exId) {
      final count = counts[exId]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                names[exId]!,
                style: TextStyle(
                    fontSize: AppTextStyles.sm, color: AppColors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count ${count == 1 ? 'set' : 'sets'}',
              style: TextStyle(
                  fontSize: AppTextStyles.xs, color: AppColors.muted),
            ),
          ],
        ),
      );
    }).toList();
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
              !_sameDay(prev.workoutCreatedDate, row.workoutCreatedDate);

          final isReps    = row.duration.isEmpty;
          final vals      = isReps ? row.reps : row.duration;
          final valStr    = vals.isEmpty ? '—' : vals.join(', ');
          final unit      = isReps ? 'reps' : 's';
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
                    formatDate(row.workoutCreatedDate),
                    style: TextStyle(
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
                              style: TextStyle(
                                  fontSize: AppTextStyles.sm,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$weightStr$valStr $unit',
                              style: TextStyle(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                            ),
                            if (metaLabel.isNotEmpty)
                              Text(
                                metaLabel,
                                style: TextStyle(
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
                    style: TextStyle(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
