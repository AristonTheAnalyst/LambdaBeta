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
import '../../../../shared/widgets/page_header.dart';
import '../../session/model/pr_engine.dart';

/// All PR types for one exercise, filterable by variation: best lift,
/// rep-max curve, weight-class, and the chronological timeline.
class PrExerciseDetailScreen extends StatefulWidget {
  const PrExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  State<PrExerciseDetailScreen> createState() => _PrExerciseDetailScreenState();
}

class _PrExerciseDetailScreenState extends State<PrExerciseDetailScreen> {
  static const _noVariation = '__none__'; // sentinel: PRs logged without a variation

  final _exerciseRepo = ExerciseRepository();
  final _prRepo = PrRepository();
  String? _exerciseName;
  List<CustomVariation> _variations = const [];
  List<PrRecord> _prs = const [];
  String? _filter; // null = all variations; _noVariation = no variation; else variationId

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

  bool _matches(PrRecord p) {
    if (_filter == null) return true;
    if (_filter == _noVariation) return p.variationId == null;
    return p.variationId == _filter;
  }

  @override
  Widget build(BuildContext context) {
    final name = toProperCase(_exerciseName ?? widget.exerciseId);
    final prs = _prs.where(_matches).toList();

    // ── Best lift (best weight × reps for the current filter) ──
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
          _filterBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _sectionCard(
                  title: _filter == null ? 'BEST LIFT' : 'BEST LIFT (${_filterLabel(_filter!)})',
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
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: curve.entries
                            .map((e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentBg,
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(
                                        color: AppColors.accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Text('${e.key}RM ${_fmt(e.value.weight)}kg',
                                      style: AppFonts.mono(
                                          fontSize: 12, color: AppColors.accent)),
                                ))
                            .toList(),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _sectionCard(
                  title: 'WEIGHT-CLASS (most reps)',
                  children: [
                    if (weightClass.isEmpty)
                      _muted('No weighted PRs yet')
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: weightClass.entries
                            .map((e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentBg,
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(
                                        color: AppColors.accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Text('${_fmt(e.key)}kg × ${_fmt(e.value.reps)}',
                                      style: AppFonts.mono(
                                          fontSize: 12, color: AppColors.accent)),
                                ))
                            .toList(),
                      ),
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

  /// Best weight × reps among [prs] (ties broken by higher reps) — the
  /// overall/absolute best for the current variation filter.
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

  // ── Variation filter bar ──────────────────────────────────────────────────

  Widget _filterBar() {
    final options = <(String, String?)>[
      ('All', null),
      if (_prs.any((p) => p.variationId == null)) (_noVariationLabel, _noVariation),
      for (final v in _variations) (toProperCase(v.name), v.variationId),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (label, value) = options[i];
          final active = value == _filter;
          return GestureDetector(
            onTap: () => setState(() => _filter = value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.accentBg : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: active ? AppColors.accent : AppColors.border),
              ),
              child: Text(label,
                  style: AppFonts.ui(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.accent : AppColors.muted)),
            ),
          );
        },
      ),
    );
  }

  static const _noVariationLabel = 'No variation';

  String _filterLabel(String value) => value == _noVariation ? _noVariationLabel : toProperCase(value);

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
