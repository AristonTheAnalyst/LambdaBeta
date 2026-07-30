import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_set.dart';
import '../../../data/models/planned_workout.dart';
import '../../../data/models/workout_set.dart' show PastSetRow;
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../session/model/session_local_state.dart' show ExerciseHistorySession;
import '../../session/view/lessons_modal.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_set_row.dart';

const _dayOfWeekOptions = [
  SegmentOption<int?>(label: 'Mon', value: 1),
  SegmentOption<int?>(label: 'Tue', value: 2),
  SegmentOption<int?>(label: 'Wed', value: 3),
  SegmentOption<int?>(label: 'Thu', value: 4),
  SegmentOption<int?>(label: 'Fri', value: 5),
  SegmentOption<int?>(label: 'Sat', value: 6),
  SegmentOption<int?>(label: 'Sun', value: 7),
];

/// Full-screen planned-workout editor that mirrors the active-session UX:
/// tabbed by exercise, inline editable set grid (PlanSetRow), auto-commit on
/// blur, Lessons/History per exercise, swipe-to-reveal delete/duplicate.
/// Pushed via [program_detail_screen.dart] on create or edit.
class PlanWorkoutScreen extends StatefulWidget {
  const PlanWorkoutScreen({super.key, required this.viewModel, this.workout});

  final ProgramDetailViewModel viewModel;
  final PlannedWorkout? workout; // null = new workout

  @override
  State<PlanWorkoutScreen> createState() => _PlanWorkoutScreenState();
}

