import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/repositories/pr_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import '../../../shared/widgets/stats_row.dart';
import '../model/pr_engine.dart';

class PrLibraryScreen extends StatefulWidget {
  const PrLibraryScreen({super.key});

  @override
  State<PrLibraryScreen> createState() => _PrLibraryScreenState();
}

class _PrLibraryScreenState extends State<PrLibraryScreen> {
  final _workoutRepo = WorkoutRepository();
  final _prRepo = PrRepository();
  List<PrRecord>? _prs;
  int _tab = 0;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prs = await _prRepo.loadAllWithBackfill(
          _userId, () => _workoutRepo.loadPastSetsTimeline(_userId));
      if (mounted) setState(() => _prs = prs);
    } catch (_) {
      if (mounted) setState(() => _prs = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prs = _prs;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'PR Library'),
          SlideTabBar(
            tabs: const ['All PRs', 'By Exercise', 'Timeline'],
            activeIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: prs == null
                ? const Center(child: CircularProgressIndicator())
                : prs.isEmpty
                    ? _EmptyPRs()
                    : switch (_tab) {
                        0 => _AllPrsView(prs: prs),
                        1 => _ByExerciseView(prs: prs),
                        _ => _TimelineView(prs: prs),
                      },
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyPRs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No PRs yet — log some workouts first!',
          style: AppFonts.ui(fontSize: AppTextStyles.md, color: AppColors.muted)),
    );
  }
}

// ── All PRs tab ───────────────────────────────────────────────────────────────

class _AllPrsView extends StatelessWidget {
  const _AllPrsView({required this.prs});
  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    // Current best per exercise = the latest absolute record per exercise
    final byExercise = <String, List<PrRecord>>{};
    for (final pr in prs) {
      if (pr.type == PrType.absolute) {
        byExercise.putIfAbsent(pr.exerciseId, () => []).add(pr);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        StatsRow(tiles: [
          StatsTile(label: 'PRS', value: '${byExercise.length}'),
          StatsTile(label: 'TOTAL', value: '${prs.length}'),
          StatsTile(label: 'EXERCISES', value: '${byExercise.length}'),
        ]),
        const SizedBox(height: AppSpacing.lg),
        for (final entry in byExercise.entries)
          _ExercisePrCard(prs: entry.value),
      ],
    );
  }
}

class _ExercisePrCard extends StatelessWidget {
  const _ExercisePrCard({required this.prs});
  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    final pr = prs.last; // chronological; last absolute = current best
    final name = toProperCase(pr.exerciseName ?? pr.exerciseId);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: AppFonts.ui(
                  fontSize: AppTextStyles.md, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Text('Absolute PR: ${_fmt(pr.weight)}kg × ${_fmt(pr.reps)}',
              style: AppFonts.mono(fontSize: 13, color: AppColors.accent)),
        ],
      ),
    );
  }

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

// ── By Exercise tab ───────────────────────────────────────────────────────────

class _ByExerciseView extends StatelessWidget {
  const _ByExerciseView({required this.prs});
  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    final exercises = <String, String?>{};
    for (final pr in prs) {
      exercises.putIfAbsent(pr.exerciseId, () => pr.exerciseName);
    }
    final sorted = exercises.keys.toList()..sort((a, b) => (exercises[a] ?? a).toLowerCase().compareTo((exercises[b] ?? b).toLowerCase()));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: sorted.map((exId) {
        final exPrs = prs.where((p) => p.exerciseId == exId).toList();
        // Build rep-max curve from repMax records
        final curve = <int, num>{};
        for (final p in exPrs) {
          if (p.type == PrType.repMax && p.targetReps != null) {
            curve[p.targetReps!] = p.weight;
          }
        }
        return _ExerciseDetailCard(exerciseId: exId, name: exercises[exId] ?? exId, prs: exPrs, curve: curve);
      }).toList(),
    );
  }
}

class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({
    required this.exerciseId,
    required this.name,
    required this.prs,
    required this.curve,
  });

  final String exerciseId;
  final String name;
  final List<PrRecord> prs;
  final Map<int, num> curve;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(toProperCase(name),
              style: AppFonts.ui(
                  fontSize: AppTextStyles.md, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Text('REP-MAX CURVE',
              style: AppFonts.mono(fontSize: 8, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          if (curve.isEmpty)
            Text('No weighted sets yet', style: AppFonts.ui(fontSize: 12, color: AppColors.muted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: curve.entries
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentBg,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text('${e.key}RM ${_fmt(e.value)}kg',
                            style: AppFonts.mono(fontSize: 11, color: AppColors.accent)),
                      ))
                  .toList(),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text('PRs set: ${prs.length}',
              style: AppFonts.ui(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

// ── Timeline tab ──────────────────────────────────────────────────────────────

class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.prs});
  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    // Group by workout (date)
    final byWorkout = <String, List<PrRecord>>{};
    for (final pr in prs) {
      byWorkout.putIfAbsent(pr.workoutId, () => []).add(pr);
    }
    final workouts = byWorkout.entries.toList()
      ..sort((a, b) => b.value.first.achievedDate.compareTo(a.value.first.achievedDate));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: workouts.map((w) {
        final date = w.value.first.achievedDate;
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}/${date.month}/${date.year} — ${w.value.length} PRs',
                style: AppFonts.mono(fontSize: 10, letterSpacing: 0.6, color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final pr in w.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${toProperCase(pr.exerciseName ?? '')}  ${_fmt(pr.weight)}kg × ${_fmt(pr.reps)}',
                          style: AppFonts.ui(fontSize: 13, color: AppColors.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(pr.typeLabel,
                            style: AppFonts.mono(fontSize: 9, color: AppColors.accent)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
