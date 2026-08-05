import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/workout_plan.dart';
import '../../../../data/repositories/workout_plan_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/page_header.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_workout_screen.dart';

/// Library of standalone planned workouts (a single session, no program).
class WorkoutLibraryScreen extends StatefulWidget {
  const WorkoutLibraryScreen({super.key});

  @override
  State<WorkoutLibraryScreen> createState() => _WorkoutLibraryScreenState();
}

class _WorkoutLibraryScreenState extends State<WorkoutLibraryScreen> {
  final _repo = WorkoutPlanRepository();
  List<WorkoutPlan> _workouts = const [];
  bool _loading = true;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await _repo.fetchWorkouts(_userId);
      if (mounted) {
        setState(() {
          _workouts = w;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final vm = ProgramDetailViewModel();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => PlanWorkoutScreen(viewModel: vm)),
    );
    vm.dispose();
    await _load();
  }

  Future<void> _edit(WorkoutPlan w) async {
    final vm = ProgramDetailViewModel();
    await vm.openStandaloneWorkout(w.workoutId);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => PlanWorkoutScreen(viewModel: vm)),
    );
    vm.dispose();
    await _load();
  }

  Future<void> _archive(WorkoutPlan w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Archive Workout',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Archive "${toProperCase(w.name)}"?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Archive',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) {
      await _repo.archiveWorkout(w.workoutId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Workouts',
            right: GlassButton(
              label: '',
              icon: Icons.add,
              compact: true,
              onPressed: _create,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _workouts.isEmpty
                    ? Center(
                        child: Text('No workouts yet — create one to get started.',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.md, color: AppColors.muted)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _workouts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) {
                          final w = _workouts[i];
                          return AppCard(
                            onTap: () => _edit(w),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(toProperCase(w.name),
                                          style: AppFonts.ui(
                                              fontSize: AppTextStyles.md,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary)),
                                      if (w.notes?.isNotEmpty == true)
                                        Text(w.notes!,
                                            style: AppFonts.ui(
                                                fontSize: AppTextStyles.xs,
                                                color: AppColors.muted),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                GlassButton(
                                  label: '',
                                  icon: Icons.archive_outlined,
                                  color: AppColors.danger,
                                  compact: true,
                                  onPressed: () => _archive(w),
                                ),
                              ],
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
