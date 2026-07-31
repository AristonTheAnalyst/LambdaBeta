import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/exercise_detail.dart';
import '../../../../data/repositories/exercise_repository.dart';
import '../../../../data/repositories/pr_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../session/model/pr_engine.dart';

/// Dev-only catalog of every exercise with its PR record count, linking to a
/// per-exercise PR breakdown page.
class PrCatalogScreen extends StatefulWidget {
  const PrCatalogScreen({super.key});

  @override
  State<PrCatalogScreen> createState() => _PrCatalogScreenState();
}

class _PrCatalogScreenState extends State<PrCatalogScreen> {
  final _exerciseRepo = ExerciseRepository();
  final _prRepo = PrRepository();
  Map<String, ExerciseDetail>? _exerciseMap;
  List<PrRecord> _prs = const [];

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _prRepo.loadAll(_userId),
      ]);
      if (!mounted) return;
      setState(() {
        _exerciseMap = results[0] as Map<String, ExerciseDetail>;
        _prs = results[1] as List<PrRecord>;
      });
    } catch (_) {
      if (mounted) setState(() => _exerciseMap = {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = _exerciseMap;
    final exercises = map?.values.toList() ?? const <ExerciseDetail>[];
    final prCounts = <String, int>{};
    for (final pr in _prs) {
      prCounts[pr.exerciseId] = (prCounts[pr.exerciseId] ?? 0) + 1;
    }
    final sorted = [...exercises]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Personal Records'),
          Expanded(
            child: map == null
                ? const Center(child: CircularProgressIndicator())
                : sorted.isEmpty
                    ? Center(
                        child: Text('No exercises set up yet.',
                            style: AppFonts.ui(fontSize: AppTextStyles.md, color: AppColors.muted)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: sorted.length,
                        itemBuilder: (context, i) {
                          final ex = sorted[i];
                          final count = prCounts[ex.exerciseId] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: AppCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              child: PressSquash(
                                onTap: () => context.push('/dev/prs/${ex.exerciseId}'),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(toProperCase(ex.name),
                                          style: AppFonts.ui(
                                              fontSize: AppTextStyles.md,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary)),
                                    ),
                                    if (count > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentBg,
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                              color: AppColors.accent.withValues(alpha: 0.35)),
                                        ),
                                        child: Text('$count PR${count == 1 ? '' : 's'}',
                                            style: AppFonts.mono(
                                                fontSize: 10, color: AppColors.accent)),
                                      ),
                                    Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                                  ],
                                ),
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
