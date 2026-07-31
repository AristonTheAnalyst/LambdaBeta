import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/custom_variation.dart';
import '../../../../data/repositories/exercise_repository.dart';
import '../../../../data/repositories/pr_repository.dart';
import '../../../../data/repositories/workout_repository.dart';
import '../../../../shared/widgets/multi_select_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../session/model/pr_engine.dart';

/// All PR types for one exercise: rep-max curve (grouped by rep range),
/// weight-max (filterable by weight), and the chronological timeline.
/// Variation is a multi-select filter at the top.
class PrExerciseDetailScreen extends StatefulWidget {
  const PrExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  State<PrExerciseDetailScreen> createState() => _PrExerciseDetailScreenState();
}

class _PrExerciseDetailScreenState extends State<PrExerciseDetailScreen> {
  static const _noVariation = '__none__'; // sentinel: PRs logged without a variation

  // Training rep-bands for grouping the rep-max curve.
  static const _repBands = [
    (label: 'STRENGTH', min: 1, max: 3),
    (label: 'STRENGTH ENDURANCE', min: 4, max: 6),
    (label: 'HYPERTROPHY', min: 7, max: 15),
    (label: 'ENDURANCE', min: 16, max: null),
  ];

  // Only these rep counts are shown on the rep-max curve — weight-class
  // already covers other rep maxes, so a sparse curve avoids redundancy.
  static const _displayRepCounts = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30};

  final _exerciseRepo = ExerciseRepository();
  final _prRepo = PrRepository();
  final _workoutRepo = WorkoutRepository();
  String? _exerciseName;
  List<CustomVariation> _variations = const [];
  List<PrRecord> _prs = const [];
  bool _loading = true;

  // Filters. Empty set = "all" for the multi-selects.
  Set<String> _selectedVariations = {}; // variationId, or _noVariation
  Set<num> _selectedWeights = {}; // weightMax weights

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Backfill (if fact_pr is empty) then filter to this exercise in memory —
    // mirrors the catalog's backfill so the detail is never blank even when
    // reached directly. The exercise catalog is secondary; a failure there
    // must not blank the PRs.
    try {
      final all = await _prRepo.loadAllWithBackfill(
          _userId, () => _workoutRepo.loadPastSetsTimeline(_userId));
      if (mounted) {
        setState(() => _prs =
            all.where((p) => p.exerciseId == widget.exerciseId).toList());
      }
    } catch (_) {}
    try {
      final map = await _exerciseRepo.fetchExerciseDetailMap(_userId);
      if (mounted) {
        setState(() {
          _exerciseName = map[widget.exerciseId]?.name;
          _variations = map[widget.exerciseId]?.assignedVariations ?? const [];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _matchesVariation(PrRecord p) {
    if (_selectedVariations.isEmpty) return true;
    final key = p.variationId ?? _noVariation;
    return _selectedVariations.contains(key);
  }

  bool _inBand(PrRecord p, ({String label, int min, int? max}) band) {
    if (p.type != PrType.repMax || p.targetReps == null) return false;
    if (p.targetReps! < band.min) return false;
    return band.max == null || p.targetReps! <= band.max!;
  }

  @override
  Widget build(BuildContext context) {
    final name = toProperCase(_exerciseName ?? widget.exerciseId);
    final prs = _prs.where(_matchesVariation).toList();

    // ── Rep-max curve (latest repMax record per display rep count) ──
    final curve = <int, PrRecord>{};
    for (final p in prs) {
      if (p.type == PrType.repMax && p.targetReps != null && _displayRepCounts.contains(p.targetReps!)) {
        curve[p.targetReps!] = p;
      }
    }

    // ── Weight-max (latest weightMax record per targetWeight) ──
    final weightMax = <num, PrRecord>{};
    for (final p in prs) {
      if (p.type == PrType.weightMax && p.targetWeight != null) {
        weightMax[p.targetWeight!] = p;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: name,
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.accent),
            ),
          ),
          _variationFilter(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _sectionCard(
                  title: 'REP-MAX CURVE',
                  children: [
                    if (curve.isEmpty)
                      _muted('No weighted PRs yet')
                    else
                      _repMaxContent(curve),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionCard(
                  title: 'WEIGHT MAX',
                  children: [
                    if (weightMax.isEmpty)
                      _muted('No weighted PRs yet')
                    else ...[
                      _weightMaxDropdown(weightMax),
                      const SizedBox(height: AppSpacing.sm),
                      for (final entry in _filteredWeightMax(weightMax).entries)
                        InkWell(
                          onTap: () => _showAxisHistorySheet(
                            context,
                            title: '${_fmt(entry.key)}kg history',
                            records: _prs
                                .where((p) =>
                                    p.type == PrType.weightMax &&
                                    p.targetWeight == entry.key)
                                .toList(),
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${_fmt(entry.key)}kg',
                                      style: AppFonts.ui(
                                          fontSize: AppTextStyles.sm,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary)),
                                ),
                                Text('${_fmt(entry.value.reps)} reps',
                                    style: AppFonts.mono(
                                        fontSize: 12, color: AppColors.accent)),
                                Icon(Icons.chevron_right,
                                    size: 16, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionCard(
                  title: 'TIMELINE (${prs.length} PRs)',
                  children: [
                    if (prs.isEmpty)
                      _muted('No PRs recorded')
                    else
                      for (final p in prs.reversed)
                        InkWell(
                          onTap: p.workoutId.isNotEmpty
                              ? () => context.push('/logs/${p.workoutId}')
                              : null,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_fmt(p.weight)}kg × ${_fmt(p.reps)}  ·  ${_fmtDate(p.achievedDate)}',
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.sm, color: AppColors.primary),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentBg,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: AppColors.accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(p.typeLabel,
                                      style: AppFonts.mono(
                                          fontSize: 9, color: AppColors.accent)),
                                ),
                                if (p.workoutId.isNotEmpty)
                                  Icon(Icons.chevron_right, size: 14, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Variation multi-select filter ─────────────────────────────────────────

  Widget _variationFilter() {
    final options = <MultiSelectOption<String>>[
      if (_prs.any((p) => p.variationId == null))
        const MultiSelectOption(label: 'No variation', value: _noVariation),
      for (final v in _variations)
        MultiSelectOption(label: toProperCase(v.name), value: v.variationId),
    ];
    final label = _selectedVariations.isEmpty
        ? 'All variations'
        : _selectedVariations
            .map((k) => k == _noVariation
                ? 'No variation'
                : toProperCase(_variations.firstWhere((v) => v.variationId == k, orElse: () => CustomVariation(variationId: k, userId: '', name: k, isActive: true)).name))
            .join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
      child: GestureDetector(
        onTap: () async {
          final result = await showMultiSelectSheet<String>(
            context,
            options: options,
            selected: _selectedVariations.toList(),
            title: 'Variations',
            confirmLabel: 'Done',
          );
          if (result != null) {
            setState(() => _selectedVariations = result.toSet());
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: _selectedVariations.isEmpty ? AppColors.border : AppColors.accent),
          ),
          child: Row(
            children: [
              Icon(Icons.filter_list, size: 16,
                  color: _selectedVariations.isEmpty ? AppColors.muted : AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w600,
                        color: _selectedVariations.isEmpty ? AppColors.muted : AppColors.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rep-max content ───────────────────────────────────────────────────────

  Widget _repMaxContent(Map<int, PrRecord> curve) {
    // Group the per-rep chips under each training band.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in _repBands) ?_repBandContent(b, curve),
      ],
    );
  }

  /// Chips for one training band, or null if the band has no records.
  Widget? _repBandContent(({String label, int min, int? max}) band, Map<int, PrRecord> curve) {
    final entries = curve.entries.where((e) => _inBand(e.value, band)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${band.label} · ${_rangeLabel(band)}',
              style: AppFonts.mono(fontSize: 10, letterSpacing: 0.6, color: AppColors.muted)),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: entries
              .map((e) => _repChip(e.key, e.value))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _repChip(int repCount, PrRecord record) {
    return GestureDetector(
      onTap: () => _showAxisHistorySheet(
        context,
        title: '${repCount}RM history',
        records: _prs.where((p) => p.type == PrType.repMax && p.targetReps == repCount).toList(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Text('${repCount}RM ${_fmt(record.weight)}',
            style: AppFonts.mono(fontSize: 11, color: AppColors.accent)),
      ),
    );
  }

  String _rangeLabel(({String label, int min, int? max}) band) =>
      band.max == null ? '${band.min}+RM' : '${band.min}–${band.max}RM';

  // ── Weight-class multi-select + helpers ───────────────────────────────────

  Widget _weightMaxDropdown(Map<num, PrRecord> weightMax) {
    return GestureDetector(
      onTap: () async {
        final sorted = weightMax.keys.toList()..sort((a, b) => b.compareTo(a));
        final result = await showMultiSelectSheet<num>(
          context,
          options: sorted
              .map((w) => MultiSelectOption(label: '${_fmt(w)}kg', value: w))
              .toList(),
          selected: _selectedWeights.toList(),
          title: 'Weights',
          confirmLabel: 'Done',
        );
        if (result != null) {
          setState(() => _selectedWeights = result.toSet());
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedWeights.isEmpty
                    ? 'All weights'
                    : _selectedWeights.map(_fmt).join(' · '),
                style: AppFonts.mono(fontSize: 11, color: AppColors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Map<num, PrRecord> _filteredWeightMax(Map<num, PrRecord> weightMax) {
    if (_selectedWeights.isEmpty) return weightMax;
    return Map.fromEntries(weightMax.entries.where((e) => _selectedWeights.contains(e.key)));
  }

  // ── Axis history sheet ────────────────────────────────────────────────────

  /// Bottom sheet showing the full PR history for one axis — e.g. every
  /// 5RM record ever hit, or every record at 100kg. Each row opens the
  /// past session it came from.
  void _showAxisHistorySheet(BuildContext context,
      {required String title, required List<PrRecord> records}) {
    final sorted = [...records]
      ..sort((a, b) => b.achievedDate.compareTo(a.achievedDate));
    showLambdaModal(
      context,
      fitContent: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: AppFonts.ui(
                      fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.lg),
              if (sorted.isEmpty)
                _muted('No history for this PR.')
              else
                for (final p in sorted)
                  InkWell(
                    onTap: p.workoutId.isNotEmpty
                        ? () => context.push('/logs/${p.workoutId}')
                        : null,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${_fmt(p.weight)}kg × ${_fmt(p.reps)}',
                                    style: AppFonts.mono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                Text(_fmtDate(p.achievedDate),
                                    style: AppFonts.mono(
                                        fontSize: 10, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          if (p.workoutId.isNotEmpty)
                            Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppFonts.mono(
                  fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _muted(String text) => Text(text,
      style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted));

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
