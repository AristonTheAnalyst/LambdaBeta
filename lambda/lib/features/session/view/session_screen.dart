import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/workout_format.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';
import 'exercise_card.dart';
import 'exercise_tab_bar.dart';
import 'rest_timer_bar.dart';
import 'session_stats_bar.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static SessionViewModel? _cachedVm;

  static void _clearCachedVm() => _cachedVm = null;

  late final SessionViewModel _vm;

  final _startNotesCtrl = TextEditingController();
  final _endNotesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_cachedVm != null) {
      // Reuse across hot reload — workout state stays intact
      _vm = _cachedVm!;
      // Returning to the tab: refresh the current program / planned workout so
      // a newly created or begun program shows without a full restart.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _vm.refreshProgram();
      });
    } else {
      _vm = SessionViewModel();
      _cachedVm = _vm;
      _vm.onWorkoutEnded = _clearCachedVm;
    }
    _vm.addListener(_onVmChanged);
  }

  void _onVmChanged() {
    // The cached VM outlives this State (hot reload / navigation), so guard
    // every notification with mounted — otherwise a VM event after dispose
    // throws "setState() called after dispose()".
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _startNotesCtrl.dispose();
    _endNotesCtrl.dispose();
    super.dispose();
  }

  // ── Modals ─────────────────────────────────────────────────────────────────

  void _openEndWorkoutModal() {
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    _endNotesCtrl.clear();
    _vm.endNotes = '';
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EndWorkoutModal(vm: _vm, notesCtrl: _endNotesCtrl),
    );
  }

  void _showNoSetsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('No Sets Logged', style: TextStyle(color: AppColors.primary)),
        content: Text(
            "You haven't logged any sets yet. Log at least one set before ending, or cancel the workout instead.",
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Got It', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _confirmCancelWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cancel Workout', style: TextStyle(color: AppColors.danger)),
        content: Text('Discard this workout and all logged sets?', style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Keep Going', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.cancelWorkout();
              },
              child: Text('Discard',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _vm.initLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                PageHeader(
                  title: _vm.hasActiveWorkout ? 'Training Session' : 'Mental Prep and Planning',
                  left: _vm.hasActiveWorkout
                      ? GlassButton(label: 'Cancel', color: AppColors.danger, compact: true, onPressed: _confirmCancelWorkout)
                      : null,
                ),
                if (_vm.error != null)
                  GestureDetector(
                    onTap: _vm.clearError,
                    child: Container(
                      width: double.infinity,
                      color: AppColors.dangerBg,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      child: Text(_vm.error!, style: TextStyle(color: AppColors.danger, fontSize: AppTextStyles.sm)),
                    ),
                  ),
                Expanded(
                  child: SlidePages(
                    controller: _vm.slidePagesController,
                    children: [
                      _StartPage(vm: _vm, startNotesCtrl: _startNotesCtrl),
                      _ActivePage(vm: _vm, onFinishWorkout: _openEndWorkoutModal),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Page 0: Start ──────────────────────────────────────────────────────────────

class _StartPage extends StatelessWidget {
  const _StartPage({required this.vm, required this.startNotesCtrl});

  final SessionViewModel vm;
  final TextEditingController startNotesCtrl;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (vm.exercises.isEmpty && !vm.catalogLoading)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Text('No exercises set up yet',
                          style: TextStyle(
                              fontSize: AppTextStyles.md, fontWeight: FontWeight.w600, color: AppColors.primary),
                          textAlign: TextAlign.center),
                      SizedBox(height: AppSpacing.sm),
                      Text('Go to Exercises → Library to create your first exercise before logging a workout.',
                          style: TextStyle(fontSize: AppTextStyles.sm, color: AppColors.muted),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              if (vm.exercises.isNotEmpty) ...[
                if (vm.selectedPlannedWorkout != null) ...[
                  GestureDetector(
                    onTap: vm.availableWorkouts.length > 1
                        ? () => _showWorkoutPicker(context, vm)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Week ${vm.programProgress!.weekNumber} · ${vm.programProgress!.program.name}',
                                    style: AppFonts.mono(fontSize: 9, letterSpacing: 0.6, color: AppColors.success)),
                                const SizedBox(height: 2),
                                Text(vm.selectedPlannedWorkout!.name,
                                    style: AppFonts.ui(
                                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ],
                            ),
                          ),
                          if (vm.availableWorkouts.length > 1)
                            Icon(Icons.swap_vert, size: 18, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text('How do you expect to perform?',
                    style: TextStyle(fontSize: AppTextStyles.sm, fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(5, (i) {
                    final n = i + 1;
                    final selected = vm.sessionFeeling == n;
                    return GestureDetector(
                      onTap: () => vm.setSessionFeeling(n),
                      child: Container(
                        width: 52,
                        height: 52,
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.accent : AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
                        ),
                        child: Center(
                          child: Text('$n',
                              style: TextStyle(
                                  fontSize: AppTextStyles.lg,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? AppColors.accentText : AppColors.primary)),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                LambdaInput(
                  controller: startNotesCtrl,
                  label: 'Pre-workout notes (optional)',
                  placeholder: 'Sleep and eat well?\nHydrated?\nGoals today?',
                  onChanged: (v) => vm.startNotes = v,
                ),
              ],
            ],
          ),
        ),
        if (vm.exercises.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, bottomInset + AppSpacing.lg),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
            child: LambdaButton(
              label: 'Start Workout',
              onPressed: vm.startWorkout,
              loading: vm.startLoading,
              disabled: vm.startLoading,
            ),
          ),
      ],
    );
  }

  /// Lets the user pick which planned workout to log instead of the auto-next.
  Future<void> _showWorkoutPicker(BuildContext context, SessionViewModel vm) async {
    await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Select workout',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            if (vm.standaloneWorkouts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
                child: Text('Workouts',
                    style: AppFonts.mono(
                        fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
              ),
              for (final w in vm.standaloneWorkouts)
                InkWell(
                  onTap: () {
                    vm.selectStandaloneWorkout(w);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    color: w.workoutId == vm.selectedStandaloneWorkout?.workoutId
                        ? AppColors.accentBg
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(toProperCase(w.name),
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                        if (w.workoutId == vm.selectedStandaloneWorkout?.workoutId)
                          Icon(Icons.check, size: 18, color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (vm.availableWorkouts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
                child: Text('Program',
                    style: AppFonts.mono(
                        fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
              ),
              for (final w in vm.availableWorkouts)
                InkWell(
                  onTap: () {
                    vm.selectPlannedWorkout(w);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    color: w.plannedWorkoutId == vm.selectedPlannedWorkout?.plannedWorkoutId
                        ? AppColors.accentBg
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(toProperCase(w.name),
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                        if (w.plannedWorkoutId == vm.selectedPlannedWorkout?.plannedWorkoutId)
                          Icon(Icons.check, size: 18, color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Active workout ─────────────────────────────────────────────────────

class _ActivePage extends StatelessWidget {
  const _ActivePage({required this.vm, required this.onFinishWorkout});

  final SessionViewModel vm;
  final VoidCallback onFinishWorkout;

  String _elapsedLabel() {
    final started = vm.workoutStartedAt;
    if (started == null) return '0:00';
    final elapsed = DateTime.now().difference(started);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final plannedWorkout = vm.programProgress?.nextPlannedWorkout;
    final subtitle = plannedWorkout != null
        ? 'Week ${vm.programProgress!.weekNumber} · ${plannedWorkout.name}'
        : 'Freestyle Workout';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(subtitle,
                    style: AppFonts.mono(fontSize: 10, letterSpacing: 0.6, color: AppColors.muted)),
              ),
              _ElapsedTimer(label: _elapsedLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SessionStatsBar(vm: vm),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ExerciseTabBar(vm: vm),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: vm.activeSlot == null
                ? _EmptySlotsHint(vm: vm)
                : ExerciseCard(vm: vm, slot: vm.activeSlot!),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
              MediaQuery.of(context).padding.bottom + AppSpacing.sm),
          child: RestTimerBar(vm: vm, onFinish: onFinishWorkout),
        ),
      ],
    );
  }
}

class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer({required this.label});

  final String Function() label;

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {});
        _tick();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.label(),
        style: AppFonts.mono(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.accent));
  }
}

class _EmptySlotsHint extends StatelessWidget {
  const _EmptySlotsHint({required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Text('Tap + above to add your first exercise.',
            style: TextStyle(color: AppColors.muted, fontSize: AppTextStyles.sm)),
      ),
    );
  }
}

// ── End Workout Modal ──────────────────────────────────────────────────────────

class _EndWorkoutModal extends StatelessWidget {
  const _EndWorkoutModal({required this.vm, required this.notesCtrl});

  final SessionViewModel vm;
  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('End Workout',
                  style: TextStyle(fontSize: AppTextStyles.lg, fontWeight: FontWeight.w700, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.md),
              Text('How did it feel?',
                  style: TextStyle(fontSize: AppTextStyles.sm, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: List.generate(5, (i) {
                  final n = i + 1;
                  final selected = vm.endFeeling == n;
                  return GestureDetector(
                    onTap: () => vm.setEndFeeling(n),
                    child: Container(
                      width: 52,
                      height: 52,
                      margin: const EdgeInsets.only(right: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? AppColors.accent : AppColors.border),
                      ),
                      child: Center(
                        child: Text('$n',
                            style: TextStyle(
                                fontSize: AppTextStyles.lg,
                                fontWeight: FontWeight.w700,
                                color: selected ? AppColors.accentText : AppColors.primary)),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              LambdaInput(
                controller: notesCtrl,
                label: 'Post-workout notes (optional)',
                placeholder: 'Notes…',
                onChanged: (v) => vm.endNotes = v,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: GlassButton(
                      label: 'End Workout',
                      compact: true,
                      loading: vm.endLoading,
                      disabled: vm.endLoading,
                      onPressed: () async {
                        Navigator.of(context, rootNavigator: true).pop();
                        await vm.endWorkout();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
