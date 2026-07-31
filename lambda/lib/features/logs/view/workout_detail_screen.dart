import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/workout_set.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/exercise_tab_chip.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/stats_row.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../session/model/session_local_state.dart' show ExerciseHistorySession;
import '../../session/view/lessons_modal.dart';
import '../../session/view/notes_modal.dart';
import '../../session/view/pr_modal.dart';
import '../viewmodel/workout_detail_viewmodel.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});
  final String workoutId;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> with UnsavedChangesGuard<WorkoutDetailScreen> {
  late final WorkoutDetailViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = WorkoutDetailViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm.load(widget.workoutId);
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  // ── UnsavedChangesGuard ─────────────────────────────────────────────────

  @override
  bool get hasUnsavedChanges => (_vm.state.value.isEditing || _vm.state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty));

  @override
  Future<void> onSave() async {
    await _vm.saveNotes(widget.workoutId);
  }

  @override
  void onDiscard() {
    _vm.cancelEditing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<WorkoutDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          if (state.isLoading) {
            return Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
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
                          if (didProceed && mounted) Navigator.of(this.context).pop();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.accent),
                    ),
                    right: state.isEditing
                        ? GlassButton(
                            label: 'Done',
                            compact: true,
                            loading: state.isSaving,
                            disabled: state.isSaving,
                            onPressed: () => _vm.saveNotes(widget.workoutId),
                          )
                        : GlassButton(
                            label: 'Edit',
                            compact: true,
                            onPressed: _vm.startEditing,
                          ),
                  ),
                  Expanded(
                    child: _WorkoutBody(
                      viewModel: _vm,
                      state: state,
                    ),
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

class _WorkoutBody extends StatelessWidget {
  const _WorkoutBody({required this.viewModel, required this.state});

  final WorkoutDetailViewModel viewModel;
  final WorkoutDetailState state;

  @override
  Widget build(BuildContext context) {
    if (state.exerciseSlots.isEmpty) {
      return Center(
        child: Text('No sets recorded.',
            style: AppFonts.ui(fontSize: 15, color: AppColors.muted)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.workout?.plannedWorkoutName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(state.workout!.plannedWorkoutName!,
                        style: AppFonts.mono(fontSize: 10, letterSpacing: 0.6, color: AppColors.success)),
                  ),
                StatsRow(tiles: [
                  StatsTile(label: 'SETS', value: '${state.setsByOrder.values.expand((l) => l).length}'),
                  StatsTile(
                    label: 'PRS',
                    value: '${state.totalPRCount}',
                    accent: state.totalPRCount > 0,
                    onTap: state.totalPRCount > 0
                        ? () => showPrModal(context, prs: state.prRecords)
                        : null,
                  ),
                  StatsTile(label: 'EXERCISES', value: '${state.exerciseSlots.length}'),
                  const StatsTile(label: 'AVG REST', value: '—'),
                ]),
                if (state.workout?.preFeeling != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Text('Pre-workout feeling: ',
                            style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
                        ...List.generate(5, (i) {
                          final n = i + 1;
                          final selected = state.workout!.preFeeling! >= n;
                          return Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.accent : AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: selected ? AppColors.accent : AppColors.border),
                            ),
                            child: Center(
                              child: Text('$n',
                                  style: AppFonts.ui(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: selected ? AppColors.accentText : AppColors.muted)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                _DetailExerciseTabBar(
                  slots: state.exerciseSlots,
                  activeIndex: state.activeSlotIndex,
                  exerciseNames: state.exerciseSlots.map((sl) {
                    final detail = state.exerciseDetailMap[sl.exerciseId];
                    return toProperCase(detail?.name ?? '');
                  }).toList(),
                  onTap: (i) => viewModel.tapTab(i),
                  onAdd: state.isEditing ? () => _showAddExercise(context) : null,
                  onReorder: state.isEditing ? viewModel.reorderExercises : null,
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.activeSlot != null)
                  _DetailExerciseCard(
                    viewModel: viewModel,
                    slot: state.activeSlot!,
                  ),
              ],
            ),
          ),
        ),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(child: _notesButton(context, 'Pre-Notes', state.workout?.preNotes ?? '', 'pre', state.isEditing)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _notesButton(context, 'Post-Notes', state.workout?.postNotes ?? '', 'post', state.isEditing)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _notesButton(BuildContext context, String label, String content, String target, bool editing) {
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
              color: editing ? AppColors.border : filled ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes_outlined, size: 15, color: filled ? AppColors.accent : AppColors.muted),
            const SizedBox(width: 6),
            Text(label,
                style: AppFonts.ui(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: filled ? AppColors.accent : AppColors.muted)),
          ],
        ),
      ),
    );
  }

  void _showNotesModal(BuildContext context, String target) {
    final preCtrl = TextEditingController(text: state.preNotesDraft);
    final postCtrl = TextEditingController(text: state.postNotesDraft);
    showLambdaModal(
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
                style: AppFonts.ui(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
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
                onChanged: state.isEditing ? (target == 'pre' ? viewModel.setPreNotesDraft : viewModel.setPostNotesDraft) : null,
              ),
              const SizedBox(height: AppSpacing.md),
              GlassButton(
                label: 'Done',
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          ),
        ),
      ),
    );
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

