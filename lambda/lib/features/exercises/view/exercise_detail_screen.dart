import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/date_range.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/pr_view_setting_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/date_range_selector.dart';
import '../../../shared/widgets/section_divider.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../session/model/pr_engine.dart';
import '../model/exercise_insights.dart';
import '../viewmodel/exercise_viewmodel.dart';

/// Dedicated per-exercise insights page: header (back, name + variation,
/// edit), variation dropdown, date filter (1M/3M/6M/1Y/Custom), metrics
/// card, and the PR journey ladder. All metrics and the ladder respect the
/// active date filter; variation switching keeps the filter.
class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.exerciseName,
  });

  final String exerciseId;
  final String? exerciseName;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final _viewModel = ExerciseViewModel();
  final _sessionRepo = SessionRepository();
  final _lessonRepo = LessonRepository();
  String? _name;
  List<PastSetRow> _sets = const [];
  bool _loading = true;
  String? _error;

  /// null = 'No Variation' (the default, only when such sets exist).
  String? _variationId;

  /// The active date filter — defaults to ALL (no filtering), the shared
  /// [DateRangeSelection] the Training Logs also use.
  DateRangeSelection _selection =
      const DateRangeSelection.preset(DateRangePreset.all);

  /// PR Journey mode: false = rep-max axes, true = per-weight max reps.
  bool _weightMode = false;

  /// Hidden journey axes (per this exercise only, insights page only).
  Set<int> _hiddenReps = {};
  Set<String> _hiddenWeights = {};

  /// All-time lesson count for this exercise (knowledge isn't windowed).
  int _lessonsTotal = 0;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _name = widget.exerciseName;
    _load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sets = await _sessionRepo.loadPastSetsTimeline(_userId);
      final hidden = await PrViewSettingRepository().fetchHidden(
        _userId,
        widget.exerciseId,
      );
      final lessons = await _lessonRepo.fetchLessons(
        _userId,
        widget.exerciseId,
      );
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _hiddenReps = hidden.hiddenReps;
        _hiddenWeights = hidden.hiddenWeights;
        _lessonsTotal = lessons.length;
        _loading = false;
        // 'No Variation' is the default ONLY when such sets exist —
        // otherwise default to the first variation that has data.
        if (_variationId == null) {
          final exerciseSets = setsForExercise(sets, widget.exerciseId);
          final hasNoVariation =
              exerciseSets.any((s) => s.variationId == null);
          if (!hasNoVariation) {
            final vs = variationsFor(exerciseSets);
            if (vs.isNotEmpty) _variationId = vs.first.id;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Derived data (all respect variation + date filter) ────────────────────

  List<PastSetRow> get _exerciseSets =>
      setsForExercise(_sets, widget.exerciseId);

  List<PastSetRow> get _scoped =>
      setsScoped(_sets, widget.exerciseId, _variationId);

  List<({String? id, String name})> get _variations =>
      variationsFor(_exerciseSets);

  bool get _hasNoVariationSets =>
      _exerciseSets.any((s) => s.variationId == null);

  ({DateTime from, DateTime to}) get _window =>
      _selection.window(DateTime.now());

  Future<void> _openDateSelector() async {
    final sel = await showDateRangeSelector(
      context,
      initial: _selection,
    );
    if (sel != null && mounted) {
      setState(() => _selection = sel);
    }
  }

  static String _wfmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  /// Toggles one journey axis's visibility, persisting to the per-exercise
  /// view settings (insights page only — the summary card and everything
  /// else are unaffected).
  Future<void> _toggleAxis(
    String axisType,
    String axisValue, {
    required bool hide,
  }) async {
    final repo = PrViewSettingRepository();
    if (hide) {
      await repo.hideAxis(_userId, widget.exerciseId, axisType, axisValue);
    } else {
      await repo.showAxis(_userId, widget.exerciseId, axisType, axisValue);
    }
    final hidden = await repo.fetchHidden(_userId, widget.exerciseId);
    if (mounted) {
      setState(() {
        _hiddenReps = hidden.hiddenReps;
        _hiddenWeights = hidden.hiddenWeights;
      });
    }
  }

  void _openViewSettings() {
    final w = _window;
    final options = <({String label, String value})>[];
    String axisType;
    final bool Function(String) isHidden;
    if (!_weightMode) {
      axisType = 'reps';
      options.addAll([
        for (final n in kTrackedRepCounts) (label: '${n}RM', value: '$n'),
      ]);
      isHidden = (v) => _hiddenReps.contains(int.tryParse(v));
    } else {
      axisType = 'weight';
      final windowSets = _scoped
          .where(
            (s) =>
                !s.sessionCreatedDate.isBefore(w.from) &&
                s.sessionCreatedDate.isBefore(w.to),
          )
          .toList();
      options.addAll([
        for (final weight in weightsByUsage(windowSets))
          (label: '${_wfmt(weight)}kg', value: _wfmt(weight)),
      ]);
      isHidden = (v) => _hiddenWeights.contains(v);
    }
    showLambdaModal(
      context,
      fitContent: true,
      child: _ViewSettingsSheet(
        title: _weightMode ? 'Weights' : 'Rep Maxes',
        options: options,
        isHidden: isHidden,
        onToggle: (value, hide) =>
            _toggleAxis(axisType, value, hide: hide),
      ),
    );
  }

  // ── Edit menu (rename / delete) ───────────────────────────────────────────

  Future<void> _openEditMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(_name ?? 'Exercise',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('rename'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Rename',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('delete'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Delete',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (action == 'rename') await _rename();
    if (action == 'delete') await _archive();
  }

  Future<void> _rename() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameExerciseDialog(initialName: _name),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await _viewModel.renameExercise(widget.exerciseId, newName);
    if (mounted) setState(() => _name = newName.trim());
  }

  /// Deletes a never-used exercise outright; archives a used one. The dialog
  /// copy follows the usage state so the user always knows which happened.
  Future<void> _archive() async {
    final used =
        await _viewModel.exerciseUsageCount(widget.exerciseId) > 0;
    if (!mounted) return;
    final name = _name ?? 'this exercise';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(used ? 'Archive exercise' : 'Delete exercise',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            used
                ? 'Archive "$name"? It has been used, so it can\'t be fully '
                  'deleted — it will disappear from pickers, but your logged '
                  'history keeps its name.'
                : 'Delete "$name"? This can\'t be undone.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(used ? 'Archive' : 'Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _viewModel.deleteExercise(widget.exerciseId);
    if (mounted) context.pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String get _headerTitle {
    final name = _name ?? 'Exercise';
    if (_variationId == null) return name;
    final v = _variations
        .where((v) => v.id == _variationId)
        .firstOrNull;
    return v == null ? name : '$name · ${v.name}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: _headerTitle,
              titleWidget: PopupMenuButton<String?>(
                onSelected: (id) => setState(() => _variationId = id),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                itemBuilder: (ctx) => [
                  if (_hasNoVariationSets)
                    PopupMenuItem<String?>(
                      value: null,
                      child: Text(
                        'No Variation',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  for (final v in _variations)
                    PopupMenuItem<String?>(
                      value: v.id,
                      child: Text(
                        v.name,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: lambdaBox(
                    ContainerTone.ghost,
                    radius: AppRadius.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              left: GestureDetector(
                onTap: () => context.pop(),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: AppColors.accent,
                ),
              ),
              right: GestureDetector(
                onTap: _openEditMenu,
                child: Icon(
                  Icons.more_horiz,
                  size: 22,
                  color: AppColors.accent,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? _Skeleton()
                  : _error != null
                      ? _ErrorState(onRetry: _load)
                      : _body(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final w = _window;
    final prs = prsInWindow(_scoped, w.from, w.to);
    final setsInWindow = _scoped
        .where(
          (s) =>
              !s.sessionCreatedDate.isBefore(w.from) &&
              s.sessionCreatedDate.isBefore(w.to),
        )
        .length;
    final activeWeeks = activeWeeksInWindow(_scoped, w.from, w.to);

    // ── PR Journey rows ──
    // Reps mode: every tracked rep-max axis, start vs end of window.
    // Weight mode: the most-used weights, max reps at each, start vs end.
    // Each row counts how many times the window extended that axis — the
    // axis-history LENS (per-axis progression over raw sets), not the
    // PR-event count.
    bool inWindow(DateTime d) => !d.isBefore(w.from) && d.isBefore(w.to);
    final startCurve = curveAt(_scoped, w.from);
    final endCurve = curveAt(_scoped, w.to);
    final journeyRows = <Widget>[];
    if (!_weightMode) {
      for (final n in kTrackedRepCounts) {
        if (_hiddenReps.contains(n)) continue;
        final endV = endCurve[n];
        final count = repAxisHistory(_scoped, n)
            .where((s) => inWindow(s.sessionCreatedDate))
            .length;
        journeyRows.add(
          _CurveRow(
            label: '${n}RM',
            start: startCurve[n],
            end: endV,
            unit: 'kg',
            prCount: endV == null ? null : count,
          ),
        );
      }
    } else {
      final windowSets =
          _scoped.where((s) => inWindow(s.sessionCreatedDate)).toList();
      for (final weight in weightsByUsage(windowSets)) {
        if (_hiddenWeights.contains(_wfmt(weight))) continue;
        final endReps = maxRepsAtWeight(_scoped, w.to, weight);
        final count = weightAxisHistory(_scoped, weight)
            .where((s) => inWindow(s.sessionCreatedDate))
            .length;
        journeyRows.add(
          _CurveRow(
            label: '${_wfmt(weight)}kg',
            start: maxRepsAtWeight(_scoped, w.from, weight),
            end: endReps,
            prCount: endReps == null ? null : count,
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ── Date filter — one pill naming the active selection; tapping it
        // opens the date-range selector sheet.
        GestureDetector(
          onTap: _openDateSelector,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: glassBox(AppColors.primary),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selection.label(DateTime.now()),
                  style: AppFonts.mono(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // ── Summary ──
        const SectionDivider('SUMMARY'),
        const SizedBox(height: AppSpacing.md),
        _MetricsCard(
          prsTotal: prs.length,
          prFreq: activeWeeks == 0 ? null : prs.length / activeWeeks,
          setsPerWeek:
              activeWeeks == 0 ? null : setsInWindow / activeWeeks,
          lessonsTotal: _lessonsTotal,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Per-week rates count only weeks where this exercise was trained.',
          style: AppFonts.mono(
            fontSize: 13,
            color: AppColors.muted.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // ── PR journey ──
        const SectionDivider('PR JOURNEY'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: SegmentedControl<bool>(
                subtle: true,
                options: const [
                  SegmentOption(label: 'Reps', value: false),
                  SegmentOption(label: 'Weight', value: true),
                ],
                value: _weightMode,
                onChange: (v) => setState(() => _weightMode = v),
              ),
            ),
            const Spacer(),
            GlassButton(
              label: '',
              icon: Icons.tune,
              compact: true,
              onPressed: _openViewSettings,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...journeyRows,
      ],
    );
  }
}

// ── Metrics card ──

/// Four-tile summary card styled like the session screens' stats bar —
/// border-contained, divider-separated, centered mono tiles — but built
/// locally (not via StatsRow) so the two surfaces never drift together.
class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.prsTotal,
    required this.prFreq,
    required this.setsPerWeek,
    required this.lessonsTotal,
  });

  final int prsTotal;
  final double? prFreq;
  final double? setsPerWeek;
  final int lessonsTotal;

  static const _labels = ['PRs Total', 'PRs/Week', 'Sets/Week', 'Lessons'];

  List<String> get _values => [
    '$prsTotal',
    prFreq == null ? '—' : '${prFreq!.round()}',
    setsPerWeek == null ? '—' : '${setsPerWeek!.round()}',
    '$lessonsTotal',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: lambdaBox(ContainerTone.accent),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Column(
                  children: [
                    Text(
                      _labels[i],
                      textAlign: TextAlign.center,
                      style: AppFonts.mono(
                        fontSize: 14,
                        letterSpacing: 0.8,
                        color: AppColors.accent.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (i == 0) ...[
                          Icon(
                            Icons.emoji_events_outlined,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            _values[i],
                            style: AppFonts.mono(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── PR journey row: start-of-window value → end-of-window value ──────────────

class _CurveRow extends StatelessWidget {
  const _CurveRow({
    required this.label,
    required this.start,
    required this.end,
    this.unit = '',
    this.prCount,
  });

  final String label;
  final num? start;
  final num? end;
  final String unit;

  /// PRs on this axis within the window (propagated included) — shown only
  /// for established rows.
  final int? prCount;

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  String _v(num? v) => v == null ? 'None' : '${_fmt(v)}$unit';

  @override
  Widget build(BuildContext context) {
    // Unestablished axis → the whole row greys out.
    final established = end != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: established
            ? lambdaBox(ContainerTone.surface, radius: AppRadius.md)
            : lambdaBox(ContainerTone.ghost, radius: AppRadius.md)
                .copyWith(border: null),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: AppFonts.mono(
                  fontSize: 13,
                  color: established ? AppColors.muted : AppColors.muted
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            Text(
              _v(start),
              style: AppFonts.mono(
                fontSize: AppTextStyles.sm,
                color: start == null
                    ? AppColors.muted.withValues(alpha: 0.5)
                    : AppColors.muted,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Icon(
                Icons.arrow_forward,
                size: 14,
                color: established
                    ? AppColors.accent
                    : AppColors.muted.withValues(alpha: 0.4),
              ),
            ),
            Expanded(
              child: Text(
                _v(end),
                style: AppFonts.mono(
                  fontSize: AppTextStyles.md,
                  fontWeight: FontWeight.w700,
                  color: established
                      ? AppColors.accent
                      : AppColors.muted.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (prCount != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: lambdaBox(
                  prCount! > 0
                      ? ContainerTone.accent
                      : ContainerTone.ghost,
                  radius: 999,
                ).copyWith(
                  border: prCount! > 0
                      ? Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35),
                        )
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 12,
                      color: prCount! > 0
                          ? AppColors.accent
                          : AppColors.muted.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$prCount',
                      style: AppFonts.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: prCount! > 0
                            ? AppColors.accent
                            : AppColors.muted.withValues(alpha: 0.6),
                      ),
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

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget box(double height, [double? width]) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        box(40),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          for (var i = 0; i < 5; i++) ...[
            box(32, 64),
            if (i < 4) const SizedBox(width: AppSpacing.sm),
          ],
        ]),
        const SizedBox(height: AppSpacing.md),
        box(120),
        const SizedBox(height: AppSpacing.lg),
        box(24, 220),
        const SizedBox(height: AppSpacing.md),
        box(44),
        const SizedBox(height: AppSpacing.sm),
        box(44),
        const SizedBox(height: AppSpacing.sm),
        box(44),
      ],
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Unable to load data',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

// ── View settings sheet ───────────────────────────────────────────────────────

/// Checklist of journey axes — checked = visible. Toggling persists
/// immediately and the page updates live behind the sheet.
class _ViewSettingsSheet extends StatefulWidget {
  const _ViewSettingsSheet({
    required this.title,
    required this.options,
    required this.isHidden,
    required this.onToggle,
  });

  final String title;
  final List<({String label, String value})> options;
  final bool Function(String value) isHidden;
  final Future<void> Function(String value, bool hide) onToggle;

  @override
  State<_ViewSettingsSheet> createState() => _ViewSettingsSheetState();
}

class _ViewSettingsSheetState extends State<_ViewSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Checked axes show in your PR journey. This only affects the '
              'insights page.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.options.length,
                itemBuilder: (context, i) {
                  final opt = widget.options[i];
                  final hidden = widget.isHidden(opt.value);
                  return InkWell(
                    onTap: () async {
                      await widget.onToggle(opt.value, !hidden);
                      if (mounted) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hidden
                                ? Icons.check_box_outline_blank
                                : Icons.check_box,
                            size: 18,
                            color: hidden
                                ? AppColors.muted
                                : AppColors.accent,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            opt.label,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.md,
                              fontWeight: FontWeight.w600,
                              color: hidden
                                  ? AppColors.muted.withValues(alpha: 0.7)
                                  : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rename dialog ─────────────────────────────────────────────────────────────

/// Rename prompt. Owns its [TextEditingController] so the controller is
/// disposed when the dialog route is fully removed (after the exit
/// animation) — disposing it right after `showDialog` returns crashes,
/// because the TextField is still mounted and rebuilding during the pop
/// animation.
class _RenameExerciseDialog extends StatefulWidget {
  const _RenameExerciseDialog({required this.initialName});

  final String? initialName;

  @override
  State<_RenameExerciseDialog> createState() => _RenameExerciseDialogState();
}

class _RenameExerciseDialogState extends State<_RenameExerciseDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Rename exercise',
          style: AppFonts.ui(
              fontWeight: FontWeight.w800, color: AppColors.primary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This updates the name everywhere — all past sessions included.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: AppFonts.ui(color: AppColors.primary),
            decoration: InputDecoration(
              hintText: 'Exercise name',
              hintStyle: AppFonts.ui(color: AppColors.muted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text('Save',
                style: AppFonts.ui(
                    color: AppColors.accent, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
