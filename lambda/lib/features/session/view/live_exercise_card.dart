import 'package:flutter/material.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
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
        // Rows bound to an active draft slot render as the draft row, not
        // as a real row — they'd otherwise appear twice.
        final realSets = vm.sets
            .where(
              (s) =>
                  s.exerciseId == exerciseId &&
                  !vm.isDraftBoundRow(s.sessionExerciseSetId),
            )
            .toList()
          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        final draftIds = vm.draftSlotsByExercise[exerciseId] ?? const <int>[];

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

        // Id-anchored pairing — a row's ghost target is the template row it
        // was materialized from (parent_set_id), immune to insert/delete
        // re-shuffling. Planned values are hints only, never prefilled into
        // the actual-value cells.
        final plannedById = vm.plannedSetById;
        List<Widget> rows = [];
        for (var i = 0; i < realSets.length; i++) {
          final set = realSets[i];
          final planned = plannedById[set.plannedSetId];
          rows.add(
            SessionSetRow(
              key: ValueKey(set.sessionExerciseSetId),
              mode: SetRowMode.live,
              exerciseId: exerciseId,
              displayIndex: i + 1,
              isDraft: false,
              initialWeightText: set.weight != null ? _fmtNum(set.weight!) : '',
              initialRepsText: set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '',
              initialVariationId: set.variationId,
              initialVariationName: set.variationName,
              initialNotes: set.notes,
              hasNotes: set.notes?.isNotEmpty ?? false,
              plannedTarget: planned,
              isPr: vm.isPrSet(set.sessionExerciseSetId),
              onRegisterCommit: vm.registerCommitHandle,
              onUnregisterCommit: vm.unregisterCommitHandle,
              onCommit: (isDraft, v) async {
                if (!isDraft) {
                  await vm.updateSetField(
                    set,
                    weight: _parseWeight(v.weight),
                    clearWeight: v.weight == null,
                    reps: _parseReps(v.reps),
                    // First real commit adopts the planned variation — the
                    // draft path does the same, so a logged row keeps its
                    // template's variation instead of silently losing it.
                    variationId: set.variationId == null &&
                            planned?.variationId != null
                        ? planned!.variationId
                        : null,
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
                variationId: set.variationId == null &&
                        planned?.variationId != null
                    ? planned!.variationId
                    : null,
              ),
              onDelete: () => vm.deleteSetById(set.sessionExerciseSetId),
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
          rows.add(
            SessionSetRow(
              key: ValueKey('draft-$draftId'),
              mode: SetRowMode.live,
              exerciseId: exerciseId,
              displayIndex: realSets.length + i + 1,
              isDraft: true,
              initialWeightText: '',
              initialRepsText: '',
              initialVariationId: null,
              hasNotes: false,
              // Freestyle drafts carry no planned target — planned rows are
              // materialized as real sets at session start.
              plannedTarget: null,
              onRegisterCommit: vm.registerCommitHandle,
              onUnregisterCommit: vm.unregisterCommitHandle,
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
          // The history viewer is the regular sets grid — shared
          // SessionSetRow rows in history mode, gated by the one-time
          // "you're about to edit past data" confirm: tapping any field
          // while gated shows the dialog, and after Continue the rows
          // behave like the live grid (keystroke-committed edits).
          historyRowBuilder: (s) => SessionSetRow(
            key: ValueKey('history-${s.sessionExerciseSetId}'),
            mode: SetRowMode.history,
            exerciseId: exerciseId,
            displayIndex: s.setNumber,
            isDraft: false,
            initialWeightText: s.weight != null ? _fmtNum(s.weight!) : '',
            initialRepsText: s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '',
            initialVariationId: s.variationId,
            initialVariationName: s.variationName,
            initialNotes: s.notes,
            hasNotes: s.notes?.isNotEmpty ?? false,
            // Past PR sets badge like the live grid — events keyed by set id.
            isPr: vm.prEventsBySetId.containsKey(s.sessionExerciseSetId),
            editConfirmed: vm.historyEditConfirmed,
            onEditConfirm: vm.confirmHistoryEdit,
            onCommit: (isDraft, v) async {
              if (!isDraft) {
                await vm.updateHistoricalSetField(
                  s,
                  weight: _parseWeight(v.weight),
                  clearWeight: v.weight == null,
                  reps: _parseReps(v.reps),
                );
              }
            },
            onVariationChanged: (id) => vm.updateHistoricalSetField(
              s,
              variationId: id,
              clearVariation: id == null,
            ),
            onNotesSave: (v) => vm.updateHistoricalSetField(
              s,
              notes: v.trim().isEmpty ? null : v.trim(),
              clearNotes: v.trim().isEmpty,
            ),
            // Gate-mode rows never expose swipe actions, so these two can
            // never fire.
            onDelete: () async {},
            onDuplicate: () {},
            variationOptions: variationOptions,
            allVariations: allVariations,
            findSimilarVariations: vm.findSimilarVariations,
            submitNewVariation: vm.submitNewVariation,
          ),
          // A fresh history session must re-earn the edit confirm gate.
          onHistorySessionSelected: (_) => vm.historyEditConfirmed = false,
        );
      },
    );
  }
}
