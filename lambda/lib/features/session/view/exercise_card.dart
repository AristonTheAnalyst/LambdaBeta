import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/workout_set.dart';
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
        final name = toProperCase(detail?.name ?? '');
        final isSuperset = widget.slot.type == SessionSlotType.superset;
        final prCount = vm.prCountFor(exerciseId);
        final lessons = vm.lessonsFor(exerciseId);
        final history = vm.historyFor(exerciseId);
        final realSets = vm.sets.where((s) => s.exerciseId == exerciseId).toList()
          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        final draftIds = vm.draftSlotsByExercise[exerciseId] ?? const <int>[];
        final plannedSets = vm.plannedSetsByExercise[exerciseId] ?? const [];
        final viewingHistory = _viewingSession != null;
        final featuredLesson = lessons.isEmpty
            ? null
            : (lessons.where((l) => l.pinned).isNotEmpty
                ? lessons.firstWhere((l) => l.pinned)
                : lessons.last);

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
              else if (isSuperset)
                _supersetBar(widget.slot, vm)
              else if (featuredLesson != null)
                _lessonBar(featuredLesson, exerciseId, name),
              _header(
                name: name,
                planned: widget.slot.planned,
                prCount: viewingHistory ? 0 : prCount,
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

  /// The superset's exercise switcher — tappable pills, one per exercise in
  /// the superset, so jumping to a specific one is an explicit tap rather
  /// than the old "tap the tab bar chip again to cycle" gesture.
  Widget _supersetBar(SessionExerciseSlot slot, SessionViewModel vm) {
    return Container(
      color: AppColors.accentBg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.hexagon_outlined, size: 12, color: AppColors.accent),
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

  Widget _lessonBar(SessionLesson lesson, String exerciseId, String exerciseName) {
    return GestureDetector(
      onTap: () => showLessonsModal(context, vm: widget.vm, exerciseId: exerciseId, exerciseName: exerciseName),
      child: Container(
        width: double.infinity,
        color: AppColors.accentBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Text(lesson.pinned ? '📌 LESSON' : 'LESSON',
                style: AppFonts.mono(fontSize: 9, letterSpacing: 0.8, color: AppColors.accent)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(lesson.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
            ),
            Text(lesson.date, style: AppFonts.mono(fontSize: 9, color: AppColors.muted)),
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
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pillButton(
                icon: Icons.emoji_objects_outlined,
                label: lessonsCount > 0 ? '$lessonsCount Lessons' : 'Lessons',
                active: lessonsCount > 0,
                color: AppColors.accent,
                onTap: () => showLessonsModal(context, vm: widget.vm, exerciseId: exerciseId, exerciseName: name),
              ),
              if (historyCount > 0) ...[
                const SizedBox(height: 6),
                _pillButton(
                  icon: Icons.history,
                  label: 'History',
                  active: _historyOpen || viewingHistory,
                  color: AppColors.history,
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

  Widget _pillButton(
      {required IconData icon, required String label, required bool active, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color.withValues(alpha: 0.3) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: active ? color : AppColors.muted),
            const SizedBox(width: 4),
            Text(label,
                style: AppFonts.mono(
                    fontSize: 9, letterSpacing: 0.4, color: active ? color : AppColors.muted)),
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
        Text('Read-only — from a completed workout.',
            style: AppFonts.ui(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 8),
        ...session.sets.map((s) => Container(
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
                      child: Text('${s.setNumber}',
                          textAlign: TextAlign.center,
                          style: AppFonts.mono(fontSize: 11, color: AppColors.muted))),
                  Expanded(
                    child: Text(
                      s.weight != null ? '${s.weight}kg' : '—',
                      textAlign: TextAlign.center,
                      style: AppFonts.mono(fontSize: 13, color: AppColors.history),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.reps.isNotEmpty ? s.reps.join(', ') : (s.duration.isNotEmpty ? '${s.duration.join(', ')}s' : '—'),
                      textAlign: TextAlign.center,
                      style: AppFonts.mono(fontSize: 13, color: AppColors.history),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.variationName != null ? toProperCase(s.variationName!) : '—',
                      textAlign: TextAlign.center,
                      style: AppFonts.ui(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _setsGrid(
    SessionViewModel vm,
    String exerciseId,
    List<WorkoutSet> realSets,
    List<int> draftIds,
    List plannedSets,
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
        for (var i = 0; i < realSets.length; i++)
          SessionSetRow(
            key: ValueKey(realSets[i].setId),
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
      Text(text, textAlign: TextAlign.start, style: AppFonts.mono(fontSize: 8, letterSpacing: 0.6, color: AppColors.muted));
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