// ── Tab bar ──────────────────────────────────────────────────────────────────

class _DetailExerciseTabBar extends StatelessWidget {
  const _DetailExerciseTabBar({
    required this.slots,
    required this.activeIndex,
    required this.exerciseNames,
    required this.onTap,
    this.onAdd,
    this.onReorder,
  });

  final List<WorkoutDetailExerciseSlot> slots;
  final int activeIndex;
  final List<String> exerciseNames;
  final ValueChanged<int> onTap;
  final VoidCallback? onAdd;
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: slots.length > 2 && onReorder != null
              ? SizedBox(
                  height: 42,
                  child: ReorderableListView(
                    scrollDirection: Axis.horizontal,
                    onReorderItem: onReorder!,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, _) => Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.85, child: child),
                    ),
                    children: [
                      for (var i = 0; i < slots.length; i++)
                        SizedBox(
                          key: ValueKey('ex-${slots[i].exerciseId}'),
                          child: ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ExerciseTabChip(
                                label: exerciseNames.length > i ? exerciseNames[i] : '',
                                isActive: i == activeIndex,
                                onTap: () => onTap(i),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < slots.length; i++) ...[
                        ExerciseTabChip(
                          label: exerciseNames.length > i ? exerciseNames[i] : '',
                          isActive: i == activeIndex,
                          onTap: () => onTap(i),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
        ),
        if (onAdd != null) ...[
          AddExerciseButton(onTap: onAdd!),
        ],
      ],
    );
  }
}

// ── Exercise card ────────────────────────────────────────────────────────────

class _DetailExerciseCard extends StatefulWidget {
  const _DetailExerciseCard({required this.viewModel, required this.slot});

  final WorkoutDetailViewModel viewModel;
  final WorkoutDetailExerciseSlot slot;

  @override
  State<_DetailExerciseCard> createState() => _DetailExerciseCardState();
}

class _DetailExerciseCardState extends State<_DetailExerciseCard> {
  bool _historyOpen = false;
  ExerciseHistorySession? _viewingSession;

