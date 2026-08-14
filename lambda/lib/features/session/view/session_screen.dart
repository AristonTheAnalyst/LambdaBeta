import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/models/planned_session_set.dart';
import '../../../shared/widgets/exercise_pill_bar.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/reflection_summary.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../model/pr_engine.dart';
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

  /// Wizard step: training → reflection recap.
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
    // Wizard step: end → Prep greets with "Session complete, rest well and
    // see you soon" (rendered from vm.sessionJustCompleted).
    await _vm.endSession();
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
                ListenableBuilder(
                  listenable: _vm.slidePagesController,
                  builder: (context, _) {
                    final page = _vm.slidePagesController.currentPage;
                    // The header IS the wizard nav: title names the step, the
                    // left button steps back (or cancels), the right advances.
                    // Once started, Training's title is the bound template's
                    // name (freestyle keeps the generic title).
                    final title = switch (page) {
                      0 => 'Session Prep',
                      1 => _vm.hasActiveWorkout
                          ? (_vm.selectedPlannedSession?.name ??
                              _vm.selectedStandaloneWorkout?.name ??
                              'Freestyle Session')
                          : 'Training Session',
                      _ => 'Session Reflection',
                    };
                    return PageHeader(
                      title: title,
                      // Active: Cancel on Training; on Reflection 'Back'
                      // resumes training (the reflection back-door).
                      // Idle: 'Back' returns to Prep from Training.
                      left: _vm.hasActiveWorkout
                          ? (page == 2
                              ? GlassButton(
                                  label: 'Back',
                                  color: AppColors.primary,
                                  compact: true,
                                  onPressed: () => _vm
                                      .slidePagesController
                                      .slideToPage(1))
                              : GlassButton(
                                  label: 'Cancel',
                                  color: AppColors.danger,
                                  compact: true,
                                  onPressed: _confirmCancelWorkout))
                          : page != 0
                              ? GlassButton(
                                  label: 'Back',
                                  color: AppColors.primary,
                                  compact: true,
                                  onPressed: () => _vm
                                      .slidePagesController
                                      .slideToPage(0))
                              : null,
                      // Wizard path: START (Prep) → choose workout →
                      // START (Training) → FINISH → reflection → end.
                      right: _vm.hasActiveWorkout
                          ? GlassButton(
                              label: 'Finish',
                              color: AppColors.success,
                              compact: true,
                              onPressed: _goToReflection)
                          : page == 0
                              ? GlassButton(
                                  label: 'Start',
                                  color: AppColors.success,
                                  compact: true,
                                  onPressed: () => _vm
                                      .slidePagesController
                                      .slideToPage(1))
                              : page == 1
                                  ? GlassButton(
                                      label: 'Start',
                                      color: AppColors.success,
                                      compact: true,
                                      onPressed: _vm.startWorkout)
                                  : null,
                    );
                  },
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
                  // Key keeps the SlidePages element stable across rebuilds —
                  // otherwise the PageView is recreated and its page position
                  // resets to Prep.
                  key: const ValueKey('sessionPages'),
                  child: SlidePages(
                    controller: _vm.slidePagesController,
                    // Strict wizard: steps advance via the header buttons and
                    // (unlocked) tabs only — no swipe navigation.
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _PrepPage(vm: _vm, startNotesCtrl: _startNotesCtrl),
                      _TrainingPage(
                          vm: _vm, onRemoveExercise: _confirmRemoveExercise),
                      _ReflectionPage(vm: _vm, notesCtrl: _endNotesCtrl, onEnd: _endFromReflection),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Page 0: Prep ──────────────────────────────────────────────────────────────

class _PrepPage extends StatelessWidget {
  const _PrepPage({required this.vm, required this.startNotesCtrl});

  final SessionViewModel vm;
  final TextEditingController startNotesCtrl;

  @override
  Widget build(BuildContext context) {
    final hasLastSession = vm.latestSession?.parentSessionName != null ||
        vm.latestSession?.feeling != null ||
        vm.latestReflectionExercises.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // The wizard's closing step — shown until the next session starts.
        if (vm.sessionJustCompleted)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.success),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Session complete, rest well and see you soon',
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                ),
              ],
            ),
          ),
        if (hasLastSession) ...[
          Text('LAST SESSION',
              style: AppFonts.mono(
                  fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.sm),
          // The planned session (if any) last session was started from,
          // with the session's date.
          if (vm.latestSession?.parentSessionName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                  '${vm.latestSession!.parentSessionName} · ${DateFormat('MMM d').format(vm.latestSession!.createdDate)}',
                  style: AppFonts.mono(
                      fontSize: 10, letterSpacing: 0.6, color: AppColors.planned)),
            ),
          // How it felt last time (read-only rating of the post-feeling).
          if (vm.latestSession?.feeling != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: FeelingRating(
                  value: vm.latestSession!.feeling,
                  label: 'How it felt last time: ',
                  size: 20, radius: 4, spacing: 4, textSize: 10),
            ),
          if (vm.latestReflectionExercises.isNotEmpty) ...[
            ReflectionSummary(
              exerciseIds: vm.latestReflectionExercises,
              prsByExercise: vm.latestReflectionPrsByExercise,
              lessonsByExercise: vm.latestReflectionLessonsByExercise,
              exerciseNameFor: (id) => vm.latestReflectionExerciseNames[id] ?? '',
              previousFor: vm.previousForLatestReflection,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
        Text('THIS SESSION',
            style: AppFonts.mono(
                fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
        const SizedBox(height: AppSpacing.sm),
        Text('How do you feel about this session?',
            style: TextStyle(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
        const SizedBox(height: AppSpacing.sm),
        FeelingRating(value: vm.sessionFeeling, onChanged: vm.setSessionFeeling),
        const SizedBox(height: AppSpacing.lg),
        LambdaInput(
          controller: startNotesCtrl,
          label: 'Expound on how you feel (optional)',
          placeholder: 'Sleep and eat well?\nHydrated?\nGoals today?',
          onChanged: (v) => vm.startNotes = v,
        ),
      ],
    );
  }
}

/// The session-template selector card on the Training page — planned styling
/// when a template is selected. Only rendered while idle: once the workout
/// starts the card is hidden (the header title carries the session's name).
class _SessionTemplateCard extends StatelessWidget {
  const _SessionTemplateCard({required this.vm, this.onTap});

  final SessionViewModel vm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          // Any selected template — program planned or standalone —
          // gets the planned styling (plannedBg fill + planned outline).
          color: vm.selectedPlannedSession != null ||
                  vm.selectedStandaloneWorkout != null
              ? AppColors.plannedBg
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: vm.selectedPlannedSession != null ||
                      vm.selectedStandaloneWorkout != null
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Freestyle Session',
                            style: AppFonts.ui(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.muted)),
                        const SizedBox(height: 2),
                        Text('No planned session — add exercises as you train',
                            style: AppFonts.mono(
                                fontSize: 9,
                                letterSpacing: 0.6,
                                color: AppColors.muted)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.swap_vert,
                size: 18,
                color: vm.selectedPlannedSession != null ||
                        vm.selectedStandaloneWorkout != null
                    ? AppColors.planned
                    : AppColors.muted),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Training ───────────────────────────────────────────────────────────

class _TrainingPage extends StatelessWidget {
  const _TrainingPage({
    required this.vm,
    required this.onRemoveExercise,
  });

  final SessionViewModel vm;
  final void Function(int index) onRemoveExercise;

  @override
  Widget build(BuildContext context) {
    // The Start Session button lives in the header (top right) while idle;
    // there is no bottom bar on this page.
    return vm.hasActiveWorkout ? _buildActive() : _buildIdle(context);
  }

  /// Idle: template picker + read-only planned-set preview of the selection.
  Widget _buildIdle(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Always shown while idle — with nothing selected it is the freestyle
        // identity card (icon + sub-line), not an empty shell.
        _SessionTemplateCard(vm: vm, onTap: () => _showWorkoutPicker(context, vm)),
        const SizedBox(height: AppSpacing.lg),
        _SessionPreview(vm: vm),
      ],
    );
  }

  /// Active: the PRS/LESSONS stats take the slot the picker held while idle
  /// (same container height), then the exercise pills and card.
  Widget _buildActive() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: SessionStatsBar(vm: vm),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ListenableBuilder(
            listenable: vm,
            builder: (context, _) {
              final labels = <String>[];
              final keys = <String>[];
              for (final slot in vm.exerciseSlots) {
                // Supersets are retired from the frontend (see CLAUDE.md) —
                // any restored superset slot renders as its first exercise.
                labels.add(toProperCase(vm.exerciseDisplayName(slot.exerciseIds.first)));
                keys.add('${slot.id}');
              }
              return ExercisePillBar(
                labels: labels,
                keys: keys,
                activeIndex: vm.activeSlotIndex,
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
                ? _PlaceholderExerciseCard(vm: vm)
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

/// The Training page's pre-start preview, rendered like the live session:
/// exercise pill bar + the exercise card's grid.
///
/// Planned template: read-only planned rows (plannedBg fill + planned
/// outline) with static values — no editing, no reorder/remove/add.
/// Freestyle (no template): a ghosted, non-interactive version — sample
/// pills from recently-used exercises and an empty 3-row set container —
/// so the page still reads like a session without pretending anything is
/// planned.
/// One-screen-only by design (the planner has its own editable set rows), so
/// it lives here rather than in shared/widgets.
class _SessionPreview extends StatefulWidget {
  const _SessionPreview({required this.vm});

  final SessionViewModel vm;

  @override
  State<_SessionPreview> createState() => _SessionPreviewState();
}

class _SessionPreviewState extends State<_SessionPreview> {
  int _selectedIndex = 0;

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final order = vm.plannedExerciseOrder;
    if (order.isEmpty) return _freestylePreview(vm);
    final activeIndex = _selectedIndex.clamp(0, order.length - 1);
    final exerciseId = order[activeIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExercisePillBar(
          labels: [
            for (final id in order) toProperCase(vm.exerciseDisplayName(id))
          ],
          keys: order,
          activeIndex: activeIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          // No onReorder/onRemove/onAdd — the preview is read-only.
        ),
        const SizedBox(height: AppSpacing.sm),
        _previewCard(vm, exerciseId),
      ],
    );
  }

  /// Most-recently-used exercises, newest first — the freestyle "sample" set.
  List<String> _recentExerciseIds(SessionViewModel vm) {
    final entries = vm.lastUsedByExercise.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key].take(6).toList();
  }

  /// Freestyle ghosts: pills + exercise container are inert placeholders —
  /// dimmed, non-clickable, showing what a session will look like.
  Widget _freestylePreview(SessionViewModel vm) {
    final recentIds = _recentExerciseIds(vm);
    return IgnorePointer(
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recentIds.isNotEmpty) ...[
              ExercisePillBar(
                labels: [
                  for (final id in recentIds)
                    toProperCase(vm.exerciseDisplayName(id))
                ],
                keys: recentIds,
                activeIndex: -1, // ghost: no active pill
                onTap: (_) {},
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _freestyleCard(vm, recentIds.isEmpty ? null : recentIds.first),
          ],
        ),
      ),
    );
  }

  /// The ghost exercise container — neutral chrome with 3 empty set rows so
  /// the grid keeps its shape even though nothing is planned.
  Widget _freestyleCard(SessionViewModel vm, String? exerciseId) {
    final name = exerciseId == null
        ? 'Exercise'
        : toProperCase(vm.exerciseDisplayName(exerciseId));
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(name,
                      style: AppFonts.ui(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: exerciseId == null
                              ? AppColors.muted
                              : AppColors.primary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _disabledPill(
                        icon: Icons.menu_book_outlined, label: 'Lessons'),
                    const SizedBox(width: 6),
                    _disabledPill(icon: Icons.history, label: 'History'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same column header row as the live set grid.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 26),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('KG')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('REPS')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('VARIATION')),
                      const SizedBox(width: 6),
                      SizedBox(width: 32, child: _colLabel('NOTE')),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Three empty rows — the container holds its shape.
                for (var i = 0; i < 3; i++) _emptyRow(i + 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One empty (nothing-planned) row in the freestyle ghost grid.
  Widget _emptyRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('$index',
                  style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
            ),
            const SizedBox(width: 6),
            Expanded(child: _valueCell('—', color: AppColors.muted)),
            const SizedBox(width: 6),
            Expanded(child: _valueCell('—', color: AppColors.muted)),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const SizedBox(width: 32),
          ],
        ),
      ),
    );
  }

  /// The exercise card mirror: surface card with the planned outline, the
  /// header (name + PLANNED tag), and the live grid's column layout filled
  /// with static planned values.
  Widget _previewCard(SessionViewModel vm, String exerciseId) {
    final sets = (vm.plannedSetsByExercise[exerciseId] ?? const [])
        .where((s) => !s.isArchived)
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.planned.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(toProperCase(vm.exerciseDisplayName(exerciseId)),
                      style: AppFonts.ui(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.planned.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.planned.withValues(alpha: 0.3)),
                  ),
                  child: Text('PLANNED',
                      style: AppFonts.mono(
                          fontSize: 11, letterSpacing: 0.4, color: AppColors.planned)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same column header row as the live set grid.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 26),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('KG')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('REPS')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('VARIATION')),
                      const SizedBox(width: 6),
                      SizedBox(width: 32, child: _colLabel('NOTE')),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (sets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('No planned sets',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: AppTextStyles.sm)),
                  ),
                for (var i = 0; i < sets.length; i++)
                  _previewRow(i + 1, sets[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(text,
      textAlign: TextAlign.center,
      style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));

  /// One planned set as a static row — the live session's planned-row look
  /// (plannedBg fill + planned outline) without any edit affordances.
  Widget _previewRow(int index, PlannedSessionSet set) {
    final weight = set.targetWeight;
    final reps = set.targetReps;
    final variation = set.variationName;
    final hasNotes = set.targetNotes != null && set.targetNotes!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.plannedBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: AppColors.planned.withValues(alpha: 0.35), width: 0.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('$index',
                  style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
            ),
            const SizedBox(width: 6),
            Expanded(
                child: _valueCell(
                    weight != null ? '${_fmt(weight)}kg' : '—')),
            const SizedBox(width: 6),
            Expanded(
                child: _valueCell(
                    reps.isEmpty ? '—' : reps.map(_fmt).join(' / '))),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: variation != null
                    ? Text(toProperCase(variation),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.mono(
                            fontSize: 10, color: AppColors.planned))
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 32,
              child: hasNotes
                  ? Icon(Icons.sticky_note_2_outlined,
                      size: 16, color: AppColors.planned)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueCell(String text, {Color? color}) {
    return SizedBox(
      height: 34,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Text(text,
            style: AppFonts.mono(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color ?? AppColors.planned)),
      ),
    );
  }
}


