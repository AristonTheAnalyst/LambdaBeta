import 'package:flutter/material.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_set.dart';
import '../../../data/models/session_set.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'add_exercise_modal.dart';
import 'lessons_modal.dart';

/// The live session's exercise card — a thin adapter over the shared
/// [SessionExerciseCard] that maps the [SessionViewModel]'s mutable state
/// into the card's plain inputs and bridge callbacks.
class LiveExerciseCard extends StatelessWidget {
  const LiveExerciseCard({
    super.key,
    required this.vm,
    required this.slot,
    this.onRemoveExercise,
  });

  final SessionViewModel vm;
  final SessionExerciseSlot slot;

  /// Fired by the selector's hold-to-delete — the screen shows its own
  /// remove-exercise confirmation.
  final VoidCallback? onRemoveExercise;

  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static double? _parseWeight(String? t) =>
      t == null || t.isEmpty ? null : double.tryParse(t);

  static List<num>? _parseReps(String? t) {
    final r = t == null || t.isEmpty ? null : num.tryParse(t);
    return r == null ? null : [r];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final exerciseId = slot.activeExerciseId;
        final name = toProperCase(vm.exerciseDisplayName(exerciseId));
        final history = vm.historyFor(exerciseId);
        final realSets =
            vm.sets.where((s) => s.exerciseId == exerciseId).toList()
              ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        final draftIds = vm.draftSlotsByExercise[exerciseId] ?? const <int>[];
        final plannedSets = vm.plannedSetsByExercise[exerciseId] ?? const [];

        // The pinned lesson shows right under the exercise — pinning is what
        // decides whether a note appears there.
        Lesson? pinnedLesson;
        for (final l in vm.lessonsFor(exerciseId)) {
          if (l.pinned) {
            pinnedLesson = l;
            break;
          }
        }

        void openLessonsModal() => showLessonsModal(
          context,
          listenable: vm,
          lessonsFor: vm.lessonsFor,
          loadLessonsFor: vm.loadLessonsFor,
          addLesson: vm.addLesson,
          toggleLessonPin: vm.toggleLessonPin,
          deleteLesson: vm.deleteLesson,
          updateLesson: vm.updateLessonText,
          exerciseId: exerciseId,
          exerciseName: name,
          sessionId: vm.currentWorkoutId,
        );

        final variationOptions = [
          const DropdownOption<String?>(label: 'No Variation', value: null),
          ...vm.variationsByRecency.map(
            (v) => DropdownOption<String?>(label: v.name, value: v.variationId),
          ),
        ];
        final allVariations = [
          for (final v in vm.allVariations) (id: v.variationId, name: v.name),
        ];

        // A planned WEIGHT that is strictly a number becomes the actual
        // value — prefilled so committing it is automatic. Ranges stay
        // ghosts (the row shows them as hints).
        String weightSeed(SessionSet? set, PlannedSessionSet? planned) {
          final w = set?.weight;
          if (w != null) return _fmtNum(w);
          final plannedWeight = planned?.targetWeight;
          final numeric = plannedWeight == null
              ? null
              : double.tryParse(plannedWeight);
          return numeric != null ? _fmtNum(numeric) : '';
        }

        List<Widget> rows = [];
        for (var i = 0; i < realSets.length; i++) {
          final set = realSets[i];
          final planned = i < plannedSets.length ? plannedSets[i] : null;
          rows.add(
            SessionSetRow(
              key: ValueKey(set.sessionSetId),
              mode: SetRowMode.live,
              exerciseId: exerciseId,
              displayIndex: i + 1,
              isDraft: false,
              initialWeightText: weightSeed(set, planned),
              initialRepsText: set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '',
              initialVariationId: set.variationId,
              initialVariationName: set.variationName,
              initialNotes: set.notes,
              hasNotes: set.notes?.isNotEmpty ?? false,
              plannedTarget: planned,
              isPr: vm.isPrSet(set.sessionSetId),
              onCommit: (isDraft, v) async {
                if (!isDraft) {
                  await vm.updateSetField(
                    set,
                    weight: _parseWeight(v.weight),
                    clearWeight: v.weight == null,
                    reps: _parseReps(v.reps),
                  );
                }
              },
              onVariationChanged: (id) => vm.updateSetField(
                set,
                variationId: id,
                clearVariation: id == null,
              ),
              onNotesSave: (v) => vm.updateSetField(
                set,
                notes: v.trim().isEmpty ? null : v.trim(),
                clearNotes: v.trim().isEmpty,
              ),
              onDelete: () => vm.deleteSetById(set.sessionSetId),
              onDuplicate: () => vm.duplicateSet(set),
              variationOptions: variationOptions,
              allVariations: allVariations,
              findSimilarVariations: vm.findSimilarVariations,
              submitNewVariation: vm.submitNewVariation,
            ),
          );
        }
        for (var i = 0; i < draftIds.length; i++) {
          final draftId = draftIds[i];
          final plannedIndex = realSets.length + i;
          final planned = plannedIndex < plannedSets.length
              ? plannedSets[plannedIndex]
              : null;
          rows.add(
            SessionSetRow(
              key: ValueKey('draft-$draftId'),
              mode: SetRowMode.live,
              exerciseId: exerciseId,
              displayIndex: realSets.length + i + 1,
              isDraft: true,
              initialWeightText: weightSeed(null, planned),
              initialRepsText: '',
              initialVariationId: null,
              hasNotes: false,
              plannedTarget: planned,
              onCommit: (isDraft, v) async {
                if (isDraft) {
                  await vm.commitDraftSet(
                    exerciseId,
                    draftId,
                    variationId: v.variationId,
                    weight: _parseWeight(v.weight),
                    reps: _parseReps(v.reps),
                    notes: v.notes,
                  );
                }
              },
              onVariationChanged: (_) {},
              onNotesSave: (_) {},
              onDelete: () async => vm.removeDraftSet(exerciseId, draftId),
              onDuplicate: () {},
              variationOptions: variationOptions,
              allVariations: allVariations,
              findSimilarVariations: vm.findSimilarVariations,
              submitNewVariation: vm.submitNewVariation,
            ),
          );
        }

        return SessionExerciseCard(
          exerciseNames: [
            for (final s in vm.exerciseSlots)
              toProperCase(vm.exerciseDisplayName(s.exerciseIds.first)),
          ],
          activeIndex: vm.activeSlotIndex,
          onSelect: vm.tapTab,
          onMove: (i, dir) => vm.reorderExercises(i, i + dir),
          onAdd: () => showAddExerciseModal(context, vm: vm),
          onDeleteRequest:
              onRemoveExercise ?? () => vm.removeExerciseSlot(vm.activeSlotIndex),
          pinnedLesson: pinnedLesson != null
              ? PinnedLessonData(
                  text: pinnedLesson.text,
                  date: pinnedLesson.createdDate,
                )
              : null,
          onPinnedLessonTap: openLessonsModal,
          // Session-scoped count — past sessions' lessons stay visible in
          // the modal and the pinned bar, but don't inflate the button's
          // number.
          lessonsCount: vm.lessonsThisSession(exerciseId).length,
          onLessonsTap: openLessonsModal,
          // PRs pill stays greyed until it gets its own surface (one-screen
          // placeholder state — see the PR breakdown in the stats bar).
          prCount: 0,
          onPrTap: null,
          planned: slot.planned,
          rows: rows,
          onAddSet: () => vm.addDraftSet(exerciseId),
          history: history,
          historyRowBuilder: (s) => HistorySetRow(
            set: s,
            editable: true,
            editConfirmed: vm.historyEditConfirmed,
            onEditConfirmed: vm.confirmHistoryEdit,
            onCommit: (w, r) async {
              final weight = w == null || w.isEmpty ? null : double.tryParse(w);
              final reps = r == null || r.isEmpty ? null : num.tryParse(r);
              await vm.updateHistoricalSetField(
                s,
                weight: weight,
                clearWeight: weight == null,
                reps: reps != null ? [reps] : null,
              );
            },
          ),
          // A fresh history session must re-earn the edit confirm gate.
          onHistorySessionSelected: (_) => vm.historyEditConfirmed = false,
        );
      },
    );
  }
}
