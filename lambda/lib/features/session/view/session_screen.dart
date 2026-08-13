import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../shared/widgets/exercise_pill_bar.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../model/pr_engine.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';
import 'exercise_card.dart';
import 'session_stats_bar.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static SessionViewModel? _cachedVm;

  static void _clearCachedVm() => _cachedVm = null;

  /// Releases the cached ViewModel on sign-out — the local DB is being
  /// cleared, so the next sign-in must build fresh.
  static void _resetCachedVmOnSignOut() {
    final vm = _cachedVm;
    _cachedVm = null;
    vm?.dispose();
  }

  late final SessionViewModel _vm;

  final _startNotesCtrl = TextEditingController();
  final _endNotesCtrl = TextEditingController();
  bool _showCompleteBanner = false;

  @override
  void initState() {
    super.initState();
    ps.onSignOutReset = _resetCachedVmOnSignOut;
    if (_cachedVm != null) {
      // Reuse across hot reload — workout state stays intact
      _vm = _cachedVm!;
      // Returning to the tab: refresh the current program / planned workout so
      // a newly created or begun program shows without a full restart.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _vm.refreshCatalog(); // always refresh exercise/variation catalog
          _vm.refreshProgram();
          // If the workout ended while we were on another tab, the cached VM
          // still points at page 1 with no active sessionId — reset to the
          // start page so the user isn't stuck staring at an empty card.
          if (!_vm.hasActiveWorkout && _vm.slidePagesController.currentPage > 0) {
            _vm.slidePagesController.resetToPage(0);
          }
        }
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
    if (ps.onSignOutReset == _resetCachedVmOnSignOut) {
      ps.onSignOutReset = null;
    }
    _vm.removeListener(_onVmChanged);
    _startNotesCtrl.dispose();
    _endNotesCtrl.dispose();
    super.dispose();
  }

  // ── Modals ─────────────────────────────────────────────────────────────────

  void _goToReflection() {
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    _vm.slidePagesController.slideToPage(2);
  }

  Future<void> _endFromReflection() async {
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    await _vm.endSession();
    if (!mounted) return;
    // Transient "Workout Complete" toast that fades back out.
    setState(() => _showCompleteBanner = true);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _showCompleteBanner = false);
    });
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
              child: Text('Got It', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _confirmRemoveExercise(int index) {
    final slot = _vm.exerciseSlots[index];
    // Get the display name for the first exercise in the slot
    final exerciseId = slot.activeExerciseId;
    final name = toProperCase(_vm.exerciseDisplayName(exerciseId));
    final setCount = _vm.sets.where((s) => slot.exerciseIds.contains(s.exerciseId)).length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove Exercise', style: TextStyle(color: AppColors.danger)),
        content: Text(
            'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Keep', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.removeExerciseSlot(index);
              },
              child: Text('Remove',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _confirmCancelWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cancel Session', style: TextStyle(color: AppColors.danger)),
        content: Text('Discard this workout and all logged sets?', style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Keep Going', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.cancelSession();
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
      body: Stack(
        children: [
          _vm.initLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                PageHeader(
                  title: _vm.hasActiveWorkout ? 'Training Session' : 'Mental Prep and Planning',
                  left: _vm.hasActiveWorkout
                      ? GlassButton(label: 'Cancel', color: AppColors.danger, compact: true, onPressed: _confirmCancelWorkout)
                      : null,
                  right: _vm.hasActiveWorkout
                      ? GlassButton(label: 'Finish', color: AppColors.success, compact: true, onPressed: _goToReflection)
                      : null,
                ),
                if (_vm.hasActiveWorkout)
                  _SessionTabs(controller: _vm.slidePagesController),
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
                  // Key keeps this element stable when _SessionTabs is
                  // inserted above on workout start — otherwise the PageView
                  // is recreated and its page position resets to Prep.
                  key: const ValueKey('sessionPages'),
                  child: SlidePages(
                    controller: _vm.slidePagesController,
                    children: [
                      _StartPage(vm: _vm, startNotesCtrl: _startNotesCtrl),
                      _ActivePage(vm: _vm, onRemoveExercise: _confirmRemoveExercise),
                      _ReflectionPage(vm: _vm, notesCtrl: _endNotesCtrl, onEnd: _endFromReflection),
                    ],
                  ),
                ),
                if (_vm.hasActiveWorkout)
                  ListenableBuilder(
                    listenable: _vm.slidePagesController,
                    builder: (context, _) =>
                        _vm.slidePagesController.currentPage == 1
                            ? Padding(
                                padding: EdgeInsets.fromLTRB(
                                    AppSpacing.lg, 0, AppSpacing.lg,
                                    MediaQuery.of(context).padding.bottom +
                                        AppSpacing.lg),
                                child: SessionStatsBar(vm: _vm),
                              )
                            : const SizedBox.shrink(),
                  ),
              ],
            ),
          if (_showCompleteBanner)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showCompleteBanner ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text('Workout Complete',
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                    ),
                  ),
                ),
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
              if (vm.availableWorkouts.isNotEmpty ||
                  vm.standaloneWorkouts.isNotEmpty ||
                  vm.selectedPlannedSession != null ||
                  vm.selectedStandaloneWorkout != null) ...[
                GestureDetector(
                  onTap: () => _showWorkoutPicker(context, vm),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: vm.selectedPlannedSession != null
                          ? AppColors.plannedBg
                          : vm.selectedStandaloneWorkout != null
                              ? AppColors.accentBg
                              : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: vm.selectedPlannedSession != null
                              ? AppColors.planned.withValues(alpha: 0.3)
                              : vm.selectedStandaloneWorkout != null
                                  ? AppColors.planned.withValues(alpha: 0.3)
                                  : AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (vm.selectedPlannedSession != null) ...[
                                Text('Week ${vm.programProgress!.weekNumber} · ${vm.programProgress!.program.name}',
                                    style: AppFonts.mono(fontSize: 9, letterSpacing: 0.6, color: AppColors.planned)),
                                const SizedBox(height: 2),
                                Text(vm.selectedPlannedSession!.name,
                                    style: AppFonts.ui(
                                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ] else if (vm.selectedStandaloneWorkout != null) ...[
                                Text('Standalone session',
                                    style: AppFonts.mono(fontSize: 9, letterSpacing: 0.6, color: AppColors.planned)),
                                const SizedBox(height: 2),
                                Text(vm.selectedStandaloneWorkout!.name,
                                    style: AppFonts.ui(
                                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ] else ...[
                                Text('Session template',
                                    style: AppFonts.mono(fontSize: 9, letterSpacing: 0.6, color: AppColors.muted)),
                                const SizedBox(height: 2),
                                Text('No planned session',
                                    style: AppFonts.ui(
                                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.muted)),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.swap_vert, size: 18,
                            color: vm.selectedPlannedSession != null
                                ? AppColors.planned
                                : vm.selectedStandaloneWorkout != null
                                    ? AppColors.planned
                                    : AppColors.muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, bottomInset + AppSpacing.lg),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How do you expect to perform?',
                  style: TextStyle(fontSize: AppTextStyles.sm, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                        color: selected ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                      ),
                      child: Center(
                        child: Text('$n',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: selected ? AppColors.bg : AppColors.primary)),
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
              const SizedBox(height: AppSpacing.lg),
              LambdaButton(
                label: 'Start Session',
                onPressed: vm.startWorkout,
                loading: vm.startLoading,
                disabled: vm.startLoading,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Lets the user pick which session template to log — a standalone
  /// template, a program planned session, or none (free-form).
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
              child: Text('Select session',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            InkWell(
              onTap: () {
                vm.clearTemplateSelection();
                Navigator.of(ctx).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                color: vm.selectedPlannedSession == null &&
                        vm.selectedStandaloneWorkout == null
                    ? AppColors.accentBg
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(Icons.edit_off_outlined,
                        size: 18, color: AppColors.muted),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('No planned session',
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.md,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                    if (vm.selectedPlannedSession == null &&
                        vm.selectedStandaloneWorkout == null)
                      Icon(Icons.check, size: 18, color: AppColors.primary),
                  ],
                ),
              ),
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
                    color: w.sessionId == vm.selectedStandaloneWorkout?.sessionId
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
                        if (w.sessionId == vm.selectedStandaloneWorkout?.sessionId)
                          Icon(Icons.check, size: 18, color: AppColors.primary),
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
                    vm.selectPlannedSession(w);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    color: w.sessionId == vm.selectedPlannedSession?.sessionId
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
                        if (w.sessionId == vm.selectedPlannedSession?.sessionId)
                          Icon(Icons.check, size: 18, color: AppColors.primary),
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
  const _ActivePage({required this.vm, required this.onRemoveExercise});

  final SessionViewModel vm;
  final void Function(int index) onRemoveExercise;

  @override
  Widget build(BuildContext context) {
    final plannedWorkout = vm.programProgress?.nextPlannedSession;
    final subtitle = plannedWorkout != null
        ? 'Week ${vm.programProgress!.weekNumber} · ${plannedWorkout.name}'
        : 'Freestyle Session';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Center(
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: AppFonts.mono(fontSize: 10, letterSpacing: 0.6, color: AppColors.muted)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ListenableBuilder(
            listenable: vm,
            builder: (context, _) {
              var supersetCount = 0;
              final labels = <String>[];
              final keys = <String>[];
              final prefixIcons = <IconData?>[];
              for (final slot in vm.exerciseSlots) {
                if (slot.type == SessionSlotType.superset) {
                  supersetCount++;
                  labels.add('Superset $supersetCount');
                  prefixIcons.add(Icons.hexagon_outlined);
                } else {
                  labels.add(toProperCase(vm.exerciseDisplayName(slot.exerciseIds.first)));
                  prefixIcons.add(null);
                }
                keys.add('${slot.id}');
              }
              return ExercisePillBar(
                labels: labels,
                keys: keys,
                activeIndex: vm.activeSlotIndex,
                prefixIcons: prefixIcons,
                onTap: (i) => vm.tapTab(i),
                onReorder: (oldIndex, newIndex) =>
                    vm.reorderExercises(oldIndex, newIndex),
                onRemove: onRemoveExercise,
                onAdd: () => showAddExerciseModal(context, vm: vm),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: vm.activeSlot == null
                ? _EmptySlotsHint(vm: vm)
                // Key per exercise slot: switching tabs recreates the card
                // state so an open history view doesn't carry over.
                : ExerciseCard(
                    key: ValueKey(vm.activeSlot!.id),
                    vm: vm,
                    slot: vm.activeSlot!,
                  ),
          ),
        ),
      ],
    );
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



// ── Session flow tabs (Prep / Training / Reflection) ─────────────────────────

class _SessionTabs extends StatelessWidget {
  const _SessionTabs({required this.controller});

  final SlidePagesController controller;

  static const _tabs = ['Prep', 'Training', 'Reflection'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.slideToPage(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: controller.currentPage == i
                              ? AppColors.primary
                              : AppColors.border,
                          width: controller.currentPage == i ? 2 : 1,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _tabs[i],
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: controller.currentPage == i
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: controller.currentPage == i
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              if (i < _tabs.length - 1) const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Page 2: Reflection ───────────────────────────────────────────────────────

class _ReflectionPage extends StatelessWidget {
  const _ReflectionPage({
    required this.vm,
    required this.notesCtrl,
    required this.onEnd,
  });

  final SessionViewModel vm;
  final TextEditingController notesCtrl;
  final Future<void> Function() onEnd;

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  /// PR showcase — the axes beaten this session per exercise × variation.
  /// When a single set improved both the rep-max and the weight-max axes,
  /// only the RM record is shown (dedup); weight-max appears alone only for
  /// volume PRs. Lessons are listed under each exercise in the same format
  /// as the lessons modal, with an open-book marker.
  List<Widget> _summarySections() {
    final sections = <Widget>[];
    final prs = vm.prsThisSession;

    // Collect the exercises that have content first so a bottom divider can
    // be added to every section except the last (the sticky bottom bar's
    // top border already divides the last one).
    final contentExercises = <String>[];
    for (final slot in vm.exerciseSlots) {
      for (final exerciseId in slot.exerciseIds) {
        final exPrs = prs.where((p) => p.exerciseId == exerciseId).toList();
        final lessons = vm.lessonsFor(exerciseId);
        if (exPrs.isNotEmpty || lessons.isNotEmpty) {
          contentExercises.add(exerciseId);
        }
      }
    }

    var sectionIndex = 0;
    for (final slot in vm.exerciseSlots) {
      for (final exerciseId in slot.exerciseIds) {
        if (!contentExercises.contains(exerciseId)) continue;
        final isLast = sectionIndex == contentExercises.length - 1;
        sectionIndex++;
        final exerciseName =
            toProperCase(vm.exerciseDisplayName(exerciseId));
        final exPrs = prs.where((p) => p.exerciseId == exerciseId).toList();
        final lessons = vm.lessonsFor(exerciseId);

        sections.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
          child: Text(exerciseName,
              style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        ));

        // Group by source set; a set that fired both axes shows its RM only.
        final bySet = <String?, List<PrRecord>>{};
        for (final p in exPrs) {
          bySet.putIfAbsent(p.setId, () => []).add(p);
        }
        for (final group in bySet.values) {
          final rm = group.where((p) => p.type == PrType.repMax).firstOrNull;
          final wm = group.where((p) => p.type == PrType.weightMax).firstOrNull;
          if (rm != null && wm != null) {
            // Both axes fired: prefer the one with a meaningful "before"
            // (5kg x 9 after 5kg x 7 reads as a weight-max progression,
            // not another first RM). Both or neither -> RM.
            final rmHasPrev = _previousFor(rm) != null;
            final wmHasPrev = _previousFor(wm) != null;
            sections.add(rmHasPrev || !wmHasPrev ? _prCard(rm) : _prCard(wm));
          } else if (rm != null) {
            sections.add(_prCard(rm));
          } else if (wm != null) {
            sections.add(_prCard(wm));
          }
        }

        if (lessons.isNotEmpty) {
          for (final lesson in lessons) {
            sections.add(Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(lesson.text,
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ));
          }
        }
        if (!isLast) {
          sections.add(Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Divider(color: AppColors.border, height: 1),
          ));
        }
      }
    }
    return sections;
  }

  /// The record this PR beat on its axis — history OR an earlier set in
  /// the same session.
  PrRecord? _previousFor(PrRecord p) {
    if (p.type == PrType.repMax) {
      return vm.previousRepMax(
          p.exerciseId, p.variationId, p.targetReps ?? p.reps.toInt());
    }
    return vm.previousWeightMax(
        p.exerciseId, p.variationId, p.targetWeight ?? p.weight);
  }

  /// One PR row: the axis beaten this session with its before/after.
  /// rep-max: "5RM: 100kg → 105kg"; weight-max: "100kg: 3 → 5 reps".
  /// PR-set style: accentBg fill with the accent outline.
  Widget _prCard(PrRecord p) {
    final String? before;
    final String after;
    final String axisLabel;
    if (p.type == PrType.repMax) {
      final prev = _previousFor(p);
      before = prev != null ? '${_fmt(prev.weight)}kg' : null;
      after = '${_fmt(p.weight)}kg';
      axisLabel = '${p.targetReps ?? ''}RM';
    } else {
      final prev = _previousFor(p);
      before = prev != null ? '${_fmt(prev.reps)} reps' : null;
      after = '${_fmt(p.reps)} reps';
      axisLabel = '${_fmt(p.targetWeight ?? p.weight)}kg';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.variationName != null)
                  Text(toProperCase(p.variationName!),
                      style: AppFonts.mono(
                          fontSize: 9,
                          letterSpacing: 0.6,
                          color: AppColors.accent)),
                Text(before != null
                    ? '$axisLabel: $before  →  $after'
                    : '$axisLabel: $after (First PR)',
                    style: AppFonts.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (vm.sets.isNotEmpty) ..._summarySections(),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
                bottomInset + AppSpacing.lg),
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border, width: 0.5))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('How did it feel?',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                          color: selected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: selected ? AppColors.primary : AppColors.border),
                        ),
                        child: Center(
                          child: Text('$n',
                              style: AppFonts.ui(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppColors.bg
                                      : AppColors.primary)),
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
                LambdaButton(
                  variant: ButtonVariant.success,
                  label: 'End Session',
                  onPressed: onEnd,
                  loading: vm.endLoading,
                  disabled: vm.endLoading,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
