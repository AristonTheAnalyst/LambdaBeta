import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session_set.dart';
import '../../../shared/widgets/glass_button.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';
import 'session_set_row.dart';

class ExerciseCard extends StatefulWidget {
  const ExerciseCard({super.key, required this.vm, required this.slot});

  final SessionViewModel vm;
  final SessionExerciseSlot slot;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard> {
  bool _historyOpen = false;
  ExerciseHistorySession? _viewingSession;

  void _exitHistory() => setState(() {
        _historyOpen = false;
        _viewingSession = null;
      });

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final exerciseId = widget.slot.activeExerciseId;
        final detail = vm.exerciseDetailMap[exerciseId];
        final name = toProperCase(vm.exerciseDisplayName(exerciseId));
        final isSuperset = widget.slot.type == SessionSlotType.superset;
        final lessons = vm.lessonsFor(exerciseId);
        final history = vm.historyFor(exerciseId);
        final realSets = vm.sets.where((s) => s.exerciseId == exerciseId).toList()
          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        final draftIds = vm.draftSlotsByExercise[exerciseId] ?? const <int>[];
        final plannedSets = vm.plannedSetsByExercise[exerciseId] ?? const [];
        final viewingHistory = _viewingSession != null;
        // The banner shows the pinned lesson only — pinning is what decides
        // whether a note appears at the top of the exercise card.
        Lesson? featuredLesson;
        for (final l in lessons) {
          if (l.pinned) {
            featuredLesson = l;
            break;
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: widget.slot.planned
                  ? AppColors.planned.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (viewingHistory)
                _historyBanner(_viewingSession!)
              else if (isSuperset)
                _supersetBar(widget.slot, vm)
              else if (featuredLesson != null)
                _lessonBar(featuredLesson, exerciseId, name),
              _header(
                name: name,
                planned: widget.slot.planned,
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
                    : _setsGrid(vm, exerciseId, realSets, draftIds, plannedSets, detail),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _historyBanner(ExerciseHistorySession session) {
    return Container(
      color: AppColors.surfaceHigh,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Viewing — ${DateFormat('MMM d').format(session.date)}',
                style: AppFonts.mono(fontSize: 9, letterSpacing: 0.8, color: AppColors.muted)),
          ),
          GlassButton(label: 'Back', color: AppColors.primary, compact: true, onPressed: _exitHistory),
        ],
      ),
    );
  }

