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
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/multi_select_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../session/model/pr_engine.dart';

/// All PR types for one exercise: best lift, rep-max curve (grouped by rep
/// range), weight-class (filterable by weight), and the chronological
/// timeline. Variation is a multi-select filter at the top.
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

  final _exerciseRepo = ExerciseRepository();
  final _prRepo = PrRepository();
  String? _exerciseName;
  List<CustomVariation> _variations = const [];
  List<PrRecord> _prs = const [];

  // Filters. Empty set = "all" for the multi-selects.
  Set<String> _selectedVariations = {}; // variationId, or _noVariation
  String? _repRange; // null = all ranges
  Set<num> _selectedWeights = {}; // weightClass weights

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final map = await _exerciseRepo.fetchExerciseDetailMap(_userId);
      final prs = await _prRepo.loadAll(_userId);
      if (!mounted) return;
      setState(() {
        _exerciseName = map[widget.exerciseId]?.name;
        _variations = map[widget.exerciseId]?.assignedVariations ?? const [];
        _prs = prs.where((p) => p.exerciseId == widget.exerciseId).toList();
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
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

    // ── Best lift (best weight × reps for the variation filter) ──
    final bestLift = _bestLift(prs);

    // ── Rep-max curve (latest repMax record per targetReps) ──
    final curve = <int, PrRecord>{};
    for (final p in prs) {
      if (p.type == PrType.repMax && p.targetReps != null) {
        curve[p.targetReps!] = p;
      }
    }

    // ── Weight-class (latest weightClass record per targetWeight) ──
    final weightClass = <num, PrRecord>{};
    for (final p in prs) {
      if (p.type == PrType.weightClass && p.targetWeight != null) {
        weightClass[p.targetWeight!] = p;
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
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _sectionCard(
                  title: 'BEST LIFT',
                  children: [
                    if (bestLift == null)
                      _muted('No weighted PR yet')
                    else
                      Text(
                        '${_fmt(bestLift.weight)}kg × ${_fmt(bestLift.reps)}',
                        style: AppFonts.mono(
                            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    if (bestLift != null) ...[
                      const SizedBox(height: 2),
                      _muted(_fmtDate(bestLift.achievedDate)),
                    ],
                    const SizedBox(height: 6),
                    _muted('Best weight × reps — any variation, any rep count.'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionCard(
                  title: 'REP-MAX CURVE',
                  children: [
                    if (curve.isEmpty)
                      _muted('No weighted PRs yet')
                    else ...[
                      _repRangeDropdown(),
                      const SizedBox(height: AppSpacing.sm),
                      _repMaxContent(curve),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionCard(
                  title: 'WEIGHT-CLASS (most reps)',
                  children: [
                    if (weightClass.isEmpty)
                      _muted('No weighted PRs yet')
                    else ...[
                      _weightClassDropdown(weightClass),
                      const SizedBox(height: AppSpacing.sm),
                      for (final entry in _filteredWeightClass(weightClass).entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
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
                            ],
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

  /// Best weight × reps among [prs] (ties broken by higher reps).
  PrRecord? _bestLift(List<PrRecord> prs) {
    PrRecord? best;
    for (final p in prs) {
      if (p.type != PrType.absolute) continue;
      if (best == null ||
          p.weight > best.weight ||
          (p.weight == best.weight && p.reps > best.reps)) {
        best = p;
      }
    }
    return best;
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

  // ── Rep-max dropdown + content ────────────────────────────────────────────

  Widget _repRangeDropdown() {
    return DropdownSelect<String?>(
      options: [
        const DropdownOption<String?>(label: 'All ranges', value: null),
        for (final band in _repBands)
          DropdownOption<String?>(
              label: '${band.label} · ${_rangeLabel(band)}', value: band.label),
      ],
      value: _repRange,
      onChange: (v) => setState(() => _repRange = v),
      placeholder: 'Rep range',
      compact: true,
    );
  }

  Widget _repMaxContent(Map<int, PrRecord> curve) {
    // Selected band → show that band's per-rep chips.
    final band = _repBands.where((b) => b.label == _repRange).firstOrNull;
    if (band != null) {
      final entries = curve.entries
          .where((e) => _inBand(e.value, band))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      if (entries.isEmpty) return _muted('No records in ${band.label.toLowerCase()} range.');
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: entries
            .map((e) => _repChip('${e.key}RM', _fmt(e.value.weight)))
            .toList(),
      );
    }

    // All ranges → the full per-rep curve (1RM, 2RM, 3RM, …).
    final entries = curve.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return _muted('No weighted PRs yet');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries
          .map((e) => _repChip('${e.key}RM', _fmt(e.value.weight)))
          .toList(),
    );
  }

  Widget _repChip(String label, String weight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text('$label $weight',
          style: AppFonts.mono(fontSize: 11, color: AppColors.accent)),
    );
  }

  String _rangeLabel(({String label, int min, int? max}) band) =>
      band.max == null ? '${band.min}+RM' : '${band.min}–${band.max}RM';

  // ── Weight-class multi-select + helpers ───────────────────────────────────

  Widget _weightClassDropdown(Map<num, PrRecord> weightClass) {
    return GestureDetector(
      onTap: () async {
        final sorted = weightClass.keys.toList()..sort((a, b) => b.compareTo(a));
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

  Map<num, PrRecord> _filteredWeightClass(Map<num, PrRecord> weightClass) {
    if (_selectedWeights.isEmpty) return weightClass;
    return Map.fromEntries(weightClass.entries.where((e) => _selectedWeights.contains(e.key)));
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