  void _exitHistory() => setState(() {
        _historyOpen = false;
        _viewingSession = null;
      });

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final s = vm.state.value;
    final exerciseId = widget.slot.exerciseId;
    final order = widget.slot.groupOrder;
    final detail = s.exerciseDetailMap[exerciseId];
    final name = toProperCase(detail?.name ?? '');
    final lessons = vm.lessonsFor(exerciseId);
    final history = vm.historyFor(exerciseId);
    final planned = s.workout?.plannedWorkoutId != null;
    final prCount = vm.prCountFor(exerciseId);
    final sets = s.setsFor(order);
    final draftIds = s.workoutSetDrafts[order] ?? const <int>[];
    final viewingHistory = _viewingSession != null;
    final featuredLesson = lessons.isEmpty
        ? null
        : (lessons.where((l) => l.pinned).isNotEmpty ? lessons.firstWhere((l) => l.pinned) : lessons.last);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: viewingHistory ? AppColors.history : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (viewingHistory)
            _historyBanner(_viewingSession!)
          else if (featuredLesson != null)
            _lessonBar(featuredLesson, exerciseId, name),
          _header(
            name: name,
            planned: planned,
            prCount: prCount,
            lessonsCount: lessons.length,
            historyCount: history.length,
            exerciseId: exerciseId,
            viewingHistory: viewingHistory,
          ),
          if (_historyOpen && !viewingHistory) _historyPicker(history),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: viewingHistory
                ? _historyDetail(_viewingSession!)
                : _setsGrid(sets, draftIds, exerciseId, order, detail,
                      prSetIds: widget.viewModel.state.value.prRecords
                          .where((r) => r.setId != null)
                          .map((r) => r.setId!)
                          .toSet()),
          ),
        ],
      ),
    );
  }

  Widget _historyBanner(ExerciseHistorySession session) {
    return Container(
      color: AppColors.historyBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: AppColors.history),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Viewing — ${DateFormat('MMM d').format(session.date)}',
                style: AppFonts.mono(fontSize: 9, letterSpacing: 0.8, color: AppColors.history)),
          ),
          GlassButton(label: 'Back', color: AppColors.history, compact: true, onPressed: _exitHistory),
        ],
      ),
    );
  }

  Widget _lessonBar(Lesson lesson, String exerciseId, String exerciseName) {
    return GestureDetector(
      onTap: () => showLessonsModal(
        context,
        listenable: widget.viewModel.state,
        lessonsFor: widget.viewModel.lessonsFor,
        loadLessonsFor: widget.viewModel.loadLessonsFor,
        addLesson: widget.viewModel.addLesson,
        toggleLessonPin: widget.viewModel.toggleLessonPin,
        deleteLesson: widget.viewModel.deleteLesson,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
      ),
      child: Container(
        width: double.infinity,
        color: AppColors.accentBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Text('LESSON',
                style: AppFonts.mono(fontSize: 9, letterSpacing: 0.8, color: AppColors.accent)),
            const SizedBox(width: 8),
            Expanded(child: Text(lesson.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(fontSize: 11, color: AppColors.muted))),
            Text(DateFormat('MMM d').format(lesson.createdDate),
                style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _header({
    required String name,
    required bool planned,
    required int prCount,
    required int lessonsCount,
    required int historyCount,
    required String exerciseId,
    required bool viewingHistory,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: planned ? AppColors.successBg : AppColors.accentBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: planned ? AppColors.success.withValues(alpha: 0.35) : AppColors.accent.withValues(alpha: 0.35)),
                      ),
                      child: Text(planned ? 'PLANNED' : 'UNPLANNED',
                          style: AppFonts.ui(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: planned ? AppColors.success : AppColors.accent)),
                    ),
                    if (prCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                        child: Text('$prCount PR${prCount > 1 ? 's' : ''}',
                            style: AppFonts.ui(
                                fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentText)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(name,
                    style: AppFonts.ui(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: viewingHistory ? AppColors.history : AppColors.primary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pillButton(
                icon: Icons.emoji_objects_outlined,
                label: lessonsCount > 0 ? '$lessonsCount Lessons' : 'Lessons',
                active: lessonsCount > 0,
                onTap: () => showLessonsModal(
                  context,
                  listenable: widget.viewModel.state,
                  lessonsFor: widget.viewModel.lessonsFor,
                  loadLessonsFor: widget.viewModel.loadLessonsFor,
                  addLesson: widget.viewModel.addLesson,
                  toggleLessonPin: widget.viewModel.toggleLessonPin,
                  deleteLesson: widget.viewModel.deleteLesson,
                  exerciseId: exerciseId,
                  exerciseName: name,
                ),
              ),
              if (historyCount > 0) ...[
                const SizedBox(height: 6),
                _pillButton(
                  icon: Icons.history,
                  label: 'History',
                  active: _historyOpen || viewingHistory,
                  onTap: () {
                    if (viewingHistory) {
                      _exitHistory();
                    } else {
                      setState(() => _historyOpen = !_historyOpen);
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: active ? AppColors.accent : AppColors.muted),
            const SizedBox(width: 4),
            Text(label,
                style: AppFonts.mono(
                    fontSize: 9, letterSpacing: 0.4, color: active ? AppColors.accent : AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _historyPicker(List<ExerciseHistorySession> history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          Text('PAST SESSIONS',
              style: AppFonts.mono(fontSize: 8, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final session = history[i];
                return GestureDetector(
                  onTap: () => setState(() {
                    _viewingSession = session;
                    _historyOpen = false;
                  }),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('MMM d').format(session.date),
                            style: AppFonts.mono(fontSize: 10, color: AppColors.history)),
                        const SizedBox(height: 6),
                        Text('${session.sets.length} sets',
                            style: AppFonts.mono(fontSize: 10, color: AppColors.muted)),
                      ],
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

  Widget _historyDetail(ExerciseHistorySession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Past performance for reference.',
            style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 8),
        ...session.sets.map((s) => _DetailHistorySetRow(set: s)),
      ],
    );
  }

  Widget _setsGrid(
    List<WorkoutSet> sets,
    List<int> draftIds,
    String exerciseId,
    int order,
    ExerciseDetail? detail, {
    Set<String> prSetIds = const {},
  }) {
    final isEditing = widget.viewModel.state.value.isEditing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sets.isNotEmpty || draftIds.isNotEmpty)
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
        for (var i = 0; i < sets.length; i++)
          _DetailSetRow(
            key: ValueKey(sets[i].setId),
            viewModel: widget.viewModel,
            exerciseId: exerciseId,
            groupOrder: order,
            displayIndex: i + 1,
            detail: detail,
            set: sets[i],
            readOnly: !isEditing,
            isPr: prSetIds.contains(sets[i].setId),
          ),
        for (var i = 0; i < draftIds.length; i++)
          _DetailSetRow(
            key: ValueKey('draft-${draftIds[i]}'),
            viewModel: widget.viewModel,
            exerciseId: exerciseId,
            groupOrder: order,
            displayIndex: sets.length + i + 1,
            detail: detail,
            draftId: draftIds[i],
            readOnly: false,
          ),
        if (isEditing) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => widget.viewModel.addDraftSet(order),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border, style: BorderStyle.solid),
              ),
              child: Center(
                child: Text('+ ADD SET',
                    style: AppFonts.ui(
                        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _colLabel(String text) =>
      Text(text,
          textAlign: TextAlign.center,
          style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));
}

// ── Read-only history set row ────────────────────────────────────────────────

class _DetailHistorySetRow extends StatelessWidget {
  const _DetailHistorySetRow({required this.set});

  final PastSetRow set;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.historyBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.history.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 26,
              child: Text('${set.setNumber}',
                  textAlign: TextAlign.center,
                  style: AppFonts.mono(fontSize: 11, color: AppColors.muted))),
          Expanded(
            child: Text(
              set.weight != null ? _fmtNum(set.weight!) : '—',
              textAlign: TextAlign.center,
              style: AppFonts.mono(fontSize: 13, color: AppColors.history),
            ),
          ),
          Expanded(
            child: Text(
              set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '—',
              textAlign: TextAlign.center,
              style: AppFonts.mono(fontSize: 13, color: AppColors.history),
            ),
          ),
          Expanded(
            child: Text(
              set.variationName != null ? toProperCase(set.variationName!) : '—',
              textAlign: TextAlign.center,
              style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

// ── Set row (edit-mode is inline; view-mode is read-only) ────────────────────

class _DetailSetRow extends StatefulWidget {
  const _DetailSetRow({
    super.key,
    required this.viewModel,
    required this.exerciseId,
    required this.groupOrder,
    required this.displayIndex,
    required this.detail,
    this.set,
    this.draftId,
    this.readOnly = false,
    this.isPr = false,
  }) : assert(set != null || draftId != null);

  final WorkoutDetailViewModel viewModel;
  final String exerciseId;
  final int groupOrder;
  final int displayIndex;
  final ExerciseDetail? detail;
  final WorkoutSet? set;
  final int? draftId;
  final bool readOnly;
  final bool isPr;

  @override
  State<_DetailSetRow> createState() => _DetailSetRowState();
}

class _DetailSetRowState extends State<_DetailSetRow> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _repsCtrl;
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();
  String? _draftVariationId;
  String? _draftNotes;

  bool get _isDraft => widget.set == null;

  @override
  void initState() {
    super.initState();
    final set = widget.set;
    _weightCtrl = TextEditingController(text: set?.weight != null ? _fmtNum(set!.weight!) : '');
    _repsCtrl = TextEditingController(
        text: set != null && set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '');
    if (!widget.readOnly) {
      _weightFocus.addListener(() {
        if (!_weightFocus.hasFocus) _commit();
      });
      _repsFocus.addListener(() {
        if (!_repsFocus.hasFocus) _commit();
      });
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  static String _fmtNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  Future<void> _commit() async {
    final weightText = _weightCtrl.text.trim();
    final repsText = _repsCtrl.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);
    final reps = repsText.isEmpty ? null : num.tryParse(repsText);

    if (_isDraft) {
      if (reps == null) return;
      await widget.viewModel.commitDraftSet(
        widget.exerciseId,
        widget.groupOrder,
        widget.draftId!,
        variationId: _draftVariationId,
        weight: weight,
        reps: [reps],
        duration: const [],
        notes: _draftNotes?.trim().isEmpty == true ? null : _draftNotes?.trim(),
      );
      return;
    }

    final set = widget.set!;
    final currentWeight = set.weight;
    final currentReps = set.reps.isNotEmpty ? set.reps.first : null;
    if (weight == currentWeight && reps == currentReps) return;
    await widget.viewModel.quickUpdateSet(
      set,
      weight: weight,
      clearWeight: weight == null,
      reps: reps != null ? [reps] : null,
    );
  }

  void _openNotes() {
    showNotesModal(
      context,
      setIndex: widget.displayIndex,
      initialValue: _isDraft ? (_draftNotes ?? '') : (widget.set!.notes ?? ''),
      readOnly: widget.readOnly,
      onSave: (value) {
        if (_isDraft) {
          setState(() => _draftNotes = value);
        } else {
          widget.viewModel.quickUpdateSet(widget.set!,
              notes: value.trim().isEmpty ? null : value.trim(),
              clearNotes: value.trim().isEmpty);
        }
      },
    );
  }

  void _delete() {
    if (_isDraft) {
      widget.viewModel.removeDraftSet(widget.groupOrder, widget.draftId!);
      return;
    }
    final set = widget.set!;
    widget.viewModel.prsForSet(set.setId).then((records) {
      if (!mounted) return;
      if (records.isEmpty) {
        widget.viewModel.deleteSetById(set.setId);
        return;
      }
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('This set holds PRs',
              style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Text(
              '${records.length} PR record${records.length == 1 ? '' : 's'} (${records.map((r) => r.typeLabel).take(4).join(', ')}${records.length > 4 ? ', …' : ''}).\n\nDelete the set only, or also remove its PRs?',
              style: AppFonts.ui(color: AppColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.viewModel.deleteSetKeepingPRs(set.setId);
                },
                child: Text('Set Only',
                    style: AppFonts.ui(color: AppColors.primary, fontWeight: FontWeight.w600))),
            TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.viewModel.deleteSetAndItsPRs(set.setId, set.exerciseId);
                },
                child: Text('Set + PRs',
                    style: AppFonts.ui(color: AppColors.danger, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    });
  }

  void _duplicate() {
    if (_isDraft) return;
    widget.viewModel.duplicateSet(widget.set!);
  }

  Future<void> _handleCreateVariation(String query) async {
    final typed = query.trim();
    final name = typed.isNotEmpty ? typed : await _promptForVariationName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final trimmed = name.trim();

    final exact = widget.viewModel.state.value.allVariations
        .where((v) => v.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;

    String? useExistingId = exact?.variationId;
    if (exact == null) {
      final similar = widget.viewModel.findSimilarVariations(trimmed);
      if (similar.isNotEmpty) {
        final choice = await _showDidYouMeanDialog(trimmed, similar);
        if (choice == null || !mounted) return;
        if (!choice.createNew) useExistingId = choice.existingId;
      }
    }

    final id = await widget.viewModel
        .submitNewVariation(trimmed, exerciseId: widget.exerciseId, useExistingId: useExistingId);
    if (id == null || !mounted) return;
    if (_isDraft) {
      setState(() => _draftVariationId = id);
    } else {
      widget.viewModel.quickUpdateSet(widget.set!, variationId: id);
    }
  }

  Future<({bool createNew, String? existingId})?> _showDidYouMeanDialog(
    String typedName,
    List<({String id, String name, int exerciseCount})> similar,
  ) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Did you mean?', style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in similar)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop((createNew: false, existingId: s.id)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(s.name,
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))),
                        Text('${s.exerciseCount} exercise${s.exerciseCount == 1 ? '' : 's'}',
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop((createNew: true, existingId: null)),
            child: Text('Create "$typedName" anyway',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForVariationName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('New Variation', style: TextStyle(color: AppColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: AppColors.primary),
          decoration: InputDecoration(hintText: 'Variation name', hintStyle: TextStyle(color: AppColors.muted)),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text('Create', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final hasNotes = _isDraft ? (_draftNotes?.trim().isNotEmpty ?? false) : (set!.notes?.isNotEmpty ?? false);
    final variationId = _isDraft ? _draftVariationId : set!.variationId;
    final variationOptions = [
      const DropdownOption<String?>(label: '—', value: null),
      ...(widget.detail?.assignedVariations ?? [])
          .map((v) => DropdownOption<String?>(label: toProperCase(v.name), value: v.variationId)),
    ];

    Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isPr ? AppColors.accentBg : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: widget.isPr ? AppColors.accent : AppColors.border,
            width: widget.isPr ? 1.2 : 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isPr)
                  Text('PR',
                      style: AppFonts.mono(
                          fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.accent))
                else
                  Text('${widget.displayIndex}',
                      style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
                if (hasNotes)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _cell(controller: _weightCtrl, focusNode: _weightFocus)),
          const SizedBox(width: 6),
          Expanded(child: _cell(controller: _repsCtrl, focusNode: _repsFocus)),
          const SizedBox(width: 6),
          Expanded(
            child: widget.readOnly
                ? Text(
                    variationId != null
                        ? toProperCase(set?.variationName ?? '')
                        : '—',
                    textAlign: TextAlign.center,
                    style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
                  )
                : Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: DropdownSelect<String?>(
                      options: variationOptions,
                      value: variationId,
                      compact: true,
                      createNewLabel: 'New Variation',
                      onCreateNew: _handleCreateVariation,
                      onChange: (id) {
                        if (_isDraft) {
                          setState(() => _draftVariationId = id);
                        } else {
                          widget.viewModel.quickUpdateSet(set!, variationId: id, clearVariation: id == null);
                        }
                      },
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: (widget.readOnly && !hasNotes) ? null : _openNotes,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasNotes ? AppColors.accentBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: hasNotes
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.border),
              ),
              child: Icon(Icons.sticky_note_2_outlined,
                  size: 15,
                  color: hasNotes ? AppColors.accent : AppColors.muted),
            ),
          ),
        ],
      ),
    );

    if (!widget.readOnly) {
      row = SwipeActions(
        actions: [
          if (!_isDraft)
            SwipeAction(
              icon: Icons.copy_rounded,
              label: 'Duplicate',
              color: AppColors.accent,
              onTap: _duplicate,
            ),
          SwipeAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.danger,
            onTap: _delete,
          ),
        ],
        child: row,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: row,
    );
  }

  Widget _cell({required TextEditingController controller, required FocusNode focusNode}) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: widget.readOnly,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
        style: AppFonts.mono(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.primary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: '—',
          hintStyle: AppFonts.mono(fontSize: 14, color: AppColors.muted.withValues(alpha: 0.6)),
          filled: true,
          fillColor: widget.readOnly ? Colors.transparent : AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: widget.readOnly ? Colors.transparent : AppColors.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

// ── Add Exercise Modal ───────────────────────────────────────────────────────

class _DetailAddExerciseContent extends StatefulWidget {
  const _DetailAddExerciseContent({required this.viewModel});

  final WorkoutDetailViewModel viewModel;

  @override
  State<_DetailAddExerciseContent> createState() => _DetailAddExerciseContentState();
}

class _DetailAddExerciseContentState extends State<_DetailAddExerciseContent> {
  String _query = '';

  List<MapEntry<String, String>> get _filtered {
    return widget.viewModel.state.value.exerciseDetailMap.entries
        .where((e) => toProperCase(e.value.name).toLowerCase().contains(_query.toLowerCase()))
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
  }

  bool get _canCreate =>
      _query.trim().length > 1 &&
      !widget.viewModel.state.value.exerciseDetailMap.values
          .any((e) => e.name.toLowerCase() == _query.trim().toLowerCase());

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
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Add exercise',
                      style: AppFonts.ui(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
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
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
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
              child: ValueListenableBuilder<WorkoutDetailState>(
                valueListenable: widget.viewModel.state,
                builder: (context, state, _) => ListView(
                  shrinkWrap: true,
                  children: [
                    ..._filtered.map((e) => _resultRow(e.value, () => _pick(e.key))),
                    if (_canCreate)
                      _resultRow('+ Create "${_query.trim()}"',
                          state.newExCreating ? null : _createNew,
                          accent: true),
                    if (_filtered.isEmpty && !_canCreate && _query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Center(
                            child: Text('No exercises found',
                                style: AppFonts.ui(fontSize: 13, color: AppColors.muted))),
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
                color: accent ? AppColors.accent.withValues(alpha: 0.35) : AppColors.border),
          ),
          child: Text(label,
              style: AppFonts.ui(
                  fontSize: 14,
                  fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                  color: accent ? AppColors.accent : AppColors.primary)),
        ),
      ),
    );
  }
}