/// The training page's exercise-card placeholder shown before the first
/// exercise is added — the same card chrome (name, Lessons/History pills,
/// set-grid column labels) so the page never reads as completely empty.
/// The "+ ADD EXERCISE" row opens the add-exercise modal.
class _PlaceholderExerciseCard extends StatelessWidget {
  const _PlaceholderExerciseCard({required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text('Exercise',
                      style: AppFonts.ui(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _disabledPill(
                        icon: Icons.menu_book_outlined, label: 'Lessons'),
                    const SizedBox(width: 6),
                    _disabledPill(icon: Icons.history, label: 'History'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same column header row as the live set grid.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 26),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('KG')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('REPS')),
                      const SizedBox(width: 6),
                      Expanded(child: _colLabel('VARIATION')),
                      const SizedBox(width: 6),
                      SizedBox(width: 32, child: _colLabel('NOTE')),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => showAddExerciseModal(context, vm: vm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: AppColors.border, style: BorderStyle.solid),
                    ),
                    child: Center(
                      child: Text('+ ADD EXERCISE',
                          style: AppFonts.ui(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.muted)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(text,
      textAlign: TextAlign.center,
      style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));
}

/// The lessons/history pill chrome in its disabled state — used by the
/// active-session placeholder card and the freestyle ghost preview, where
/// the pills can't act on an exercise that isn't part of a session yet.
Widget _disabledPill({required IconData icon, required String label}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.muted.withValues(alpha: 0.4)),
        const SizedBox(width: 5),
        Text(label,
            style: AppFonts.mono(
                fontSize: 11,
                letterSpacing: 0.4,
                color: AppColors.muted.withValues(alpha: 0.4))),
      ],
    ),
  );
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

  /// PR showcase + lessons for this session, via the shared
  /// [ReflectionSummary] (same styling as the prep page's latest-session
  /// preview — one implementation).
  Widget _buildSummary() {
    final ids = [for (final slot in vm.exerciseSlots) ...slot.exerciseIds];
    final prs = vm.prsThisSession;
    return ReflectionSummary(
      exerciseIds: ids,
      prsByExercise: {
        for (final id in ids)
          id: prs.where((p) => p.exerciseId == id).toList(),
      },
      lessonsByExercise: {
        for (final id in ids)
          id: [for (final l in vm.lessonsFor(id)) l.text],
      },
      exerciseNameFor: (id) => vm.exerciseDisplayName(id),
      previousFor: (p) => p.type == PrType.repMax
          ? vm.previousRepMax(p.exerciseId, p.variationId,
              p.targetReps ?? p.reps.toInt())
          : vm.previousWeightMax(p.exerciseId, p.variationId,
              p.targetWeight ?? p.weight),
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
                if (!vm.hasActiveWorkout)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(
                      child: Text('Nothing to reflect on yet — finish a session here.',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: AppTextStyles.sm)),
                    ),
                  )
                else if (vm.sets.isNotEmpty)
                  _buildSummary(),
              ],
            ),
          ),
          if (vm.hasActiveWorkout)
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
                  FeelingRating(value: vm.endFeeling, onChanged: vm.setEndFeeling),
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
