import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/repositories/exercise_repository.dart';
import '../../../../data/repositories/pr_repository.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../session/model/pr_engine.dart';

/// All PR types for one exercise: absolute, rep-max curve, weight-class,
/// per-variation bests, and the chronological timeline.
class PrExerciseDetailScreen extends StatefulWidget {
  const PrExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  State<PrExerciseDetailScreen> createState() => _PrExerciseDetailScreenState();
}

class _PrExerciseDetailScreenState extends State<PrExerciseDetailScreen> {
  final _exerciseRepo = ExerciseRepository();
  final _prRepo = PrRepository();
  String? _exerciseName;
  List<PrRecord> _prs = const [];

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
        _prs = prs.where((p) => p.exerciseId == widget.exerciseId).toList();
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = toProperCase(_exerciseName ?? widget.exerciseId);
    final prs = _prs;

    // ── Current best absolute ──
    final absolute = prs.where((p) => p.type == PrType.absolute).toList();
    final currentAbs = absolute.isEmpty ? null : absolute.last;

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

    // ── Per-variation best (latest absolute record per variation) ──
    final byVariation = <String?, PrRecord>{};
    for (final p in absolute) {
      byVariation[p.variationId] = p;
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _sectionCard(
                  title: 'ABSOLUTE',
                  children: [
                    if (currentAbs == null)
                      _muted('No weighted PR yet')
                    else
                      Text(
                        '${_fmt(currentAbs.weight)}kg × ${_fmt(currentAbs.reps)}',
                        style: AppFonts.mono(
                            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    if (currentAbs != null) ...[
                      const SizedBox(height: 2),
                      _muted(_fmtDate(currentAbs.achievedDate)),
                    ],
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
                  title: 'PER VARIATION',
                  children: [
                    if (byVariation.isEmpty)
                      _muted('No PRs yet')
                    else
                      for (final entry in byVariation.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.value.variationName != null
                                      ? toProperCase(entry.value.variationName!)
                                      : 'Default',
                                  style: AppFonts.ui(
                                      fontSize: AppTextStyles.sm,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary),
                                ),
                              ),
                              Text(
                                '${_fmt(entry.value.weight)}kg × ${_fmt(entry.value.reps)}',
                                style: AppFonts.mono(
                                    fontSize: 12, color: AppColors.accent),
                              ),
                            ],
                          ),
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

  static String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}
