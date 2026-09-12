import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/planned_banner.dart';
import '../../../shared/widgets/reflection_summary.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/session_bookend.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/stats_row.dart';
import '../../session/model/pr_engine.dart';
import '../../session/view/lessons_modal.dart';
import '../../session/view/pr_modal.dart';
import '../viewmodel/session_detail_viewmodel.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with UnsavedChangesGuard<SessionDetailScreen> {
  late final SessionDetailViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = SessionDetailViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm.load(widget.sessionId);
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  // ── UnsavedChangesGuard ─────────────────────────────────────────────────

  @override
  bool get hasUnsavedChanges =>
      (_vm.state.value.isEditing ||
      _vm.state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty));

  @override
  Future<void> onSave() async {
    await _vm.saveNotes(widget.sessionId);
  }

  @override
  void onDiscard() {
    _vm.cancelEditing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<SessionDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          if (state.isLoading) {
            return Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }
          return buildGuardedScaffold(
            scaffold: Scaffold(
              backgroundColor: AppColors.bg,
              body: Column(
                children: [
                  PageHeader(
                    title: state.isEditing ? 'Edit Session' : 'Past Session',
                    left: GestureDetector(
                      onTap: () async {
                        if (state.isEditing) {
                          final didProceed = await confirmBack();
                          if (didProceed && mounted) {
                            Navigator.of(this.context).pop();
                          }
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    right: state.isEditing
                        ? GlassButton(
                            label: 'Done',
                            compact: true,
                            loading: state.isSaving,
                            disabled: state.isSaving,
                            onPressed: () => _vm.saveNotes(widget.sessionId),
                          )
                        : GlassButton(
                            label: 'Edit',
                            compact: true,
                            onPressed: _vm.startEditing,
                          ),
                  ),
                  Expanded(
                    child: SessionDetailView(viewModel: _vm, state: state),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

/// The past-session viewer's tabbed content — the Details/Summary toggle
/// plus the selected surface. Shared between the /logs route (with its
/// Edit header) and the Session tab's Home embed (read-only view mode).
class SessionDetailView extends StatefulWidget {
  const SessionDetailView({
    super.key,
    required this.viewModel,
    required this.state,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  @override
  State<SessionDetailView> createState() => _SessionDetailViewState();
}

class _SessionDetailViewState extends State<SessionDetailView> {
  /// Which of the two surfaces is shown: the pre/PRS/lessons/post summary,
  /// or the sets (details). Plain UI state — no VM involvement.
  String _tab = 'summary';

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final state = widget.state;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: SegmentedControl<String>(
            options: const [
              SegmentOption(label: 'Summary', value: 'summary'),
              SegmentOption(label: 'Details', value: 'details'),
            ],
            value: _tab,
            onChange: (v) => setState(() => _tab = v),
          ),
        ),
        Expanded(child: _body(viewModel, state)),
      ],
    );
  }

  Widget _body(SessionDetailViewModel viewModel, SessionDetailState state) {
    if (_tab == 'summary') {
      return _SessionSummaryBody(viewModel: viewModel, state: state);
    }
    if (state.exerciseSlots.isEmpty) {
      return Center(
        child: Text(
          'No sets recorded.',
          style: AppFonts.ui(fontSize: 15, color: AppColors.muted),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.session?.plannedSessionName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      state.session!.plannedSessionName!,
                      style: AppFonts.mono(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        color: AppColors.planned,
                      ),
                    ),
                  ),
                if (state.activeSlot != null)
                  _DetailCardBuilder(
                    viewModel: viewModel,
                    state: state,
                    slot: state.activeSlot!,
                    onAddExercise: () => _showAddExercise(context),
                  ),
              ],
            ),
          ),
        ),
        // Sticky bottom: SETS/PRS/EXERCISES — the live session's bottom-bar
        // position; the PRS tile stays accent + tappable.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: StatsRow(
            tiles: [
              StatsTile(
                label: 'SETS',
                value: '${state.setsByOrder.values.expand((l) => l).length}',
              ),
              StatsTile(
                label: 'PRS',
                value: '${state.totalPRCount}',
                accent: state.totalPRCount > 0,
                onTap: state.totalPRCount > 0
                    ? () => showPrModal(context, prs: state.prEvents)
                    : null,
              ),
              StatsTile(
                label: 'EXERCISES',
                value: '${state.exerciseSlots.length}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddExercise(BuildContext context) {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _DetailAddExerciseContent(viewModel: widget.viewModel),
    );
  }
}

// ── Summary tab ───────────────────────────────────────────────────────────────

/// The session's bookends and reflection — the same layout as the prep
/// page's LAST SESSION card, minus its date row and session pager (this
/// screen is a focused view of one session). Order per spec: pre-training
/// data, then PRS + LESSONS, then post-training data.
class _SessionSummaryBody extends StatelessWidget {
  const _SessionSummaryBody({required this.viewModel, required this.state});

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session;

    // PR events grouped by exercise.
    final prsByExercise = <String, List<PrEvent>>{};
    for (final p in state.prEvents) {
      prsByExercise.putIfAbsent(p.exerciseId, () => []).add(p);
    }
    // Session-scoped lessons only — mirrors the prep card, where only
    // lessons born in the shown session count toward its preview.
    final lessonsByExercise = <String, List<String>>{};
    for (final e in state.lessonsByExercise.entries) {
      lessonsByExercise[e.key] = [
        for (final l in e.value)
          if (l.sessionId == session?.sessionId) l.text,
      ];
    }
    final exerciseIds = [
      for (final sl in state.exerciseSlots) sl.exerciseId,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pre card: planned source (if any) + the PRE-WORKOUT bookend.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session?.plannedSessionName != null) ...[
                  PlannedBanner(name: session!.plannedSessionName!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                SessionBookend(
                  label: 'PRE-WORKOUT',
                  feeling: state.isEditing
                      ? state.preFeelingDraft
                      : session?.preFeeling,
                  notes: state.isEditing ? state.preNotesDraft : session?.preNotes,
                  emptyNotes: 'No pre-workout notes',
                  question: 'How well do you think you\'re going to do',
                  notesLabel: 'Why do you feel that way',
                  onFeelingChanged:
                      state.isEditing ? viewModel.setPreFeelingDraft : null,
                  onNotesChanged:
                      state.isEditing ? viewModel.setPreNotesDraft : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // The PRS and LESSONS sections — the sections carry their own
          // empty notes.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ReflectionSummary(
              exerciseIds: exerciseIds,
              prsByExercise: prsByExercise,
              lessonsByExercise: lessonsByExercise,
              exerciseNameFor: viewModel.exerciseDisplayName,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Post card: the POST-WORKOUT bookend.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SessionBookend(
              label: 'POST-WORKOUT',
              feeling: state.isEditing
                  ? state.postFeelingDraft
                  : session?.feeling,
              notes:
                  state.isEditing ? state.postNotesDraft : session?.postNotes,
              emptyNotes: 'No post-workout notes',
              question: 'How well did you do this session',
              notesLabel: 'What could have made this session better',
              onFeelingChanged:
                  state.isEditing ? viewModel.setPostFeelingDraft : null,
              onNotesChanged:
                  state.isEditing ? viewModel.setPostNotesDraft : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise card ────────────────────────────────────────────────────────────

/// The past-session viewer's exercise card — an adapter over the shared
/// [SessionExerciseCard]. View mode greys edit-only affordances (reorder,
/// add, hold-to-delete X, ADD SET, swipe, editable cells); edit mode enables
/// them. The selector switch works in both modes (browsing).
class _DetailCardBuilder extends StatelessWidget {
  const _DetailCardBuilder({
    required this.viewModel,
    required this.state,
    required this.slot,
    required this.onAddExercise,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;
  final SessionDetailExerciseSlot slot;
  final VoidCallback onAddExercise;

  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static double? _parseWeight(String? t) =>
      t == null || t.isEmpty ? null : double.tryParse(t);

  static List<num>? _parseReps(String? t) {
    final r = t == null || t.isEmpty ? null : num.tryParse(t);
    return r == null ? null : [r];
  }

  void _confirmRemoveExercise(BuildContext context) {
    final name = toProperCase(viewModel.exerciseDisplayName(slot.exerciseId));
    final setCount = state.setsFor(slot.groupOrder).length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Exercise',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Keep', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final index = state.exerciseSlots.indexWhere(
                (sl) => sl.groupOrder == slot.groupOrder,
              );
              viewModel.removeExerciseGroup(index);
            },
            child: Text(
              'Remove',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete with the PR-count warning — cascade so PRs recompute.
  Future<void> _confirmDeleteSet(SessionExerciseSet set, BuildContext context) async {
    // In-memory PR count from the already-computed workout PR events.
    final prCount = state.prEvents
        .where((r) => r.sessionExerciseSetId == set.sessionExerciseSetId)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Set',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          prCount > 0
              ? 'This set holds $prCount PR record${prCount == 1 ? '' : 's'}, which will be deleted too. Remove this set?'
              : 'Remove this set from the workout?',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await viewModel.deleteSetCascade(
        set.sessionExerciseSetId,
        set.exerciseId ?? '',
      );
      if (context.mounted) _showDeleteErrorIfAny(context);
    }
  }

  void _showDeleteErrorIfAny(BuildContext context) {
    final err = viewModel.state.value.error;
    if (err == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final exerciseId = slot.exerciseId;
    final order = slot.groupOrder;
    final name = toProperCase(viewModel.exerciseDisplayName(exerciseId));
    final history = viewModel.historyFor(exerciseId);
    final sets = state.setsFor(order);
    final draftIds = state.workoutSetDrafts[order] ?? const <int>[];
    // The orange PR accent = this session's PR events — the same sets the
    // stats tile, pills, and modal count.
    final prSetIds = {
      for (final r in state.prEvents)
        if (r.sessionExerciseSetId != null) r.sessionExerciseSetId!,
    };

    // The pinned lesson shows right under the exercise — pinning is what
    // decides whether a note appears there.
    Lesson? pinnedLesson;
    for (final l in viewModel.lessonsFor(exerciseId)) {
      if (l.pinned) {
        pinnedLesson = l;
        break;
      }
    }

    void openLessonsModal() => showLessonsModal(
      context,
      listenable: viewModel.state,
      lessonsFor: viewModel.lessonsFor,
      loadLessonsFor: viewModel.loadLessonsFor,
      addLesson: viewModel.addLesson,
      toggleLessonPin: viewModel.toggleLessonPin,
      deleteLesson: viewModel.deleteLesson,
      updateLesson: viewModel.updateLessonText,
      exerciseId: exerciseId,
      exerciseName: name,
    );

    final variationOptions = [
      const DropdownOption<String?>(label: 'No Variation', value: null),
      ...viewModel.variationsByRecency.map(
        (v) => DropdownOption<String?>(label: v.name, value: v.variationId),
      ),
    ];
    final allVariations = [
      for (final v in state.allVariations)
        (id: v.variationId, name: v.name),
    ];

    List<Widget> rows = [];
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      rows.add(
        SessionSetRow(
          key: ValueKey(set.sessionExerciseSetId),
          mode: SetRowMode.history,
          exerciseId: exerciseId,
          displayIndex: i + 1,
          isDraft: false,
          initialWeightText: set.weight != null ? _fmtNum(set.weight!) : '',
          initialRepsText: set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '',
          initialVariationId: set.variationId,
          initialVariationName: set.variationName,
          initialNotes: set.notes,
          hasNotes: set.notes?.isNotEmpty ?? false,
          isPr: prSetIds.contains(set.sessionExerciseSetId),
          readOnly: !state.isEditing,
          onCommit: (isDraft, v) async {
            if (!isDraft) {
              await viewModel.quickUpdateSet(
                set,
                weight: _parseWeight(v.weight),
                clearWeight: v.weight == null,
                reps: _parseReps(v.reps),
              );
            }
          },
          onVariationChanged: (id) => viewModel.quickUpdateSet(
            set,
            variationId: id,
            clearVariation: id == null,
          ),
          onNotesSave: (v) => viewModel.quickUpdateSet(
            set,
            notes: v.trim().isEmpty ? null : v.trim(),
            clearNotes: v.trim().isEmpty,
          ),
          onDelete: () => _confirmDeleteSet(set, context),
          onDuplicate: () => viewModel.duplicateSet(set),
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: viewModel.findSimilarVariations,
          submitNewVariation: viewModel.submitNewVariation,
        ),
      );
    }
    for (var i = 0; i < draftIds.length; i++) {
      final draftId = draftIds[i];
      rows.add(
        SessionSetRow(
          key: ValueKey('draft-$draftId'),
          mode: SetRowMode.history,
          exerciseId: exerciseId,
          displayIndex: sets.length + i + 1,
          isDraft: true,
          initialWeightText: '',
          initialRepsText: '',
          initialVariationId: null,
          hasNotes: false,
          onCommit: (isDraft, v) async {
            if (isDraft) {
              // The row guarantees reps text for history drafts — the
              // numeric formatter makes this parse safe.
              final reps = num.tryParse(v.reps!) ?? 0;
              await viewModel.commitDraftSet(
                exerciseId,
                order,
                draftId,
                variationId: v.variationId,
                weight: _parseWeight(v.weight),
                reps: [reps],
                notes: v.notes,
              );
            }
          },
          onVariationChanged: (_) {},
          onNotesSave: (_) {},
          onDelete: () async => viewModel.removeDraftSet(order, draftId),
          onDuplicate: () {},
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: viewModel.findSimilarVariations,
          submitNewVariation: viewModel.submitNewVariation,
        ),
      );
    }

    return SessionExerciseCard(
      exerciseNames: [
        for (final sl in state.exerciseSlots)
          toProperCase(viewModel.exerciseDisplayName(sl.exerciseId)),
      ],
      activeIndex: state.activeSlotIndex,
      onSelect: (i) => viewModel.tapTab(i),
      // Edit-only affordances: null greys the reorder arrows and the Add
      // Exercise row; the hold-to-delete X is hidden in view mode.
      onMove: state.isEditing
          ? (i, dir) => viewModel.reorderExercises(i, i + dir)
          : null,
      onAdd: state.isEditing ? onAddExercise : null,
      onDeleteRequest: state.isEditing
          ? () => _confirmRemoveExercise(context)
          : null,
      pinnedLesson: pinnedLesson != null
          ? PinnedLessonData(
              text: pinnedLesson.text,
              date: pinnedLesson.createdDate,
            )
          : null,
      onPinnedLessonTap: openLessonsModal,
      lessonsCount: viewModel.lessonsFor(exerciseId).length,
      onLessonsTap: openLessonsModal,
      prCount: viewModel.prCountFor(exerciseId),
      // Gate on DISPLAYABLE records, not the countable count — a
      // weight-max-only exercise still has PRs to show.
      onPrTap: viewModel.displayPrsFor(exerciseId).isNotEmpty
          ? () => showPrModal(
              context,
              prs: viewModel.displayPrsFor(exerciseId),
            )
          : null,
      // PLANNED badge → the planned card outline, like the live screen.
      planned: state.session?.plannedSessionId != null,
      rows: rows,
      onAddSet: state.isEditing ? () => viewModel.addDraftSet(order) : null,
      history: history,
      // The history viewer is the regular sets grid — read-only here (the
      // screen's own edit mode is the logs' editing surface), so the rows
      // are inert shared SessionSetRows with no edit gate.
      historyRowBuilder: (s) => SessionSetRow(
        key: ValueKey('history-${s.sessionExerciseSetId}'),
        mode: SetRowMode.history,
        exerciseId: s.exerciseId ?? '',
        displayIndex: s.setNumber,
        isDraft: false,
        initialWeightText: s.weight != null ? _fmtNum(s.weight!) : '',
        initialRepsText: s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '',
        initialVariationId: s.variationId,
        initialVariationName: s.variationName,
        initialNotes: s.notes,
        hasNotes: s.notes?.isNotEmpty ?? false,
        // Past PR sets badge like the grid — events are keyed by set id.
        isPr: state.prEventSetIds.contains(s.sessionExerciseSetId),
        readOnly: true,
        onCommit: (_, _) async {},
        onVariationChanged: (_) {},
        onNotesSave: (_) {},
        onDelete: () async {},
        onDuplicate: () {},
        variationOptions: variationOptions,
        allVariations: allVariations,
        findSimilarVariations: viewModel.findSimilarVariations,
        submitNewVariation: viewModel.submitNewVariation,
      ),
    );
  }
}

// ── Add Exercise Modal ───────────────────────────────────────────────────────

class _DetailAddExerciseContent extends StatefulWidget {
  const _DetailAddExerciseContent({required this.viewModel});

  final SessionDetailViewModel viewModel;

  @override
  State<_DetailAddExerciseContent> createState() =>
      _DetailAddExerciseContentState();
}

class _DetailAddExerciseContentState extends State<_DetailAddExerciseContent> {
  String _query = '';

  List<MapEntry<String, String>> get _filtered {
    final s = widget.viewModel.state.value;
    final entries = s.exerciseDetailMap.entries
        .where(
          (e) => toProperCase(
            e.value.name,
          ).toLowerCase().contains(_query.toLowerCase()),
        )
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
    // Most recently used first (newest history session per exercise, nulls
    // last), then name.
    final lastUsed = <String, DateTime>{};
    for (final sessions in s.historyByExercise.values) {
      if (sessions.isNotEmpty) {
        final exId = sessions.first.sets.first.exerciseId;
        if (exId != null) lastUsed[exId] = sessions.first.date;
      }
    }
    entries.sort((a, b) {
      final da = lastUsed[a.key];
      final db = lastUsed[b.key];
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return entries;
  }

  bool get _canCreate =>
      _query.trim().length > 1 &&
      !widget.viewModel.state.value.exerciseDetailMap.values.any(
        (e) => e.name.toLowerCase() == _query.trim().toLowerCase(),
      );

  void _pick(String exerciseId) {
    widget.viewModel.addExerciseGroup(exerciseId);
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _createNew() async {
    final id = await widget.viewModel.submitNewExercise(_query);
    if (id == null || !mounted) return;
    _pick(id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add exercise',
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              autofocus: true,
              style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.muted,
                ),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ValueListenableBuilder<SessionDetailState>(
                valueListenable: widget.viewModel.state,
                builder: (context, state, _) => ListView(
                  shrinkWrap: true,
                  children: [
                    ..._filtered.map(
                      // Exercises are unique per session — already-added
                      // ones are marked, and picking one just switches to
                      // its existing tab.
                      (e) => _resultRow(
                        e.value,
                        () => _pick(e.key),
                        added: state.exerciseSlots.any(
                          (sl) => sl.exerciseId == e.key,
                        ),
                      ),
                    ),
                    if (_canCreate)
                      _resultRow(
                        '+ Create "${_query.trim()}"',
                        state.newExCreating ? null : _createNew,
                        accent: true,
                      ),
                    if (_filtered.isEmpty &&
                        !_canCreate &&
                        _query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: Text(
                            'No exercises found',
                            style: AppFonts.ui(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, VoidCallback? onTap, {bool accent = false, bool added = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          // Pressable rows — the glass recipe in their semantic color.
          decoration: glassBox(accent ? AppColors.accent : AppColors.primary),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppFonts.ui(
                    fontSize: 14,
                    fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                    color: accent ? AppColors.accent : AppColors.primary,
                  ),
                ),
              ),
              if (added) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  'Added',
                  style: AppFonts.mono(
                    fontSize: 9,
                    letterSpacing: 0.4,
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
