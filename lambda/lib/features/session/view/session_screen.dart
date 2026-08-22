import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/models/planned_session_set.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_set.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/exercise_pill_bar.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/press_squash.dart';
import '../../../shared/widgets/reflection_summary.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';
import 'live_exercise_card.dart';
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
      // Tab re-entry recreates this State (and its PageView); a freshly
      // attached PageView always starts at page 0, silently dumping the user
      // back on Prep — whose header has no Back button. Re-anchor the pager
      // at the wizard step they left, before the new PageView attaches.
      _vm.slidePagesController.restorePageView();
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

  /// Wizard step: training → reflection recap. Shows THIS SESSION first.
  void _goToReflection() {
    // Blur any focused set cell first — its typed value commits on focus
    // loss, and navigating away must not swallow it.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    _vm.showCurrentReflection();
    _vm.slidePagesController.slideToPage(2);
  }

  Future<void> _endFromReflection() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    // Wizard step: end → Prep greets with "Session complete, rest well and
    // see you soon" (rendered from vm.sessionJustCompleted).
    await _vm.endSession();
    // The VM resets endNotes but the controller would keep the old text —
    // clear it so the next workout's post-notes field starts empty.
    _endNotesCtrl.clear();
  }

  void _showNoSetsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'No Sets Logged',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Text(
          "You haven't logged any sets yet. Log at least one set before ending, or cancel the workout instead.",
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Got It',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveExercise(int index) {
    final slot = _vm.exerciseSlots[index];
    // Get the display name for the first exercise in the slot
    final exerciseId = slot.activeExerciseId;
    final name = toProperCase(_vm.exerciseDisplayName(exerciseId));
    final setCount = _vm.sets
        .where((s) => slot.exerciseIds.contains(s.exerciseId))
        .length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Exercise',
          style: TextStyle(color: AppColors.danger),
        ),
        content: Text(
          'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Keep', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vm.removeExerciseSlot(index);
            },
            child: Text(
              'Remove',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancelWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Cancel Session',
          style: TextStyle(color: AppColors.danger),
        ),
        content: Text(
          'Discard this workout and all logged sets?',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Keep Going', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vm.cancelSession();
            },
            child: Text(
              'Discard',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
                          1 =>
                            _vm.hasActiveWorkout
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
                                            .slideToPage(1),
                                      )
                                    : GlassButton(
                                        label: 'Cancel',
                                        color: AppColors.danger,
                                        compact: true,
                                        onPressed: _confirmCancelWorkout,
                                      ))
                              : page != 0
                              ? GlassButton(
                                  label: 'Back',
                                  color: AppColors.primary,
                                  compact: true,
                                  onPressed: () {
                                    // Prep always shows the latest completed
                                    // session — a THIS SESSION position from
                                    // the reflection page can't leak onto it.
                                    _vm.showLatestReflection();
                                    _vm.slidePagesController.slideToPage(0);
                                  },
                                )
                              : null,
                          // Wizard path: START (Prep) → choose workout →
                          // START (Training) → FINISH → reflection → END.
                          // On Reflection the button itself ends the session.
                          right: _vm.hasActiveWorkout
                              ? GlassButton(
                                  label: page == 2 ? 'End' : 'Finish',
                                  color: AppColors.success,
                                  compact: true,
                                  onPressed: page == 2
                                      ? _endFromReflection
                                      : _goToReflection,
                                )
                              : page == 0
                              ? GlassButton(
                                  label: 'Start',
                                  color: AppColors.success,
                                  compact: true,
                                  onPressed: () =>
                                      _vm.slidePagesController.slideToPage(1),
                                )
                              : page == 1
                              ? GlassButton(
                                  label: 'Start',
                                  color: AppColors.success,
                                  compact: true,
                                  onPressed: _vm.startWorkout,
                                )
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            _vm.error!,
                            style: TextStyle(
                              color: AppColors.danger,
                              fontSize: AppTextStyles.sm,
                            ),
                          ),
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
                            vm: _vm,
                            onRemoveExercise: _confirmRemoveExercise,
                          ),
                          _ReflectionPage(vm: _vm, notesCtrl: _endNotesCtrl),
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
    // Any completed history shows the card — sessions without planned names,
    // feelings, PRs or lessons still appear, with explicit empty states.
    final hasLastSession = vm.reflectionSession != null;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // The wizard's closing step — shown until the next session starts.
        if (vm.sessionJustCompleted)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.success),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Session complete, rest well and see you soon',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _FeelingForm(
          rating: vm.sessionFeeling,
          onRatingChanged: vm.setSessionFeeling,
          notesCtrl: startNotesCtrl,
          onNotesChanged: (v) => vm.startNotes = v,
          placeholder: 'Sleep and eat well?\nHydrated?\nGoals today?',
          question: 'How well do you think you\'re going to do',
          notesLabel: 'Why do you feel that way',
        ),
        // The previous-session viewer sits below this session's prep so the
        // current-session inputs come first.
        if (hasLastSession) ...[
          const SizedBox(height: AppSpacing.xl),
          _SectionDivider('PREVIOUS SESSION'),
          const SizedBox(height: AppSpacing.sm),
          _LastSessionCard(vm: vm),
        ],
      ],
    );
  }
}

