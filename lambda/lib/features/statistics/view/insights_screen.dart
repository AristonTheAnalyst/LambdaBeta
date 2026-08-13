import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/session_set.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/multi_select_sheet.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import '../../../shared/widgets/stats_row.dart';
import '../../session/model/pr_engine.dart';
import '../model/insights_engine.dart';

/// Analytics over past workouts: PR frequency, set volume, and weight/rep
/// distributions — filterable by exercise, variation, and time range.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.lockedExerciseId,
    this.lockedExerciseName,
    this.headerRight,
  });

  /// When set, the exercise filter is locked to this exercise and its chip
  /// is not tappable — used by the per-exercise detail page.
  final String? lockedExerciseId;
  final String? lockedExerciseName;

  /// Optional actions in the header (used by the locked exercise page for
  /// rename / archive).
  final Widget? headerRight;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  static const _noVariation = '__none__'; // sentinel: sets logged without a variation

  final _sessionRepo = SessionRepository();
  List<PastSetRow>? _sets;
  List<PrRecord>? _prs;
  String? _error;
  int _tab = 0;
  InsightRange _range = InsightRange.month;

  // Empty set = "all" for the multi-selects.
  Set<String> _exercises = {};
  Set<String> _selectedVariations = {}; // variationId, or _noVariation

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    if (widget.lockedExerciseId != null) {
      _exercises = {widget.lockedExerciseId!};
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final sets = await _sessionRepo.loadPastSetsTimeline(_userId);
      final prs = fullPrTimeline(sets);
      if (mounted) {
        setState(() {
          _sets = sets;
          _prs = prs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sets = null;
          _prs = null;
          _error = e.toString();
        });
      }
    }
  }

  // ── Derived filter options ───────────────────────────────────────────────────

  List<({String id, String name})> get _exerciseOptions {
    final seen = <String, String?>{};
    final lastUsed = lastUsedByEntity(_sets ?? const <PastSetRow>[]);
    for (final s in _sets ?? const <PastSetRow>[]) {
      seen.putIfAbsent(s.exerciseId, () => s.exerciseName);
    }
    final list = seen.entries
        .map((e) => (id: e.key, name: e.value ?? e.key))
        .toList()
      ..sort((a, b) {
        final da = lastUsed[a.id];
        final db = lastUsed[b.id];
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  List<({String? id, String name})> get _variationOptions {
    final seen = <String?, String?>{};
    final lastUsed = lastUsedByEntity(_sets ?? const <PastSetRow>[]);
    for (final s in _sets ?? const <PastSetRow>[]) {
      if (_exercises.isNotEmpty && !_exercises.contains(s.exerciseId)) continue;
      seen.putIfAbsent(s.variationId, () => s.variationName);
    }
    final list = seen.entries
        .map((e) => (id: e.key, name: e.value ?? 'No variation'))
        .toList()
      ..sort((a, b) {
        final da = a.id != null ? lastUsed[a.id] : null;
        final db = b.id != null ? lastUsed[b.id] : null;
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Set<String?> get _activeVariations => {
        if (_selectedVariations.contains(_noVariation)) null,
        ..._selectedVariations.where((v) => v != _noVariation),
      };

  List<PastSetRow> get _filteredSets {
    final sets = _sets ?? const <PastSetRow>[];
    return filterSets(sets, _range, _exercises, _activeVariations, DateTime.now());
  }

  List<PrRecord> get _filteredPrs {
    final prs = _prs ?? const <PrRecord>[];
    return filterPrs(prs, _range, _exercises, _activeVariations, DateTime.now());
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: widget.lockedExerciseName != null
                ? "Insights - ${toProperCase(widget.lockedExerciseName!)}"
                : 'Insights',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.primary),
            ),
            right: widget.headerRight,
          ),
          _filterRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
            child: SegmentedControl<InsightRange>(
              subtle: true,
              options: [
                for (final r in InsightRange.values) SegmentOption(label: r.label, value: r),
              ],
              value: _range,
              onChange: (r) => setState(() => _range = r),
            ),
          ),
          SlideTabBar(
            tabs: const ['PRs', 'Sets', 'Weight', 'Reps'],
            activeIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: _sets == null
                ? (_error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Could not load insights.',
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.md,
                                        color: AppColors.danger)),
                                const SizedBox(height: AppSpacing.sm),
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.xs,
                                        color: AppColors.muted)),
                                const SizedBox(height: AppSpacing.lg),
                                GlassButton(
                                  label: 'Retry',
                                  onPressed: _load,
                                ),
                              ],
                            ),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator()))
                : switch (_tab) {
                    0 => _PrsTab(screen: this),
                    1 => _SetsTab(screen: this),
                    2 => _WeightTab(screen: this),
                    _ => _RepsTab(screen: this),
                  },
          ),
        ],
      ),
    );
  }

  // ── Filter row ───────────────────────────────────────────────────────────────

  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: _filterChip(
            icon: Icons.fitness_center,
            label: widget.lockedExerciseName != null
                ? toProperCase(widget.lockedExerciseName!)
                : _exerciseLabel,
            onTap: widget.lockedExerciseId != null ? null : _pickExercises,
          )),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _filterChip(
            icon: Icons.tune,
            label: _variationLabel,
            onTap: _pickVariations,
          )),
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (onTap != null)
              Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  String get _exerciseLabel =>
      _exercises.isEmpty ? 'All exercises' : '${_exercises.length} exercise${_exercises.length == 1 ? '' : 's'}';

  String get _variationLabel =>
      _selectedVariations.isEmpty ? 'All variations' : '${_selectedVariations.length} variation${_selectedVariations.length == 1 ? '' : 's'}';

  Future<void> _pickExercises() async {
    if (widget.lockedExerciseId != null) return; // locked — not pickable
    final result = await showMultiSelectSheet<String>(
      context,
      options: [
        for (final e in _exerciseOptions) MultiSelectOption(label: toProperCase(e.name), value: e.id),
      ],
      selected: _exercises.toList(),
      title: 'Exercises',
      confirmLabel: 'Done',
      searchable: true,
    );
    if (result != null) setState(() => _exercises = result.toSet());
  }

  Future<void> _pickVariations() async {
    final options = <MultiSelectOption<String>>[
      if (_variationOptions.any((v) => v.id == null))
        const MultiSelectOption(label: 'No variation', value: _noVariation),
      for (final v in _variationOptions.where((v) => v.id != null))
        MultiSelectOption(label: toProperCase(v.name), value: v.id!),
    ];
    if (options.isEmpty) return;
    final result = await showMultiSelectSheet<String>(
      context,
      options: options,
      selected: _selectedVariations.toList(),
      title: 'Variations',
      confirmLabel: 'Done',
      searchable: true,
    );
    if (result != null) setState(() => _selectedVariations = result.toSet());
  }

  // ── Chart scaffolding shared by all tabs ─────────────────────────────────────

  Widget _tabBody({required List<StatsTile> tiles, required Widget chart, required bool hasData}) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        StatsRow(tiles: tiles),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: hasData
              ? SizedBox(height: 220, width: double.infinity, child: chart)
              : const _EmptyChart(),
        ),
      ],
    );
  }

  FlTitlesData _titles({
    required Widget Function(double, TitleMeta) bottomTitle,
    double? bottomInterval,
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          getTitlesWidget: _leftTitle,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: bottomInterval,
          getTitlesWidget: bottomTitle,
        ),
      ),
    );
  }

  Widget _leftTitle(double value, TitleMeta meta) {
    if (value != value.roundToDouble()) return const SizedBox.shrink();
    return SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text('${value.toInt()}',
          style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
    );
  }

  FlGridData get _grid => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: AppColors.border.withValues(alpha: 0.4), strokeWidth: 0.5),
      );

  FlBorderData get _noBorder => FlBorderData(show: false);

  /// Bottom-axis widget for time-series charts: bucket date, thinned via [interval].
  Widget _timeTitle(double value, TitleMeta meta, List<DateTime> buckets, int interval) {
    final i = value.round();
    if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
    if (i % interval != 0 && i != buckets.length - 1) return const SizedBox.shrink();
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Text(_axisLabel(buckets[i], _range),
          style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
    );
  }

  String _axisLabel(DateTime d, InsightRange range) {
    switch (range) {
      case InsightRange.week:
      case InsightRange.fortnight:
      case InsightRange.month:
      case InsightRange.threeMonths:
        return DateFormat('d/M').format(d);
      case InsightRange.sixMonths:
      case InsightRange.year:
        return DateFormat('MMM').format(d);
    }
  }

  static int _intervalFor(int n) => n <= 6 ? 1 : ((n - 1) / 5).ceil();

  // ── Tab: PRs ─────────────────────────────────────────────────────────────────

  Widget _prsTab() {
    final prs = _filteredPrs;
    final buckets = bucketsFor(_range, DateTime.now());
    final counts = countsPerBucket(buckets,
        [for (final p in prs) p.achievedDate], _range);
    final m = prMetrics(prs, _range);
    final n = buckets.length;
    final maxY = counts.fold<int>(0, (acc, c) => c > acc ? c : acc);

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: n > 1 ? (n - 1).toDouble() : 1,
        minY: 0,
        maxY: maxY == 0 ? 4 : maxY.toDouble() * 1.3,
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), counts[i].toDouble())],
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppColors.accent,
            barWidth: 2,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: 0.12)),
          ),
        ],
        gridData: _grid,
        borderData: _noBorder,
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: _titles(
          bottomInterval: _intervalFor(n).toDouble(),
          bottomTitle: (v, meta) => _timeTitle(v, meta, buckets, _intervalFor(n)),
        ),
      ),
    );

    return _tabBody(
      tiles: [
        StatsTile(label: 'TOTAL PRs', value: '${m.total}'),
        StatsTile(label: 'PRs/WK', value: _fmt(m.perWeek)),
        StatsTile(label: 'BEST 1RM', value: m.best1rm != null ? '${_fmt(m.best1rm!)}kg' : '—'),
      ],
      chart: chart,
      hasData: prs.isNotEmpty,
    );
  }

  // ── Tab: Sets ────────────────────────────────────────────────────────────────

  Widget _setsTab() {
    final sets = _filteredSets;
    final buckets = bucketsFor(_range, DateTime.now());
    final counts = countsPerBucket(buckets,
        [for (final s in sets) s.sessionCreatedDate], _range);
    final m = setMetrics(sets, _range);
    final n = buckets.length;

    final chart = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: counts[i].toDouble(),
                color: AppColors.accent,
                width: n > 14 ? 5 : 10,
                borderRadius: BorderRadius.circular(2),
              ),
            ]),
        ],
        maxY: _maxBarY(counts),
        gridData: _grid,
        borderData: _noBorder,
        barTouchData: const BarTouchData(enabled: false),
        titlesData: _titles(
          bottomInterval: _intervalFor(n).toDouble(),
          bottomTitle: (v, meta) => _timeTitle(v, meta, buckets, _intervalFor(n)),
        ),
      ),
    );

    return _tabBody(
      tiles: [
        StatsTile(label: 'TOTAL SETS', value: '${m.total}'),
        StatsTile(label: 'SETS/WK', value: _fmt(m.perWeek)),
        StatsTile(label: 'EXERCISES', value: '${m.exercises}'),
      ],
      chart: chart,
      hasData: sets.isNotEmpty,
    );
  }

  // ── Tab: Weight ──────────────────────────────────────────────────────────────

  Widget _weightTab() {
    final sets = _filteredSets;
    final hist = weightHistogram(sets);
    final m = weightMetrics(sets, hist);
    final keys = hist.keys.toList()..sort();
    final entries = [
      if (keys.isNotEmpty)
        for (var b = keys.first; b <= keys.last; b += kWeightBucket) (bucket: b, count: hist[b] ?? 0),
    ];

    final chart = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: entries[i].count.toDouble(),
                color: AppColors.accent,
                width: entries.length > 14 ? 5 : 10,
                borderRadius: BorderRadius.circular(2),
              ),
            ]),
        ],
        maxY: _maxBarY([for (final e in entries) e.count]),
        gridData: _grid,
        borderData: _noBorder,
        barTouchData: const BarTouchData(enabled: false),
        titlesData: _titles(
          bottomInterval: _intervalFor(entries.length).toDouble(),
          bottomTitle: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= entries.length) return const SizedBox.shrink();
            if (i % _intervalFor(entries.length) != 0 && i != entries.length - 1) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              space: 6,
              child: Text('${entries[i].bucket}',
                  style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
            );
          },
        ),
      ),
    );

    return _tabBody(
      tiles: [
        StatsTile(label: 'MOST HIT', value: '${m.mostHit}kg', accent: true),
        StatsTile(label: 'AVG WEIGHT', value: '${_fmt(m.avgWeight)}kg'),
        StatsTile(label: 'MAX', value: m.maxWeight != null ? '${_fmt(m.maxWeight!)}kg' : '—'),
      ],
      chart: chart,
      hasData: entries.isNotEmpty,
    );
  }

  // ── Tab: Reps ────────────────────────────────────────────────────────────────

  Widget _repsTab() {
    final sets = _filteredSets;
    final hist = repsHistogram(sets);
    final m = repMetrics(sets, hist);
    final counts = [for (final rr in kRepRanges) hist[rr.label] ?? 0];

    final chart = BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var i = 0; i < counts.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: counts[i].toDouble(),
                color: AppColors.accent,
                width: 14,
                borderRadius: BorderRadius.circular(2),
              ),
            ]),
        ],
        maxY: _maxBarY(counts),
        gridData: _grid,
        borderData: _noBorder,
        barTouchData: const BarTouchData(enabled: false),
        titlesData: _titles(
          bottomTitle: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= kRepRanges.length) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              space: 6,
              child: Text(kRepRanges[i].label,
                  style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
            );
          },
        ),
      ),
    );

    return _tabBody(
      tiles: [
        StatsTile(label: 'TOP RANGE', value: m.topRange, accent: true),
        StatsTile(label: 'AVG REPS', value: _fmt(m.avgReps)),
        StatsTile(label: 'TOTAL REPS', value: '${m.totalReps}'),
      ],
      chart: chart,
      hasData: sets.isNotEmpty,
    );
  }

  static double _maxBarY(List<int> counts) {
    final max = counts.fold<int>(0, (acc, c) => c > acc ? c : acc);
    return max == 0 ? 4 : max.toDouble() * 1.2;
  }

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No data in this range',
          style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted)),
    );
  }
}

// ── Tab view wrappers ──────────────────────────────────────────────────────────

class _PrsTab extends StatelessWidget {
  const _PrsTab({required this.screen});
  final _InsightsScreenState screen;
  @override
  Widget build(BuildContext context) => screen._prsTab();
}

class _SetsTab extends StatelessWidget {
  const _SetsTab({required this.screen});
  final _InsightsScreenState screen;
  @override
  Widget build(BuildContext context) => screen._setsTab();
}

class _WeightTab extends StatelessWidget {
  const _WeightTab({required this.screen});
  final _InsightsScreenState screen;
  @override
  Widget build(BuildContext context) => screen._weightTab();
}

class _RepsTab extends StatelessWidget {
  const _RepsTab({required this.screen});
  final _InsightsScreenState screen;
  @override
  Widget build(BuildContext context) => screen._repsTab();
}