class _PlanWorkoutScreenState extends State<PlanWorkoutScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  final _nameFocus = FocusNode();
  final _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = widget.viewModel.state.value;
    _nameCtrl = TextEditingController(text: s.workoutNameDraft);
    _notesCtrl = TextEditingController(text: s.workoutNotesDraft);
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) widget.viewModel.commitWorkoutName();
    });
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) widget.viewModel.commitWorkoutNotes();
    });
    widget.viewModel.loadHistoryIfNeeded();
    if (widget.workout != null) {
      widget.viewModel.openEditWorkout(widget.workout!);
    } else {
      widget.viewModel.createWorkoutAndOpen();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _notesFocus.dispose();
    // Final commit on dispose in case the user navigates back without blurring
    widget.viewModel.commitWorkoutName();
    widget.viewModel.commitWorkoutNotes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgramDetailState>(
      valueListenable: widget.viewModel.state,
      builder: (context, state, _) {
        final workout = state.editingWorkout;
        if (workout == null) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              _editableHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _notesField(state.workoutNotesDraft),
                      if (state.isCalendarMode) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text('Day of week',
                            style: AppFonts.ui(
                                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primary)),
                        const SizedBox(height: 6),
                        SegmentedControl<int?>(
                          options: _dayOfWeekOptions,
                          value: state.workoutDayOfWeekDraft,
                          onChange: (v) => widget.viewModel.commitWorkoutDayOfWeek(v),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _PlanStatsBar(
                        setCount: state.workoutPlannedSets.length,
                        exerciseCount: state.workoutExerciseSlots.length,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (state.workoutSetsLoading)
                        Center(
                            child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: CircularProgressIndicator(color: AppColors.accent),
                        ))
                      else ...[
                        _PlanExerciseTabBar(
                          slots: state.workoutExerciseSlots,
                          activeIndex: state.activeSlotIndex,
                          setCounts: state.workoutExerciseSlots
                              .map((slot) => state.plannedSetsFor(slot.exerciseSequenceOrder).length)
                              .toList(),
                          exerciseNames: state.workoutExerciseSlots.map((slot) {
                            final detail = state.exerciseDetailMap[slot.exerciseId];
                            return toProperCase(detail?.name ?? '');
                          }).toList(),
                          onTap: (i) => widget.viewModel.tapTab(i),
                          onAdd: _showAddExercise,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (state.activeSlot != null)
                          _PlanExerciseCard(
                            viewModel: widget.viewModel,
                            slot: state.activeSlot!,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _editableHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(left: 16,
              child: GestureDetector(
                onTap: () {
                  widget.viewModel.commitWorkoutName();
                  widget.viewModel.commitWorkoutNotes();
                  widget.viewModel.closeWorkoutEditor();
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.accent),
              ),
            ),
            Positioned(
              left: 88,
              right: 88,
              top: 0,
              bottom: 0,
              child: Center(
                child: TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.words,
                  style: AppFonts.ui(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.primary),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Workout name',
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onChanged: widget.viewModel.setWorkoutNameDraft,
                ),
              ),
            ),
            Positioned(right: 16,
              child: GestureDetector(
                onTap: _confirmDelete,
                child: Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesField(String draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session Notes',
            style: AppFonts.ui(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          focusNode: _notesFocus,
          textCapitalization: TextCapitalization.sentences,
          style: AppFonts.ui(fontSize: 15, color: AppColors.primary),
          decoration: InputDecoration(
            hintText: 'What to focus on…',
            hintStyle: AppFonts.ui(color: AppColors.muted),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
          onChanged: widget.viewModel.setWorkoutNotesDraft,
        ),
      ],
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Workout',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Remove this planned workout and its sets?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.viewModel.deleteWorkout();
              Navigator.of(context, rootNavigator: true).pop();
            },
            child: Text('Delete',
                style: AppFonts.ui(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddExercise() {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _AddExerciseContent(viewModel: widget.viewModel),
    );
  }
}

// ── Stats Bar ────────────────────────────────────────────────────────────────

class _PlanStatsBar extends StatelessWidget {
  const _PlanStatsBar({required this.setCount, required this.exerciseCount});

  final int setCount;
  final int exerciseCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: _tile(label: 'SETS', value: '$setCount')),
          _divider(),
          Expanded(child: _tile(label: 'EXERCISES', value: '$exerciseCount')),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, color: AppColors.border);

  Widget _tile({required String label, required String value}) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: AppFonts.mono(fontSize: 8, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value,
              style: AppFonts.mono(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ── Exercise Tab Bar ──────────────────────────────────────────────────────────

class _PlanExerciseTabBar extends StatelessWidget {
  const _PlanExerciseTabBar({
    required this.slots,
    required this.activeIndex,
    required this.setCounts,
    required this.exerciseNames,
    required this.onTap,
    required this.onAdd,
  });

  final List<PlanExerciseSlot> slots;
  final int activeIndex;
  final List<int> setCounts;
  final List<String> exerciseNames;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < slots.length; i++) ...[
                  _TabChip(
                    label: exerciseNames.length > i ? exerciseNames[i] : '',
                    isActive: i == activeIndex,
                    setCount: setCounts.length > i ? setCounts[i] : 0,
                    onTap: () => onTap(i),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(Icons.add, size: 16, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isActive,
    required this.setCount,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final int setCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentBg : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppFonts.ui(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppColors.accent : AppColors.primary)),
            if (setCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$setCount',
                    style: AppFonts.mono(fontSize: 10, color: AppColors.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Exercise Card ─────────────────────────────────────────────────────────────

class _PlanExerciseCard extends StatefulWidget {
  const _PlanExerciseCard({required this.viewModel, required this.slot});

  final ProgramDetailViewModel viewModel;
  final PlanExerciseSlot slot;

  @override
  State<_PlanExerciseCard> createState() => _PlanExerciseCardState();
}

class _PlanExerciseCardState extends State<_PlanExerciseCard> {
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
    final order = widget.slot.exerciseSequenceOrder;
    final detail = s.exerciseDetailMap[exerciseId];
    final name = toProperCase(detail?.name ?? '');
    final lessons = vm.lessonsFor(exerciseId);
    final history = vm.historyFor(exerciseId);
    final sets = s.plannedSetsFor(order);
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
                : _setsGrid(sets, draftIds, exerciseId, order, detail),
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
          GlassButton(
              label: 'Back', color: AppColors.history, compact: true, onPressed: _exitHistory),
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
            Expanded(
              child: Text(lesson.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
            ),
            Text(DateFormat('MMM d').format(lesson.createdDate),
                style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _header({
    required String name,
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
            child: Text(name,
                style: AppFonts.ui(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: viewingHistory ? AppColors.history : AppColors.primary)),
          ),
          const SizedBox(width: AppSpacing.sm),
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
          border: Border.all(
              color: active ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
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
              style:
                  AppFonts.mono(fontSize: 8, letterSpacing: 0.8, color: AppColors.muted)),
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
        ...session.sets.map((s) => _PlanHistorySetRow(set: s)),
      ],
    );
  }

  Widget _setsGrid(
    List<PlannedSet> sets,
    List<int> draftIds,
    String exerciseId,
    int order,
    dynamic detail,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
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
          PlanSetRow(
            key: ValueKey(sets[i].plannedSetId),
            viewModel: widget.viewModel,
            exerciseId: exerciseId,
            exerciseSequenceOrder: order,
            displayIndex: i + 1,
            detail: detail,
            set: sets[i],
          ),
        for (var i = 0; i < draftIds.length; i++)
          PlanSetRow(
            key: ValueKey('draft-${draftIds[i]}'),
            viewModel: widget.viewModel,
            exerciseId: exerciseId,
            exerciseSequenceOrder: order,
            displayIndex: sets.length + i + 1,
            detail: detail,
            draftId: draftIds[i],
          ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => widget.viewModel.addDraftPlannedSet(order),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.muted)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _colLabel(String text) =>
      Text(text,
          textAlign: TextAlign.start,
          style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));
}

// ── Read-only history set row ──────────────────────────────────────────────────

class _PlanHistorySetRow extends StatelessWidget {
  const _PlanHistorySetRow({required this.set});

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

// ── Add Exercise Modal ────────────────────────────────────────────────────────

class _AddExerciseContent extends StatefulWidget {
  const _AddExerciseContent({required this.viewModel});

  final ProgramDetailViewModel viewModel;

  @override
  State<_AddExerciseContent> createState() => _AddExerciseContentState();
}

class _AddExerciseContentState extends State<_AddExerciseContent> {
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
    widget.viewModel.addPlannedExerciseGroup(exerciseId);
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
                      style: AppFonts.ui(
                          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
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
              child: ValueListenableBuilder<ProgramDetailState>(
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
