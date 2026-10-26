import 'package:flutter/material.dart';

import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../goals/view/goal_sheet.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';
import 'pr_history_sheet.dart';

/// Opens the shared exercise picker wired to [vm] — the one picker behind both
/// the live card and the empty-state placeholder, which differ only in whether
/// removal is offered.
///
/// [onRemoveExercise] is the screen's confirmation, addressed by slot index;
/// the picker hands it back an exercise id, so the mapping happens here. Null
/// leaves the tick informational, which is right for the placeholder — there is
/// nothing in the session to remove yet.
void showSessionExercisePicker(
  BuildContext context,
  SessionViewModel vm, {
  void Function(int index)? onRemoveExercise,
}) {
  showAddExerciseModal(
    context,
    listenable: vm,
    entries: () => [
      for (final e in vm.exercises)
        AddExerciseEntry(
          exerciseId: e.exerciseId,
          name: toProperCase(e.name),
          lastUsed: vm.lastUsedByExercise[e.exerciseId],
        ),
    ],
    isAdded: (id) => vm.exerciseSlots.any((s) => s.exerciseIds.contains(id)),
    onAdd: vm.addExerciseSlot,
    onRemoveRequest: onRemoveExercise == null
        ? null
        : (id) async {
            final i = vm.exerciseSlots.indexWhere(
              (s) => s.exerciseIds.contains(id),
            );
            if (i >= 0) onRemoveExercise(i);
          },
    onCreate: vm.submitNewExercise,
    isCreating: () => vm.newExCreating,
  );
}

/// One of an exercise's deleted (flagged) rows, drawn in place in the grid:
/// red, inert, and answering nothing — the Restore under the card is the way
/// back, and until then the row is a fact being shown (2026-10-14). Shared
/// by the live card's inline rows and the deleted view, so the two can never
/// drift.
///
/// [plannedTarget] is the template row this set was materialized from. The
/// deletion never erases what the set was meant to do: an empty cell still
/// draws the plan's target as the blue guide, so a deleted exercise reads as
/// its plan, not a blank grid (2026-10-23).
Widget deletedSetRow(
  SessionViewModel vm,
  SessionExerciseSet set,
  int displayIndex,
  String exerciseId, {
  PlannedSessionExerciseSet? plannedTarget,
}) {
  String fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  return SessionSetRow(
    key: ValueKey(set.sessionExerciseSetId),
    mode: SetRowMode.live,
    exerciseId: exerciseId,
    displayIndex: displayIndex,
    isDraft: false,
    initialWeightText: set.weight != null ? fmt(set.weight!) : '',
    initialRepsText: set.reps.isNotEmpty ? fmt(set.reps.first) : '',
    initialVariationId: set.variationId,
    initialVariationName: set.variationName,
    initialNotes: set.notes,
    hasNotes: set.notes?.isNotEmpty ?? false,
    plannedTarget: plannedTarget,
    deleted: true,
    readOnly: true,
    onCommit: (_, _, {bool immediate = false}) async {},
    onVariationChanged: (_) {},
    onNotesSave: (_) {},
    onDelete: () async {},
    onDuplicate: (_) {},
    variationOptions: [
      const DropdownOption<String?>(label: 'No Variation', value: null),
      ...vm.variationsByRecency.map(
        (v) => DropdownOption<String?>(label: v.name, value: v.variationId),
      ),
    ],
    allVariations: [
      for (final v in vm.allVariations) (id: v.variationId, name: v.name),
    ],
    findSimilarVariations: vm.findSimilarVariations,
    submitNewVariation: vm.submitNewVariation,
  );
}

