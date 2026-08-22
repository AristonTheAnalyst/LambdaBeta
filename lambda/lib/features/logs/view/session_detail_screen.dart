import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session_set.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/stats_row.dart';
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
                    child: _SessionBody(viewModel: _vm, state: state),
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

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.viewModel, required this.state});

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  @override
  Widget build(BuildContext context) {
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
                if (state.session?.parentSessionName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      state.session!.parentSessionName!,
                      style: AppFonts.mono(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        color: AppColors.planned,
                      ),
                    ),
                  ),
                if (state.session?.preFeeling != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.xs,
                    ),
                    child: FeelingRating(
                      value: state.session!.preFeeling,
                      label: 'Pre-workout feeling: ',
                      size: 20,
                      spacing: 4,
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
                    ? () => showPrModal(context, prs: state.prRecords)
                    : null,
              ),
              StatsTile(
                label: 'EXERCISES',
                value: '${state.exerciseSlots.length}',
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _notesButton(
                  context,
                  'Pre-Notes',
                  state.session?.preNotes ?? '',
                  'pre',
                  state.isEditing,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _notesButton(
                  context,
                  'Post-Notes',
                  state.session?.postNotes ?? '',
                  'post',
                  state.isEditing,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _notesButton(
    BuildContext context,
    String label,
    String content,
    String target,
    bool editing,
  ) {
    final filled = content.isNotEmpty;
    final tappable = editing || filled;
    return GestureDetector(
      onTap: tappable ? () => _showNotesModal(context, target) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.accentBg
              : editing
              ? AppColors.surfaceHigh
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: editing
                ? AppColors.border
                : filled
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notes_outlined,
              size: 15,
              color: filled ? AppColors.accent : AppColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppFonts.ui(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: filled ? AppColors.accent : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNotesModal(BuildContext context, String target) async {
    final preCtrl = TextEditingController(text: state.preNotesDraft);
    final postCtrl = TextEditingController(text: state.postNotesDraft);
    await showLambdaModal<void>(
      context,
      fitContent: true,
      keyboardAware: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                target == 'pre' ? 'Pre-Workout Notes' : 'Post-Workout Notes',
                style: AppFonts.ui(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: target == 'pre' ? preCtrl : postCtrl,
                readOnly: !state.isEditing,
                maxLines: 3,
                style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
                decoration: InputDecoration(
                  hintText: !state.isEditing ? '' : 'Notes…',
                  hintStyle: AppFonts.ui(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
                onChanged: state.isEditing
                    ? (target == 'pre'
                          ? viewModel.setPreNotesDraft
                          : viewModel.setPostNotesDraft)
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              GlassButton(
                label: 'Done',
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          ),
        ),
      ),
    );
    preCtrl.dispose();
    postCtrl.dispose();
  }

  void _showAddExercise(BuildContext context) {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _DetailAddExerciseContent(viewModel: viewModel),
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
  Future<void> _confirmDeleteSet(SessionSet set, BuildContext context) async {
    // In-memory PR count from the already-computed workout PR records.
    final prCount = state.prRecords
        .where((r) => r.setId == set.sessionSetId)
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
      await viewModel.deleteSetCascade(set.sessionSetId, set.exerciseId);
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
    final prSetIds = state.prRecords
        .where((r) => r.setId != null)
        .map((r) => r.setId!)
        .toSet();

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
          key: ValueKey(set.sessionSetId),
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
          isPr: prSetIds.contains(set.sessionSetId),
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
      onPrTap: viewModel.prCountFor(exerciseId) > 0
          ? () => showPrModal(context, prs: state.prRecords)
          : null,
      // PLANNED badge → the planned card outline, like the live screen.
      planned: state.session?.parentSessionId != null,
      rows: rows,
      onAddSet: state.isEditing ? () => viewModel.addDraftSet(order) : null,
      history: history,
      historyDetailSubtitle: 'Past performance for reference.',
      historyRowBuilder: (s) => HistorySetRow(set: s),
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
        lastUsed[sessions.first.sets.first.exerciseId] = sessions.first.date;
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
                      (e) => _resultRow(e.value, () => _pick(e.key)),
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

  Widget _resultRow(String label, VoidCallback? onTap, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: accent
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppFonts.ui(
              fontSize: 14,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              color: accent ? AppColors.accent : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