// ── Shared prep/reflection pieces (two pages of ONE screen, so these stay
// file-level private rather than in shared/widgets — that folder is for
// components spanning the three screens) ──────────────────────────────────

/// Centered section label with a hairline rule on both sides — the
/// PREVIOUS SESSION / THIS SESSION dividers. Larger and primary-toned,
/// unlike the muted mono micro-labels, so the section reads as a headline.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Container(height: 1, color: AppColors.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Text(
          text,
          style: AppFonts.mono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.primary,
          ),
        ),
      ),
      Expanded(child: Container(height: 1, color: AppColors.border)),
    ],
  );
}

/// The questionnaire form — rating question, rating, notes question + input.
/// The exact prep-page block; the reflection page reuses it for POST-WORKOUT
/// so the two pages can never drift apart. Pre and post pass their own
/// [question]/[notesLabel] copy.
class _FeelingForm extends StatelessWidget {
  const _FeelingForm({
    required this.rating,
    required this.onRatingChanged,
    required this.notesCtrl,
    required this.onNotesChanged,
    required this.placeholder,
    required this.question,
    required this.notesLabel,
  });

  final int? rating;
  final ValueChanged<int?> onRatingChanged;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onNotesChanged;
  final String placeholder;
  final String question;
  final String notesLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        question,
        style: TextStyle(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      FeelingRating(value: rating, onChanged: onRatingChanged),
      const SizedBox(height: AppSpacing.lg),
      LambdaInput(
        controller: notesCtrl,
        label: notesLabel,
        placeholder: placeholder,
        onChanged: onNotesChanged,
      ),
    ],
  );
}