/// The goal door on a live set (2026-10-26): the New goal form the goals
/// screen composes, opened on the row the user swiped — exercise, variation,
/// weight and reps already in it, and one keystroke away from being a target.
///
/// The row is re-read AFTER the pending commits are flushed: a value typed
/// and not yet settled is still the value the user is looking at, and the
/// form must open on what the row SHOWS, not on what was last written. The
/// write behind ADD folds the new goal into the G badges in place, so the set
/// that meets it turns green without a reload.
///
/// The form opens on a one-shot draft — a session door has nothing to resume,
/// and a second row opens on its own values — and it wires no "open that
/// workout" door: a live session does not leave itself to read a record.
Future<void> _openGoalForSet(
  BuildContext context,
  SessionViewModel vm,
  String setId,
) async {
  await vm.flushPendingCommits();
  if (!context.mounted) return;
  SessionExerciseSet? set;
  for (final s in vm.sets) {
    if (s.sessionExerciseSetId == setId) {
      set = s;
      break;
    }
  }
  final exerciseId = set?.exerciseId;
  if (set == null || exerciseId == null) return;
  await showAddGoalSheet(
    context,
    detailMap: vm.exerciseDetailMap,
    variations: vm.allVariations,
    lastUsed: vm.lastUsedByExercise,
    pastSets: vm.pastSets,
    seed: ExerciseTarget(
      exerciseId: exerciseId,
      exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
      variationId: set.variationId,
      weight: set.weight,
      reps: set.reps.isEmpty ? null : set.reps.first.toInt(),
    ),
    onAdd: vm.createGoalFromTarget,
  );
}

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

  /// The screen's remove-exercise confirmation, addressed by slot index — the
  /// exercise picker calls it when the user taps an already-added exercise.
  final void Function(int index)? onRemoveExercise;

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
        // The exercise's rows, deleted ones included and back in their
        // sorted place: a set deleted under a planned exercise stays
        // VISIBLE, red and inert, until the Restore under the card brings it
        // back — nothing underneath a planned exercise just disappears
        // (2026-10-14).
        final combined = <({SessionExerciseSet set, bool deleted})>[
          for (final s in vm.sets)
            if (s.exerciseId == exerciseId &&
                !vm.isDraftBoundRow(s.sessionExerciseSetId))
              (set: s, deleted: false),
          for (final s in vm.deletedSets)
            if (s.exerciseId == exerciseId) (set: s, deleted: true),
        ]..sort((a, b) => a.set.setNumber.compareTo(b.set.setNumber));
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
          sessionStartedAt: vm.workoutStartedAt,
          sessionIsLive: true,
        );

        // The card's PR pill opens the PR Lab's PR History, scoped to the
        // live session — the same sheet the floor's trophy opens, so the pill
        // and the tile always agree (2026-10-22).
        void openPrHistory() => showPrHistorySheet(
          context,
          exerciseName: name,
          prs: vm.prHistoryFor(exerciseId),
          sessionSetIds: vm.sessionPrSetIdsFor(exerciseId),
          sessionStartedAt: vm.workoutStartedAt,
          sessionIsLive: true,
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
        for (var i = 0; i < combined.length; i++) {
          final set = combined[i].set;
          if (combined[i].deleted) {
            rows.add(
              deletedSetRow(
                vm,
                set,
                i + 1,
                exerciseId,
                plannedTarget: plannedById[set.plannedSetId],
              ),
            );
            continue;
          }
          final planned = plannedById[set.plannedSetId];
          rows.add(
            SessionSetRow(
              key: ValueKey(set.sessionExerciseSetId),
              mode: SetRowMode.live,
              exerciseId: exerciseId,
              displayIndex: i + 1,
              isDraft: false,
              dragIndex: i,
              initialWeightText: set.weight != null ? _fmtNum(set.weight!) : '',
              initialRepsText: set.reps.isNotEmpty
                  ? _fmtNum(set.reps.first)
                  : '',
              initialVariationId: set.variationId,
              initialVariationName: set.variationName,
              initialNotes: set.notes,
              hasNotes: set.notes?.isNotEmpty ?? false,
              plannedTarget: planned,
              isPr: vm.isPrSet(set.sessionExerciseSetId),
              isGoal: vm.isGoalSet(set.sessionExerciseSetId),
              onRegisterCommit: vm.registerCommitHandle,
              onUnregisterCommit: vm.unregisterCommitHandle,
              onCommit: (isDraft, v, {bool immediate = false}) async {
                if (!isDraft) {
                  await vm.updateSetField(
                    set,
                    weight: _parseWeight(v.weight),
                    clearWeight: v.weight == null,
                    reps: _parseReps(v.reps),
                    clearReps: v.reps == null,
                    // First real commit adopts the planned variation — the
                    // draft path does the same, so a logged row keeps its
                    // template's variation instead of silently losing it.
                    variationId:
                        set.variationId == null && planned?.variationId != null
                        ? planned!.variationId
                        : null,
                    immediate: immediate,
                  );
                }
              },
              onVariationChanged: (id) => vm.updateSetField(
                set,
                variationId: id,
                clearVariation: id == null,
                immediate: true,
              ),
              onNotesSave: (v) => vm.updateSetField(
                set,
                notes: v.trim().isEmpty ? null : v.trim(),
                clearNotes: v.trim().isEmpty,
                variationId:
                    set.variationId == null && planned?.variationId != null
                    ? planned!.variationId
                    : null,
                immediate: true,
              ),
              onDelete: () => vm.deleteSetById(set.sessionExerciseSetId),
              onDuplicate: (v) => vm.duplicateSet(
                set,
                weight: _parseWeight(v.weight),
                reps: _parseReps(v.reps),
              ),
              // The goal door (2026-10-26): a set is where a target comes
              // from. Every committed row carries it — a live session is the
              // best moment to decide to chase what was just lifted.
              onCreateGoal: () => _openGoalForSet(
                context,
                vm,
                set.sessionExerciseSetId,
              ),
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
              displayIndex: combined.length + i + 1,
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
              onCommit: (isDraft, v, {bool immediate = false}) async {
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
              onDuplicate: (_) {},
              variationOptions: variationOptions,
              allVariations: allVariations,
              findSimilarVariations: vm.findSimilarVariations,
              submitNewVariation: vm.submitNewVariation,
            ),
          );
        }

        // The selector lists the active tabs; exercises added beyond the
        // plan wear the green plus, present planned pills stay bare
        // (2026-10-13). Deleted planned exercises live behind the
        // trash-restore button on the stats bar, not in the selector.
        return SessionExerciseCard(
          exerciseNames: [
            for (final s in vm.exerciseSlots)
              toProperCase(vm.exerciseDisplayName(s.exerciseIds.first)),
          ],
          exerciseMarks: [
            for (final s in vm.exerciseSlots)
              s.planned ? null : ExerciseMark.added,
          ],
          activeIndex: vm.activeSlotIndex,
          onSelect: vm.tapTab,
          onMove: (i, dir) => vm.reorderExercises(i, i + dir),
          onAdd: () => showSessionExercisePicker(
            context,
            vm,
            onRemoveExercise: onRemoveExercise,
          ),
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
          // The pill counts and opens this session's PRs for the exercise —
          // the same feed the floor's trophy opens (2026-10-22). The count
          // never decides doorness: the sheet holds the exercise's whole
          // history, not only this session's gains (2026-10-23).
          prCount: vm.sessionPrCountFor(exerciseId),
          onPrTap: openPrHistory,
          planned: slot.planned,
          // The live session is a flat card since 2026-10-22 — the page
          // ground shows through and every row lands on the 22pt gutter.
          flat: true,
          rows: rows,
          onAddSet: () => vm.addDraftSet(exerciseId),
          // The reorderable indexes its CHILDREN — the red rows included —
          // while the VM reorders the exercise's ACTIVE rows, so a drag's
          // positions are mapped across the two (2026-10-14). A red row has
          // no drag handle, so only an active index can be lifted.
          onReorderSets: (oldIndex, newIndex) {
            final oldActive = [
              for (var i = 0; i < combined.length; i++)
                if (!combined[i].deleted) i,
            ].indexOf(oldIndex);
            if (oldActive == -1) return;
            // The drop position read back onto the active rows: count them
            // before it once the lifted row is out (`onReorderItem`'s
            // newIndex already accounts for the lift).
            var newActive = 0;
            var kept = 0;
            for (var i = 0; i < combined.length; i++) {
              if (i == oldIndex) continue;
              if (kept == newIndex) break;
              if (!combined[i].deleted) newActive++;
              kept++;
            }
            vm.reorderSets(exerciseId, oldActive, newActive);
          },
          history: history,
          // The date bar's EXERCISE walk selects a performance (2026-10-23):
          // the flat card has no pills row, so the stage hands the card the
          // one it is showing. Home (today's live sets) is null.
          historySelection: vm.viewedExerciseHistory,
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
            // Past PR sets badge like the live grid — events keyed by set id —
            // and past goal sets read green with the G the same way.
            isPr: vm.prEventsBySetId.containsKey(s.sessionExerciseSetId),
            isGoal: vm.isGoalSet(s.sessionExerciseSetId),
            editConfirmed: vm.historyEditConfirmed,
            onEditConfirm: vm.confirmHistoryEdit,
            onCommit: (isDraft, v, {bool immediate = false}) async {
              if (!isDraft) {
                await vm.updateHistoricalSetField(
                  s,
                  weight: _parseWeight(v.weight),
                  clearWeight: v.weight == null,
                  reps: _parseReps(v.reps),
                  clearReps: v.reps == null,
                  immediate: immediate,
                );
              }
            },
            onVariationChanged: (id) => vm.updateHistoricalSetField(
              s,
              variationId: id,
              clearVariation: id == null,
              immediate: true,
            ),
            onNotesSave: (v) => vm.updateHistoricalSetField(
              s,
              notes: v.trim().isEmpty ? null : v.trim(),
              clearNotes: v.trim().isEmpty,
              immediate: true,
            ),
            // Gate-mode rows never expose swipe actions, so these two can
            // never fire.
            onDelete: () async {},
            onDuplicate: (_) {},
            variationOptions: variationOptions,
            allVariations: allVariations,
            findSimilarVariations: vm.findSimilarVariations,
            submitNewVariation: vm.submitNewVariation,
          ),
          // A fresh history session must re-earn the edit confirm gate.
          onHistorySessionSelected: (_) => vm.historyEditConfirmed = false,
          // The picker tiles show each past session's PR count.
          isPrSet: (setId) => vm.prEventsBySetId.containsKey(setId),
        );
      },
    );
  }
}