  /// The superset's exercise switcher — tappable pills, one per exercise in
  /// the superset, so jumping to a specific one is an explicit tap rather
  /// than the old "tap the tab bar chip again to cycle" gesture.
  Widget _supersetBar(SessionExerciseSlot slot, SessionViewModel vm) {
    return Container(
      color: AppColors.accentBg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.hexagon_outlined, size: 12, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < slot.exerciseIds.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 13, color: AppColors.muted),
                      ),
                    _SupersetPill(
                      label: toProperCase(vm.exerciseDetailMap[slot.exerciseIds[i]]?.name ?? ''),
                      isActive: i == slot.activeIndex,
                      onTap: () => vm.setSupersetIndex(slot, i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lessonBar(Lesson lesson, String exerciseId, String exerciseName) {
    return GestureDetector(
      onTap: () => showLessonsModal(
              context,
              listenable: widget.vm,
              lessonsFor: widget.vm.lessonsFor,
              loadLessonsFor: widget.vm.loadLessonsFor,
              addLesson: widget.vm.addLesson,
              toggleLessonPin: widget.vm.toggleLessonPin,
              deleteLesson: widget.vm.deleteLesson,
              exerciseId: exerciseId,
              exerciseName: exerciseName,
            ),
      child: Container(
        width: double.infinity,
        color: AppColors.accentBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lesson.pinned) ...[
                  Icon(Icons.push_pin, size: 10, color: AppColors.accent),
                  const SizedBox(width: 4),
                ],
                Text('LESSON',
                    style: AppFonts.mono(
                        fontSize: 9, letterSpacing: 0.8, color: AppColors.accent)),
              ],
            ),
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
    required bool planned,
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

                const SizedBox(height: 6),
                Text(name,
                    style: AppFonts.ui(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pillButton(
                icon: Icons.menu_book_outlined,
                label: lessonsCount > 0 ? '$lessonsCount Lessons' : 'Lessons',
                active: lessonsCount > 0,
                color: AppColors.accent,
                onTap: () => showLessonsModal(
                    context,
                    listenable: widget.vm,
                    lessonsFor: widget.vm.lessonsFor,
                    loadLessonsFor: widget.vm.loadLessonsFor,
                    addLesson: widget.vm.addLesson,
                    toggleLessonPin: widget.vm.toggleLessonPin,
                    deleteLesson: widget.vm.deleteLesson,
                    exerciseId: exerciseId,
                    exerciseName: name,
                  ),
              ),
              const SizedBox(width: 6),
              _pillButton(
                icon: Icons.history,
                label: 'History',
                active: _historyOpen || viewingHistory,
                color: AppColors.primary,
                enabled: historyCount > 0,
                onTap: historyCount == 0
                    ? null
                    : () {
                        if (viewingHistory) {
                          _exitHistory();
                        } else {
                          setState(() => _historyOpen = !_historyOpen);
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton(
      {required IconData icon,
      required String label,
      required bool active,
      required Color color,
      required VoidCallback? onTap,
      bool enabled = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? color.withValues(alpha: 0.3) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: enabled
                    ? (active ? color : AppColors.muted)
                    : AppColors.muted.withValues(alpha: 0.4)),
            const SizedBox(width: 5),
            Text(label,
                style: AppFonts.mono(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: enabled
                        ? (active ? color : AppColors.muted)
                        : AppColors.muted.withValues(alpha: 0.4))),
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
          Text('PAST SESSIONS', style: AppFonts.mono(fontSize: 8, letterSpacing: 0.8, color: AppColors.muted)),
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
                    widget.vm.historyEditConfirmed = false;
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
                            style: AppFonts.mono(fontSize: 10, color: AppColors.muted)),
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
        Text('From a completed workout — tap a value to edit.',
            style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 8),
        ...session.sets.map((s) => _HistorySetRow(vm: widget.vm, set: s)),
      ],
    );
  }

  Widget _setsGrid(
    SessionViewModel vm,
    String exerciseId,
    List<SessionSet> realSets,
    List<int> draftIds,
    List plannedSets,
    dynamic detail,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        for (var i = 0; i < realSets.length; i++)
          SessionSetRow(
            key: ValueKey(realSets[i].sessionSetId),
            vm: vm,
            exerciseId: exerciseId,
            displayIndex: i + 1,
            detail: detail,
            set: realSets[i],
            plannedTarget: i < plannedSets.length ? plannedSets[i] : null,
          ),
        for (var i = 0; i < draftIds.length; i++)
          SessionSetRow(
            key: ValueKey('draft-${draftIds[i]}'),
            vm: vm,
            exerciseId: exerciseId,
            displayIndex: realSets.length + i + 1,
            detail: detail,
            draftId: draftIds[i],
            plannedTarget: (realSets.length + i) < plannedSets.length ? plannedSets[realSets.length + i] : null,
          ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => vm.addDraftSet(exerciseId),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border, style: BorderStyle.solid),
            ),
            child: Center(
              child: Text('+ ADD SET',
                  style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _colLabel(String text) =>
      Text(text, textAlign: TextAlign.center, style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));
}

class _SupersetPill extends StatelessWidget {
  const _SupersetPill({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
        ),
        child: Text(label,
            style: AppFonts.mono(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? AppColors.accent : AppColors.muted)),
      ),
    );
  }
}

/// One row in the history viewer's set list. Weight/reps are editable, but
/// gated behind a one-time-per-viewing "you're editing past data" confirm —
/// fields render read-only (`TextField.readOnly`) until `vm.historyEditConfirmed`
/// flips true, at which point a rebuild (triggered by the ancestor
/// `ListenableBuilder` in `ExerciseCard.build`) makes them genuinely
/// editable. Duration-only sets and variation stay display-only — editing
/// those wasn't requested.
class _HistorySetRow extends StatefulWidget {
  const _HistorySetRow({required this.vm, required this.set});

  final SessionViewModel vm;
  final PastSetRow set;

  @override
  State<_HistorySetRow> createState() => _HistorySetRowState();
}

class _HistorySetRowState extends State<_HistorySetRow> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _repsCtrl;
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = widget.set;
    _weightCtrl = TextEditingController(text: s.weight != null ? _fmtNum(s.weight!) : '');
    _repsCtrl =
        TextEditingController(text: s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '');
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) _commit();
    });
    _repsFocus.addListener(() {
      if (!_repsFocus.hasFocus) _commit();
    });
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
    final s = widget.set;
    final currentWeight = s.weight;
    final currentReps = s.reps.isNotEmpty ? s.reps.first : null;
    if (weight == currentWeight && reps == currentReps) return;
    await widget.vm.updateHistoricalSetField(
      s,
      weight: weight,
      clearWeight: weight == null,
      reps: reps != null ? [reps] : null,
    );
  }

  Future<void> _requestEdit(FocusNode focus) async {
    if (widget.vm.historyEditConfirmed) {
      focus.requestFocus();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Edit past data?', style: TextStyle(color: AppColors.primary)),
        content: Text(
          "You're about to update past data — this changes your historical record for this workout, including any PRs based on it.",
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Continue', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.vm.confirmHistoryEdit();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.set;
    final confirmed = widget.vm.historyEditConfirmed;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 26,
              child: Text('${s.setNumber}',
                  textAlign: TextAlign.center,
                  style: AppFonts.mono(fontSize: 11, color: AppColors.muted))),
          Expanded(child: _editableCell(_weightCtrl, _weightFocus, confirmed)),
          Expanded(child: _editableCell(_repsCtrl, _repsFocus, confirmed)),
          Expanded(
            child: Text(
              s.variationName != null ? toProperCase(s.variationName!) : '—',
              textAlign: TextAlign.center,
              style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableCell(TextEditingController ctrl, FocusNode focus, bool confirmed) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      readOnly: !confirmed,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
      onTap: () => _requestEdit(focus),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