/// The session viewer shared by the prep page (PREVIOUS SESSION) and the
/// reflection page (THIS SESSION). Card 1 — all-sessions picker, pager
/// chevrons, planned source — taps through to the past-session viewer
/// (disabled for the still-active session); card 2 holds the PRS/LESSONS
/// reflection; card 3 shows the session's pre/post bookends. Chevrons page
/// left = older, right = newer without leaving the page.
class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({required this.vm, this.showPostBookend = true});

  final SessionViewModel vm;

  /// Whether card 3 renders the POST-WORKOUT bookend. False while the
  /// current (still-active) session is shown — its post rating/notes are
  /// being entered in the form above, not stored yet.
  final bool showPostBookend;

  @override
  Widget build(BuildContext context) {
    final session = vm.reflectionSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: session identity — pager, planned source, feeling.
        // Tapping opens the shown session in the past-session viewer.
        AppCard(
          // The still-active session must not open the past-session viewer —
          // its edit mode would let the user change sets the live VM doesn't
          // know about mid-workout.
          onTap: session == null || vm.reflectionIsCurrent
              ? null
              : () async {
                  await context.push('/logs/${session.sessionId}');
                  // Note/feeling edits made in the past-session viewer show
                  // immediately when the viewer card recomputes on return.
                  vm.refreshShownReflection();
                },
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    // The shown session's date anchors the pager.
                    child: Text(
                      session == null
                          ? ''
                          : DateFormat('MMM d').format(session.createdDate),
                      style: AppFonts.mono(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  // All-sessions picker — jumps the card to any completed
                  // session instead of paging one step at a time.
                  _pagerButton(
                    Icons.list_alt,
                    vm.completedSessionCount > 0,
                    () => _openSessionPicker(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _pagerButton(
                    Icons.chevron_left,
                    vm.reflectionCanGoOlder,
                    vm.showOlderReflectionSession,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _pagerButton(
                    Icons.chevron_right,
                    vm.reflectionCanGoNewer,
                    vm.showNewerReflectionSession,
                  ),
                ],
              ),
              // The planned session (if any) this session was started from —
              // planned-blue ghost container styling.
              if (session?.parentSessionName != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.plannedBg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.planned, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 16,
                        color: AppColors.planned,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${session!.parentSessionName}',
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.xs,
                            letterSpacing: 0.6,
                            color: AppColors.planned,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Card 2: the PRS and LESSONS sections — a separate container; the
        // sections carry their own empty notes.
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ReflectionSummary(
            exerciseIds: vm.reflectionExercises,
            prsByExercise: vm.reflectionPrsByExercise,
            lessonsByExercise: vm.reflectionLessonsByExercise,
            exerciseNameFor: (id) => vm.reflectionExerciseNames[id] ?? '',
            previousFor: vm.previousForReflection,
          ),
        ),
        if (session != null) ...[
          const SizedBox(height: AppSpacing.md),
          // Card 3: the session's bookends — pre and post ratings and notes,
          // shown after the PRS/LESSONS reflection. Always rendered, with the
          // same explicit empty note as the reflection sections ("No
          // pre/post-workout notes") so a sparse session still reads complete.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bookend(
                  'PRE-WORKOUT',
                  session.preFeeling,
                  session.preNotes,
                  'No pre-workout notes',
                  question: 'How well do you think you\'re going to do',
                  notesLabel: 'Why do you feel that way',
                ),
                if (showPostBookend) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _bookend(
                    'POST-WORKOUT',
                    session.feeling,
                    session.postNotes,
                    'No post-workout notes',
                    question: 'How well did you do this session',
                    notesLabel: 'What could have made this session better',
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The all-sessions sheet — training-logs-style rows (date, planned name,
  /// exercises × sets, pre/post ratings) that jump the card to the tapped
  /// session.
  void _openSessionPicker(BuildContext context) {
    showLambdaModal<void>(
      context,
      fitContent: true,
      // Page background under the rows so the surface cards separate from
      // the sheet itself.
      backgroundColor: AppColors.bg,
      child: _SessionPickerSheet(vm: vm),
    );
  }

  /// Card-3 section label — the muted mono micro-label style.
  Widget _bookendLabel(String text) => Text(
    text,
    style: AppFonts.mono(
      fontSize: 9,
      letterSpacing: 0.8,
      color: AppColors.muted,
    ),
  );

  /// One bookend section (feeling + notes) — the questionnaire read back
  /// with the same wording/styling as the live form: [question] above the
  /// rating and [notesLabel] above the notes. Rating and notes always
  /// render: an unrated session shows empty squares, and empty notes show
  /// [emptyNotes] in the reflection sections' empty-note style. Notes sit in
  /// a lesson-row container and scroll inside it when long.
  Widget _bookend(
    String label,
    int? feeling,
    String? notes,
    String emptyNotes, {
    required String question,
    required String notesLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _bookendLabel(label),
      const SizedBox(height: AppSpacing.sm),
      Text(
        question,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      // Full-size squares — the usual rating size, centered like the
      // prep page's THIS SESSION input.
      FeelingRating(value: feeling),
      const SizedBox(height: AppSpacing.sm),
      Text(
        notesLabel,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: 6),
      if (notes != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: ConstrainedBox(
            // Roomier than one line so short notes still read as a box;
            // long notes scroll inside it instead of stretching the card.
            constraints: const BoxConstraints(minHeight: 64, maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                notes,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        )
      else
        Text(
          emptyNotes,
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        ),
    ],
  );

  /// Bordered pager chevron — the neutral chip styling (surfaceHigh fill +
  /// border outline when actionable, hairline + muted when disabled) so the
  /// enabled state reads as a real button.
  Widget _pagerButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      // Disabled chevrons still claim the tap with a no-op handler — a
      // GestureDetector with no recognizers lets the tap fall through to the
      // card's PressSquash, which would navigate into the session.
      onTap: enabled ? onTap : () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.border,
            width: enabled ? 1.0 : 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }
}

/// The all-sessions picker sheet — completed sessions newest-first in
/// training-logs style: date, planned pill, exercise × set summaries, and
/// the pre/post ratings (notes are omitted from the preview). Tapping a row
/// selects that session in the viewer card.
class _SessionPickerSheet extends StatefulWidget {
  const _SessionPickerSheet({required this.vm});

  final SessionViewModel vm;

  @override
  State<_SessionPickerSheet> createState() => _SessionPickerSheetState();
}

class _SessionPickerSheetState extends State<_SessionPickerSheet> {
  late final Future<List<SessionWithSets>> _sessions = widget.vm
      .loadCompletedSessions();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                'ALL SESSIONS',
                style: AppFonts.mono(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<SessionWithSets>>(
                future: _sessions,
                builder: (context, snap) {
                  final list = snap.data;
                  if (list == null) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      ),
                    );
                  }
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'No completed sessions yet',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: AppTextStyles.sm,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _pickerRow(context, list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerRow(BuildContext context, SessionWithSets w) {
    final s = w.session;
    final selected = s.sessionId == widget.vm.reflectionSession?.sessionId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PressSquash(
        onTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          widget.vm.selectReflectionSession(s.sessionId);
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            // Recessed — darker than the sheet's bg so the row cards
            // separate from the page ground.
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // The soft-highlight recipe marks the session the card shows.
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pickerGrid(s),
              if (w.sets.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _exerciseSummaries(w.sets),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The row's 2×2 identity grid — date, planned source, pre and post
  /// ratings — hairline-separated cells in the StatsRow style. Exercises
  /// live below it, centered.
  Widget _pickerGrid(Session s) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _gridCell(
                  'DATE',
                  Text(
                    DateFormat('MMM d, yyyy').format(s.createdDate),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Expanded(
                child: _gridCell(
                  'PLANNED',
                  s.parentSessionName != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.plannedBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.planned.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            s.parentSessionName!,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w700,
                              color: AppColors.planned,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text(
                          '—',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.muted,
                          ),
                        ),
                ),
              ),
            ],
          ),
          Container(height: 1, color: AppColors.border),
          Row(
            children: [
              Expanded(
                child: _gridCell(
                  'PRE',
                  FeelingRating(value: s.preFeeling, size: 14, spacing: 3),
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Expanded(
                child: _gridCell(
                  'POST',
                  FeelingRating(value: s.feeling, size: 14, spacing: 3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gridCell(String label, Widget content) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: 9,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 3),
        content,
      ],
    ),
  );

  List<Widget> _exerciseSummaries(List<SessionSet> sets) {
    final order = <String>[];
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final s in sets) {
      if (!names.containsKey(s.exerciseId)) {
        order.add(s.exerciseId);
        names[s.exerciseId] = s.exerciseName ?? s.exerciseId;
      }
      counts[s.exerciseId] = (counts[s.exerciseId] ?? 0) + 1;
    }
    return order.map((exId) {
      final count = counts[exId]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                toProperCase(names[exId]!),
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count ${count == 1 ? 'set' : 'sets'}',
              style: AppFonts.mono(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      );
    }).toList();
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
          color:
              vm.selectedPlannedSession != null ||
                  vm.selectedStandaloneWorkout != null
              ? AppColors.plannedBg
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                vm.selectedPlannedSession != null ||
                    vm.selectedStandaloneWorkout != null
                ? AppColors.planned.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vm.selectedPlannedSession != null) ...[
                    Text(
                      'Week ${vm.programProgress!.weekNumber} · ${vm.programProgress!.program.name}',
                      style: AppFonts.mono(
                        fontSize: 9,
                        letterSpacing: 0.6,
                        color: AppColors.planned,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vm.selectedPlannedSession!.name,
                      style: AppFonts.ui(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ] else if (vm.selectedStandaloneWorkout != null) ...[
                    Text(
                      'Standalone session',
                      style: AppFonts.mono(
                        fontSize: 9,
                        letterSpacing: 0.6,
                        color: AppColors.planned,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vm.selectedStandaloneWorkout!.name,
                      style: AppFonts.ui(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ] else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Freestyle Session',
                          style: AppFonts.ui(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No planned session — add exercises as you train',
                          style: AppFonts.mono(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.swap_vert,
              size: 18,
              color:
                  vm.selectedPlannedSession != null ||
                      vm.selectedStandaloneWorkout != null
                  ? AppColors.planned
                  : AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Training ───────────────────────────────────────────────────────────

class _TrainingPage extends StatelessWidget {
  const _TrainingPage({required this.vm, required this.onRemoveExercise});

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
        _SessionTemplateCard(
          vm: vm,
          onTap: () => _showWorkoutPicker(context, vm),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SessionPreview(vm: vm),
      ],
    );
  }

  /// Active: the exercise card fills the screen; the session stats bar
  /// (PRS/LESSONS) sticks to the very bottom. The pinned lesson lives in
  /// the exercise card, right under the exercise.
  Widget _buildActive() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: vm.activeSlot == null
                ? _PlaceholderExerciseCard(vm: vm)
                // Key per exercise slot: switching tabs recreates the card
                // state so an open history view doesn't carry over.
                : LiveExerciseCard(
                    key: ValueKey(vm.activeSlot!.id),
                    vm: vm,
                    slot: vm.activeSlot!,
                    onRemoveExercise: () =>
                        onRemoveExercise(vm.activeSlotIndex),
                  ),
          ),
        ),
        // Sticky bottom: the session stats bar.
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: SessionStatsBar(vm: vm),
        ),
      ],
    );
  }

  /// Lets the user pick which session template to log — a standalone
  /// template, a program planned session, or none (free-form).
  Future<void> _showWorkoutPicker(
    BuildContext context,
    SessionViewModel vm,
  ) async {
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
              child: Text(
                'Select session',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                vm.clearTemplateSelection();
                Navigator.of(ctx).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                color:
                    vm.selectedPlannedSession == null &&
                        vm.selectedStandaloneWorkout == null
                    ? AppColors.accentBg
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_off_outlined,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'No planned session',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
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
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  'Workouts',
                  style: AppFonts.mono(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AppColors.muted,
                  ),
                ),
              ),
              for (final w in vm.standaloneWorkouts)
                InkWell(
                  onTap: () {
                    vm.selectStandaloneWorkout(w);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    color:
                        w.sessionId == vm.selectedStandaloneWorkout?.sessionId
                        ? AppColors.accentBg
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            toProperCase(w.name),
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.md,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        if (w.sessionId ==
                            vm.selectedStandaloneWorkout?.sessionId)
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
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  'Program',
                  style: AppFonts.mono(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AppColors.muted,
                  ),
                ),
              ),
              for (final w in vm.availableWorkouts)
                InkWell(
                  onTap: () {
                    vm.selectPlannedSession(w);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    color: w.sessionId == vm.selectedPlannedSession?.sessionId
                        ? AppColors.accentBg
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            toProperCase(w.name),
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.md,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
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
            for (final id in order) toProperCase(vm.exerciseDisplayName(id)),
          ],
          keys: order,
          activeIndex: activeIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          // No onReorder/onRemove/onAdd — the preview is read-only.
        ),
        const SizedBox(height: AppSpacing.xs),
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
                    toProperCase(vm.exerciseDisplayName(id)),
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
                  child: Text(
                    name,
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: exerciseId == null
                          ? AppColors.muted
                          : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _disabledPill(
                      icon: Icons.menu_book_outlined,
                      label: 'Lessons',
                    ),
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
              child: Text(
                '$index',
                style: AppFonts.mono(fontSize: 11, color: AppColors.muted),
              ),
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
        border: Border.all(color: AppColors.planned.withValues(alpha: 0.35)),
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
                  child: Text(
                    toProperCase(vm.exerciseDisplayName(exerciseId)),
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.planned.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.planned.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'PLANNED',
                    style: AppFonts.mono(
                      fontSize: 11,
                      letterSpacing: 0.4,
                      color: AppColors.planned,
                    ),
                  ),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'No planned sets',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: AppTextStyles.sm,
                      ),
                    ),
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

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 8,
      letterSpacing: 0.6,
      color: AppColors.muted,
    ),
  );

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
            color: AppColors.planned.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$index',
                style: AppFonts.mono(fontSize: 11, color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: _valueCell(weight != null ? '${weight}kg' : '—')),
            const SizedBox(width: 6),
            Expanded(
              child: _valueCell(reps == null || reps.isEmpty ? '—' : reps),
            ),
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
                    ? Text(
                        toProperCase(variation),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.mono(
                          fontSize: 10,
                          color: AppColors.planned,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 32,
              child: hasNotes
                  ? Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: AppColors.planned,
                    )
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
        child: Text(
          text,
          style: AppFonts.mono(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: color ?? AppColors.planned,
          ),
        ),
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
                  child: Text(
                    'Add your first exercise',
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                GlassButton(
                  label: 'Add Exercise',
                  compact: true,
                  onPressed: () => showAddExerciseModal(context, vm: vm),
                ),
                const SizedBox(width: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _disabledPill(
                      icon: Icons.menu_book_outlined,
                      label: 'Lessons',
                    ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 8,
      letterSpacing: 0.6,
      color: AppColors.muted,
    ),
  );
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
        Text(
          label,
          style: AppFonts.mono(
            fontSize: 11,
            letterSpacing: 0.4,
            color: AppColors.muted.withValues(alpha: 0.4),
          ),
        ),
      ],
    ),
  );
}

// ── Page 2: Reflection ───────────────────────────────────────────────────────

class _ReflectionPage extends StatelessWidget {
  const _ReflectionPage({required this.vm, required this.notesCtrl});

  final SessionViewModel vm;
  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.hasActiveWorkout) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(
                  child: Text(
                    'Nothing to reflect on yet — finish a session here.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppTextStyles.sm,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        // The exact prep-page layout: the POST-WORKOUT form on top, then the
        // THIS SESSION divider, then the shared session-viewer card (which
        // hides its own POST-WORKOUT bookend for the still-active session).
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _FeelingForm(
              rating: vm.endFeeling,
              onRatingChanged: vm.setEndFeeling,
              notesCtrl: notesCtrl,
              onNotesChanged: (v) => vm.endNotes = v,
              placeholder: 'How did it go?\nStrong sets?\nAnything to fix?',
              question: 'How well did you do this session',
              notesLabel: 'What could have made this session better',
            ),
            const SizedBox(height: AppSpacing.xl),
            // The divider names what the viewer shows — THIS SESSION while
            // the still-active workout is selected, PREVIOUS SESSION once
            // the chevrons page into completed history.
            _SectionDivider(
              vm.reflectionIsCurrent ? 'THIS SESSION' : 'PREVIOUS SESSION',
            ),
            const SizedBox(height: AppSpacing.sm),
            _LastSessionCard(vm: vm, showPostBookend: !vm.reflectionIsCurrent),
          ],
        );
      },
    );
  }
}