/// The live session's reading of **deleted** planned exercises (2026-10-14,
/// widened 2026-10-23): what the trash menu's row opens. The selector lists
/// every deleted exercise — red, in the trash's own order — and picking one
/// from its popover flips the card onto that exercise's surviving rows. The
/// rows draw red and inert, with an empty cell still
/// showing the plan's target as the blue guide: the deletion does not erase
/// what the exercise was meant to do. The caller draws the Restore button
/// under this card, and it restores the exercise on screen; looking is not
/// writing.
class DeletedExerciseCard extends StatelessWidget {
  const DeletedExerciseCard({super.key, required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final seId = vm.deletedViewSeId;
        if (seId == null) return const SizedBox.shrink();
        final entries = vm.deletedPlannedExerciseEntries;
        final activeIndex = entries.indexWhere((e) => e.id == seId);
        if (activeIndex < 0) return const SizedBox.shrink();
        final exerciseId = vm.deletedViewSessionExercise?.exerciseId;
        if (exerciseId == null) return const SizedBox.shrink();

        // Each row keeps its template link, so the guide survives the
        // deletion — id-anchored, never positional.
        final plannedById = vm.plannedSetById;
        final sets = vm.deletedViewSets;
        final rows = <Widget>[
          for (var i = 0; i < sets.length; i++)
            deletedSetRow(
              vm,
              sets[i],
              i + 1,
              exerciseId,
              plannedTarget: plannedById[sets[i].plannedSetId],
            ),
        ];

        return SessionExerciseCard(
          exerciseNames: [
            for (final e in entries) toProperCase(e.name),
          ],
          // Every name here is a deleted exercise — the selector IS the
          // deleted set, so each wears the deleted box.
          deletedExercises: [for (final _ in entries) true],
          activeIndex: activeIndex,
          // Picking another deleted exercise flips the card onto it in
          // place; the view stays up and nothing is written.
          onSelect: vm.viewDeletedPlannedExerciseAt,
          onMove: null,
          onAdd: null,
          pinnedLesson: null,
          onPinnedLessonTap: null,
          lessonsCount: 0,
          onLessonsTap: null,
          prCount: 0,
          onPrTap: null,
          // The same flat reading the live card wears, with no outer rim:
          // the deletion reads off the red selector and rows (2026-10-23).
          flat: true,
          rows: rows,
          onAddSet: null,
          onReorderSets: null,
          history: null,
          isPrSet: null,
        );
      },
    );
  }
}
