import '../../../data/models/program_content.dart';
import '../../../data/models/program_review.dart';

/// What kind of thing changed.
enum ContentEntity { block, session, exercise, set, goal }

/// How it changed.
enum ContentChangeKind { added, removed, edited, moved }

/// One line in a snapshot comparison.
class ContentChange {
  const ContentChange({
    required this.entity,
    required this.kind,
    required this.id,
    required this.label,
    this.detail,
    this.oldText,
    this.newText,
    this.sessionId,
    this.sessionName,
    this.exerciseId,
    this.exerciseName,
    this.plannedExerciseId,
  });

  final ContentEntity entity;
  final ContentChangeKind kind;

  /// The id of the changed thing — a `session_id`, `planned_exercise_id`,
  /// `planned_set_id` or `block_id`.
  final String id;

  /// The primary noun: a workout name, an exercise name, "Set 3", a block name.
  final String label;

  /// The delta, e.g. `2 → 4 sets` or `60 × 5 → 65 × 5`. Null for added/removed,
  /// where the label says everything.
  final String? detail;

  /// The verbatim texts on either side of a note edit — what `notes edited`
  /// alone cannot say. [detail] carries each side collapsed to one line and
  /// capped, so the row reads; these carry the whole thing, for the popup that
  /// opens on a tap. Null on every change that is not a note.
  final String? oldText;
  final String? newText;

  // Parent context, so a UI can group nested changes under their workout.
  final String? sessionId;
  final String? sessionName;
  final String? exerciseId;
  final String? exerciseName;

  /// The exercise GROUP the change sits under (a `planned_exercise_id`), set
  /// on every exercise- and set-level change and null where there is no
  /// exercise context (blocks, workouts, goals). Lets a reader gather one
  /// exercise's changes by filtering — and it holds across a lift swap, where
  /// [exerciseId] itself changes.
  final String? plannedExerciseId;

  @override
  String toString() => '${kind.name} ${entity.name} $label'
      '${detail != null ? ' ($detail)' : ''}';
}

/// The result of comparing two snapshots.
class ContentDiff {
  const ContentDiff(this.changes);

  const ContentDiff.empty() : changes = const [];

  final List<ContentChange> changes;

  bool get isEmpty => changes.isEmpty;
  bool get isNotEmpty => changes.isNotEmpty;

  int countOf(ContentChangeKind kind) =>
      changes.where((c) => c.kind == kind).length;

  int get addedCount => countOf(ContentChangeKind.added);
  int get removedCount => countOf(ContentChangeKind.removed);
  int get editedCount => countOf(ContentChangeKind.edited);
  int get movedCount => countOf(ContentChangeKind.moved);

  /// Changes touching a given workout, in emitted order.
  List<ContentChange> forSession(String sessionId) =>
      changes.where((c) => c.sessionId == sessionId).toList();

  /// `+2 −1 ~3` — a one-line summary for a timeline row.
  String get summary {
    final parts = <String>[];
    if (addedCount > 0) parts.add('+$addedCount');
    if (removedCount > 0) parts.add('−$removedCount');
    if (editedCount > 0) parts.add('~$editedCount');
    if (movedCount > 0) parts.add('↕$movedCount');
    return parts.isEmpty ? 'no content changes' : parts.join(' ');
  }
}

/// The part of a program a review at this scope is looking at.
///
/// A comparison has to be scoped the same way the review is, because "what
/// changed" means nothing without "changed where": a workout review compares
/// the workout, a block review its block (and the goals in force there), and a
/// program review the whole shape. A diff that reported the siblings too would
/// answer a question nobody asked, and read as if the pass had broken things
/// it never touched.
///
/// The rules mirror the read-back (`review_detail_sheet`'s contents panel) —
/// one answer to "what is being reviewed", so the comparison and the record
/// cannot disagree about it.
///
/// A scope id that matches nothing yields a document with nothing from that
/// scope rather than the full one: the comparison then reads as "everything
/// removed", which is the honest rendering of a workout that was deleted
/// between two checkpoints. Silently widening to the whole program would be a
/// lie with content in it. (One exception, on purpose: program-level goals
/// still ride along at block scope — they were never that block's to lose.)
///
/// [sessionIds] is the **set** form — a review's own scope, and the shape the
/// read-back surfaces render: the named workouts, the blocks that hold any of
/// them, and the goals in force over them (the program's own plus those
/// blocks'). A set spanning two blocks keeps both, so a multi-workout pass
/// reads back as the ground it covered rather than as the whole program.
///
/// [goalIds] names goals the pass **explicitly picked**. They survive the
/// narrowing even when their block holds no reviewed workout — a goal chosen
/// on purpose was part of the pass's question, and dropping it because of
/// where its block sits would lose the thing the user ticked. Only meaningful
/// with [sessionIds]; ignored otherwise.
ProgramContent contentInScope(
  ProgramContent content, {
  String? blockId,
  String? sessionId,
  List<String>? sessionIds,
  Set<String>? goalIds,
}) {
  if (sessionId != null) {
    return ProgramContent(
      sessions: [
        for (final s in content.sessions)
          if (s.sessionId == sessionId) s,
      ],
    );
  }
  final set = sessionIds;
  if (set != null) {
    final kept = [
      for (final s in content.sessions)
        if (set.contains(s.sessionId)) s,
    ];
    final blocks = {
      for (final s in kept)
        if (s.blockId != null) s.blockId,
    };
    return ProgramContent(
      blocks: [
        for (final b in content.blocks)
          if (blocks.contains(b.blockId)) b,
      ],
      sessions: kept,
      // Same rule the achievements derivation uses: a program goal is chased
      // wherever its workouts sit, and each kept block's goals ride along —
      // plus the pass's explicitly picked goals, wherever they live.
      goals: [
        for (final g in content.goals)
          if (g.blockId == null ||
              blocks.contains(g.blockId) ||
              (goalIds?.contains(g.goalId) ?? false))
            g,
      ],
    );
  }
  final block = blockId;
  if (block == null) return content;
  return ProgramContent(
    blocks: [
      for (final b in content.blocks)
        if (b.blockId == block) b,
    ],
    sessions: [
      for (final s in content.sessions)
        if (s.blockId == block) s,
    ],
    // A block's goals plus the program's own: a goal with no block is in force
    // everywhere, so it is part of what this phase is chasing.
    goals: [
      for (final g in content.goals)
        if (g.blockId == null || g.blockId == block) g,
    ],
  );
}

/// [review]'s stored snapshot as the pass saw it: a set review narrows to the
/// workouts it covered (plus the goals it explicitly picked), while a legacy
/// row's whole-program document passes through untouched.
///
/// One helper for every read-back surface — the timeline's digests, the detail
/// sheet, the snapshot screen — so what a pass "changed" always counts the same
/// ground as what it renders. It narrows by the row's **stored** ids, not by a
/// live resolution: a workout deleted since the pass must still be able to
/// read back as removed rather than quietly leaving the record.
ProgramContent? scopedSnapshot(ProgramReview review) {
  final content = review.snapshot;
  if (content == null) return null;
  final stored = review.storedSessionIds;
  if (stored == null) return content;
  return contentInScope(
    content,
    sessionIds: stored,
    goalIds: review.storedGoalIds?.toSet(),
  );
}

/// Compares two program contents and reports what changed between them.
///
/// Passing null for [from] means "the first version" — everything in [to] is
/// reported as added. A null [to] reports everything as removed.
///
/// [exerciseNames], [blockNames] and [variationNames] are optional id→name
/// maps so the diff can render real nouns without resolving anything itself.
/// The snapshot stores ids only (names resolve live, like every other
/// surface), so without a map an exercise falls back to a generic label and a
/// variation change falls back to "variation changed".
///
/// **Move detection is the part that decides whether this reads as signal or
/// noise.** A move is reported only when an item's position among the items
/// that SURVIVE from [from] to [to] actually changed. Comparing raw positions
/// would report every subsequent workout as moved the moment one is inserted
/// at the head — which is exactly what makes version histories unreadable.
/// This also means renumbering orders without changing relative order reports
/// nothing, correctly.
ContentDiff diffContent(
  ProgramContent? from,
  ProgramContent? to, {
  Map<String, String> exerciseNames = const {},
  Map<String, String> blockNames = const {},
  Map<String, String> variationNames = const {},
}) {
  final before = from ?? const ProgramContent();
  final after = to ?? const ProgramContent();
  final changes = <ContentChange>[];

  final beforeBlockById = {for (final b in before.blocks) b.blockId: b};
  final afterBlockById = {for (final b in after.blocks) b.blockId: b};

  // ── Blocks ────────────────────────────────────────────────────────────────
  changes.addAll(_compareBlocks(
    before: beforeBlockById,
    after: afterBlockById,
    beforeOrder: before.blocks.map((b) => b.blockId).toList(),
    afterOrder: after.blocks.map((b) => b.blockId).toList(),
  ));

  // ── Workouts ──────────────────────────────────────────────────────────────
  final beforeById = {for (final s in before.sessions) s.sessionId: s};
  final afterById = {for (final s in after.sessions) s.sessionId: s};

  final surviving = after.sessions
      .map((s) => s.sessionId)
      .where(beforeById.containsKey)
      .toList(growable: false);
  final beforePositions = _positionsAmong(
      surviving, before.sessions.map((s) => s.sessionId).toList());
  final afterPositions = _positionsAmong(
      surviving, after.sessions.map((s) => s.sessionId).toList());
  final movedSessions = _movedAmong(
    before.sessions.map((s) => s.sessionId).toList(),
    after.sessions.map((s) => s.sessionId).toList(),
  );

  // Added and surviving workouts, in the new program's order, so each workout's
  // nested changes stay adjacent to the workout itself.
  for (final session in after.sessions) {
    final prior = beforeById[session.sessionId];

    if (prior == null) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.added,
        id: session.sessionId,
        label: session.name,
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
      continue;
    }

    if (movedSessions.contains(session.sessionId)) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.moved,
        id: session.sessionId,
        label: session.name,
        detail: 'position ${beforePositions[session.sessionId]} → '
            '${afterPositions[session.sessionId]}',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if (prior.name != session.name) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: 'renamed: ${prior.name} → ${session.name}',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if ((prior.notes ?? '') != (session.notes ?? '')) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: _noteChange(prior.notes, session.notes),
        oldText: prior.notes,
        newText: session.notes,
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if (prior.blockId != session.blockId) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: 'block: ${_blockLabel(prior.blockId, blockNames)} → '
            '${_blockLabel(session.blockId, blockNames)}',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if (prior.dayOfWeek != session.dayOfWeek ||
        prior.weekOffset != session.weekOffset) {
      changes.add(ContentChange(
        entity: ContentEntity.session,
        kind: ContentChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: 'schedule changed',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    changes.addAll(_compareExercises(
      session: session,
      prior: prior,
      exerciseNames: exerciseNames,
      variationNames: variationNames,
    ));
  }

  // Removed workouts last — they have no place in the new ordering.
  for (final session in before.sessions) {
    if (afterById.containsKey(session.sessionId)) continue;
    changes.add(ContentChange(
      entity: ContentEntity.session,
      kind: ContentChangeKind.removed,
      id: session.sessionId,
      label: session.name,
      sessionId: session.sessionId,
      sessionName: session.name,
    ));
  }

  // ── Goals ─────────────────────────────────────────────────────────────────
  // Last, and in the document's own order at each scope: a goal is a target
  // rather than a step, so it has no position to move from and every change to
  // one is added, removed or edited.
  changes.addAll(_compareGoals(
    before: before,
    after: after,
    exerciseNames: exerciseNames,
    blockNames: blockNames,
  ));

  return ContentDiff(List.unmodifiable(changes));
}

List<ContentChange> _compareGoals({
  required ProgramContent before,
  required ProgramContent after,
  required Map<String, String> exerciseNames,
  required Map<String, String> blockNames,
}) {
  final changes = <ContentChange>[];
  final beforeById = {for (final g in before.goals) g.goalId: g};
  final afterById = {for (final g in after.goals) g.goalId: g};

  for (final goal in after.goals) {
    final prior = beforeById[goal.goalId];
    if (prior == null) {
      changes.add(ContentChange(
        entity: ContentEntity.goal,
        kind: ContentChangeKind.added,
        id: goal.goalId,
        label: _goalLabel(goal, exerciseNames),
        detail: _goalTarget(goal),
      ));
      continue;
    }

    // Scope first: "this target now belongs to Block 2" is a different claim
    // from "the target moved from 100 to 110", and a goal can do both at once.
    if (prior.blockId != goal.blockId) {
      changes.add(ContentChange(
        entity: ContentEntity.goal,
        kind: ContentChangeKind.edited,
        id: goal.goalId,
        label: _goalLabel(goal, exerciseNames),
        detail: 'scope: ${_goalScopeLabel(prior.blockId, blockNames)} → '
            '${_goalScopeLabel(goal.blockId, blockNames)}',
      ));
    }

    if (prior.targetWeight != goal.targetWeight ||
        prior.targetReps != goal.targetReps) {
      changes.add(ContentChange(
        entity: ContentEntity.goal,
        kind: ContentChangeKind.edited,
        id: goal.goalId,
        label: _goalLabel(goal, exerciseNames),
        detail: 'target: ${_goalTarget(prior)} → ${_goalTarget(goal)}',
      ));
    }

    if ((prior.text ?? '') != (goal.text ?? '') ||
        prior.exerciseId != goal.exerciseId ||
        prior.variationId != goal.variationId) {
      changes.add(ContentChange(
        entity: ContentEntity.goal,
        kind: ContentChangeKind.edited,
        id: goal.goalId,
        label: _goalLabel(goal, exerciseNames),
        detail: 'reworded',
      ));
    }
  }

  for (final goal in before.goals) {
    if (afterById.containsKey(goal.goalId)) continue;
    changes.add(ContentChange(
      entity: ContentEntity.goal,
      kind: ContentChangeKind.removed,
      id: goal.goalId,
      label: _goalLabel(goal, exerciseNames),
      detail: _goalTarget(goal),
    ));
  }

  return changes;
}

/// A goal's noun: the text the user wrote, which for an exercise goal is the
/// exercise's name (the picker writes it there at creation), with the live
/// exercise name as the fallback for a row that somehow has none.
///
/// Deliberately not the target — that is the [ContentChange.detail], so
/// "Bench" and "100 kg × 1" do not repeat each other on one line.
String _goalLabel(ContentGoal goal, Map<String, String> exerciseNames) {
  final text = goal.text?.trim();
  if (text != null && text.isNotEmpty) return text;
  final id = goal.exerciseId;
  if (id != null) return exerciseNames[id] ?? 'Goal';
  return 'Goal';
}

/// A goal's target as a reader says it: `100 kg × 1`, or "no target" for a
/// goal that is only a sentence.
String _goalTarget(ContentGoal goal) {
  final parts = <String>[];
  if (goal.targetWeight != null) parts.add('${_trim(goal.targetWeight!)} kg');
  if (goal.targetReps != null) {
    final reps = goal.targetReps!;
    parts.add('$reps rep${reps == 1 ? '' : 's'}');
  }
  return parts.isEmpty ? 'no target' : parts.join(' × ');
}

String _trim(num n) =>
    n == n.roundToDouble() ? '${n.round()}' : n.toString();

List<ContentChange> _compareBlocks({
  required Map<String, ContentBlock> before,
  required Map<String, ContentBlock> after,
  required List<String> beforeOrder,
  required List<String> afterOrder,
}) {
  final changes = <ContentChange>[];
  final surviving =
      afterOrder.where(before.containsKey).toList(growable: false);
  final beforePositions = _positionsAmong(surviving, beforeOrder);
  final afterPositions = _positionsAmong(surviving, afterOrder);
  final movedBlocks = _movedAmong(beforeOrder, afterOrder);

  for (final id in afterOrder) {
    final prior = before[id];
    final block = after[id]!;
    if (prior == null) {
      changes.add(ContentChange(
        entity: ContentEntity.block,
        kind: ContentChangeKind.added,
        id: id,
        label: block.name,
      ));
      continue;
    }
    if (movedBlocks.contains(id)) {
      changes.add(ContentChange(
        entity: ContentEntity.block,
        kind: ContentChangeKind.moved,
        id: id,
        label: block.name,
        detail: 'position ${beforePositions[id]} → ${afterPositions[id]}',
      ));
    }
    if (prior.name != block.name) {
      changes.add(ContentChange(
        entity: ContentEntity.block,
        kind: ContentChangeKind.edited,
        id: id,
        label: block.name,
        detail: 'renamed: ${prior.name} → ${block.name}',
      ));
    }
    // The days remainder is compared too, and it has to be: a block that gained
    // three days kept the same weeks, so a two-field comparison would report no
    // change for an edit that moved the phase's last day — and a diff that
    // stays silent about a real change is worse than one that misses a rename.
    if (prior.targetWeeks != block.targetWeeks ||
        prior.targetDays != block.targetDays ||
        prior.targetSessions != block.targetSessions) {
      changes.add(ContentChange(
        entity: ContentEntity.block,
        kind: ContentChangeKind.edited,
        id: id,
        label: block.name,
        detail: 'targets changed',
      ));
    }
  }

  for (final id in beforeOrder) {
    if (after.containsKey(id)) continue;
    changes.add(ContentChange(
      entity: ContentEntity.block,
      kind: ContentChangeKind.removed,
      id: id,
      label: before[id]!.name,
    ));
  }

  return changes;
}

/// Sets are ordered by `set_number` in the document, so array position is the
/// set order and `set_number` itself is positional, not an edit field.
List<ContentChange> _compareExercises({
  required ContentSession session,
  required ContentSession prior,
  required Map<String, String> exerciseNames,
  required Map<String, String> variationNames,
}) {
  final changes = <ContentChange>[];

  final beforeById = {for (final e in prior.exercises) e.plannedExerciseId: e};
  final afterById = {for (final e in session.exercises) e.plannedExerciseId: e};

  final surviving = session.exercises
      .map((e) => e.plannedExerciseId)
      .where(beforeById.containsKey)
      .toList(growable: false);
  final beforePositions = _positionsAmong(
      surviving, prior.exercises.map((e) => e.plannedExerciseId).toList());
  final afterPositions = _positionsAmong(
      surviving, session.exercises.map((e) => e.plannedExerciseId).toList());
  final movedExercises = _movedAmong(
    prior.exercises.map((e) => e.plannedExerciseId).toList(),
    session.exercises.map((e) => e.plannedExerciseId).toList(),
  );

  for (final exercise in session.exercises) {
    final id = exercise.plannedExerciseId;
    final priorExercise = beforeById[id];
    final name = _exerciseLabel(exercise.exerciseId, exerciseNames);

    if (priorExercise == null) {
      changes.add(ContentChange(
        entity: ContentEntity.exercise,
        kind: ContentChangeKind.added,
        id: id,
        label: name,
        detail: '${exercise.sets.length} sets',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
        plannedExerciseId: id,
      ));
      continue;
    }

    // A different lift under the same group id is a replace, never an edit —
    // rendering it as an edit would show a nonsense weight/reps diff between
    // two unrelated exercises.
    if (priorExercise.exerciseId != exercise.exerciseId) {
      final priorName = _exerciseLabel(priorExercise.exerciseId, exerciseNames);
      changes.add(ContentChange(
        entity: ContentEntity.exercise,
        kind: ContentChangeKind.removed,
        id: id,
        label: priorName,
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: priorExercise.exerciseId,
        exerciseName: priorName,
        plannedExerciseId: id,
      ));
      changes.add(ContentChange(
        entity: ContentEntity.exercise,
        kind: ContentChangeKind.added,
        id: id,
        label: name,
        detail: 'replaced $priorName',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
        plannedExerciseId: id,
      ));
      continue;
    }

    if (movedExercises.contains(id)) {
      changes.add(ContentChange(
        entity: ContentEntity.exercise,
        kind: ContentChangeKind.moved,
        id: id,
        label: name,
        detail: 'position ${beforePositions[id]} → ${afterPositions[id]}',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
        plannedExerciseId: id,
      ));
    }

    changes.addAll(_compareSets(
      exercise: exercise,
      prior: priorExercise,
      session: session,
      exerciseName: name,
      variationNames: variationNames,
    ));
  }

  for (final exercise in prior.exercises) {
    final id = exercise.plannedExerciseId;
    if (afterById.containsKey(id)) continue;
    final name = _exerciseLabel(exercise.exerciseId, exerciseNames);
    changes.add(ContentChange(
      entity: ContentEntity.exercise,
      kind: ContentChangeKind.removed,
      id: id,
      label: name,
      sessionId: session.sessionId,
      sessionName: session.name,
      exerciseId: exercise.exerciseId,
      exerciseName: name,
      plannedExerciseId: id,
    ));
  }

  return changes;
}

List<ContentChange> _compareSets({
  required ContentExercise exercise,
  required ContentExercise prior,
  required ContentSession session,
  required String exerciseName,
  required Map<String, String> variationNames,
}) {
  final changes = <ContentChange>[];

  final beforeById = {for (final s in prior.sets) s.plannedSetId: s};
  final afterById = {for (final s in exercise.sets) s.plannedSetId: s};

  final surviving = exercise.sets
      .map((s) => s.plannedSetId)
      .where(beforeById.containsKey)
      .toList(growable: false);
  final beforePositions = _positionsAmong(
      surviving, prior.sets.map((s) => s.plannedSetId).toList());
  final afterPositions = _positionsAmong(
      surviving, exercise.sets.map((s) => s.plannedSetId).toList());
  final movedSets = _movedAmong(
    prior.sets.map((s) => s.plannedSetId).toList(),
    exercise.sets.map((s) => s.plannedSetId).toList(),
  );

  ContentChange build(
    ContentChangeKind kind,
    ContentSet set,
    String label, {
    String? detail,
    String? oldText,
    String? newText,
  }) =>
      ContentChange(
        entity: ContentEntity.set,
        kind: kind,
        id: set.plannedSetId,
        label: label,
        detail: detail,
        oldText: oldText,
        newText: newText,
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: exerciseName,
        plannedExerciseId: exercise.plannedExerciseId,
      );

  for (var i = 0; i < exercise.sets.length; i++) {
    final set = exercise.sets[i];
    final priorSet = beforeById[set.plannedSetId];
    final label = 'Set ${i + 1}';

    if (priorSet == null) {
      changes.add(build(ContentChangeKind.added, set, label,
          detail: _setDetail(set, variationNames)));
      continue;
    }

    if (movedSets.contains(set.plannedSetId)) {
      changes.add(build(ContentChangeKind.moved, set, label,
          detail: 'position ${beforePositions[set.plannedSetId]} → '
              '${afterPositions[set.plannedSetId]}'));
    }

    if (priorSet.targetWeight != set.targetWeight ||
        priorSet.targetReps != set.targetReps) {
      changes.add(build(
        ContentChangeKind.edited,
        set,
        label,
        detail: '${_setSummary(priorSet)} → ${_setSummary(set)}',
      ));
    }

    if (priorSet.variationId != set.variationId) {
      final from = _variationName(priorSet.variationId, variationNames);
      final to = _variationName(set.variationId, variationNames);
      changes.add(build(
        ContentChangeKind.edited,
        set,
        label,
        detail: from == 'a variation' && to == 'a variation'
            ? 'variation changed'
            : 'variation: $from → $to',
      ));
    }

    if ((priorSet.targetNotes ?? '') != (set.targetNotes ?? '')) {
      changes.add(build(
        ContentChangeKind.edited,
        set,
        label,
        detail: _noteChange(priorSet.targetNotes, set.targetNotes),
        oldText: priorSet.targetNotes,
        newText: set.targetNotes,
      ));
    }
  }

  for (var i = 0; i < prior.sets.length; i++) {
    final set = prior.sets[i];
    if (afterById.containsKey(set.plannedSetId)) continue;
    changes.add(build(ContentChangeKind.removed, set, 'Set ${i + 1}',
        detail: _setDetail(set, variationNames)));
  }

  return changes;
}

/// A note edit as one line: `was → now`, each side collapsed and capped.
///
/// The row cannot hold a note — a note is whatever the user typed, and a diff
/// row is one line — so each side is flattened (a note saved with newlines
/// reads as a sentence here) and cut at [_notePreviewLength]. The full texts
/// ride along on the change for the popup a tap opens.
String _noteChange(String? before, String? after) =>
    '${_notePreview(before)} → ${_notePreview(after)}';

const _notePreviewLength = 40;

String _notePreview(String? text) {
  final collapsed = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '(none)';
  return collapsed.length <= _notePreviewLength
      ? collapsed
      : '${collapsed.substring(0, _notePreviewLength - 1)}…';
}

String _setSummary(ContentSet set) {
  final weight = (set.targetWeight?.trim().isNotEmpty ?? false)
      ? set.targetWeight!.trim()
      : '—';
  final reps =
      (set.targetReps?.trim().isNotEmpty ?? false) ? set.targetReps!.trim() : '—';
  if (weight == '—' && reps == '—') return 'empty';
  return '$weight × $reps';
}

/// A set as one line, variation included: `Paused · 70 × 5`.
///
/// The line names the variation because a card groups by EXERCISE, not by
/// exercise × variation — a set that only a variation distinguishes from its
/// neighbours has to say so on its own line, or the card reads as noise.
String _setDetail(ContentSet set, Map<String, String> variationNames) {
  final summary = _setSummary(set);
  if (set.variationId == null) return summary;
  return '${_variationName(set.variationId, variationNames)} · $summary';
}

String _exerciseLabel(String? exerciseId, Map<String, String> names) {
  if (exerciseId == null) return 'Exercise';
  final name = names[exerciseId];
  if (name != null && name.trim().isNotEmpty) return name;
  // Names resolve live and the snapshot stores ids only, so an unknown id
  // (archived exercise, or no map passed) falls back to something readable
  // rather than leaking a raw uuid into the UI.
  return 'Exercise';
}

/// A variation as a change line names it: "none" for the plain exercise, the
/// live name when known, and a readable noun — never a uuid — for an id no
/// map resolves.
String _variationName(String? variationId, Map<String, String> names) {
  if (variationId == null) return 'none';
  final name = names[variationId];
  if (name != null && name.trim().isNotEmpty) return name;
  return 'a variation';
}

String _blockLabel(String? blockId, Map<String, String> names) {
  if (blockId == null) return 'no block';
  final name = names[blockId];
  if (name != null && name.trim().isNotEmpty) return name;
  return 'a block';
}

/// A goal's scope as the Goals tab names it.
///
/// Distinct from [_blockLabel] because the same null means two things: a
/// workout with no block is unplaced, while a goal with no block is the
/// program's own — in force in every block. "No block" would read as the first
/// on a line about the second, and the screen that sets this calls it
/// "Whole program".
String _goalScopeLabel(String? blockId, Map<String, String> names) {
  if (blockId == null) return 'Whole program';
  final name = names[blockId];
  if (name != null && name.trim().isNotEmpty) return name;
  return 'a block';
}

/// 1-based position of each of [ids] within [order], counting ONLY [ids] —
/// i.e. position among the items that survive both revisions. Used for the
/// "position 2 → 4" detail text, not for deciding WHETHER something moved
/// (see [_movedAmong]).
Map<String, int> _positionsAmong(List<String> ids, List<String> order) {
  final wanted = ids.toSet();
  final positions = <String, int>{};
  var n = 0;
  for (final id in order) {
    if (!wanted.contains(id)) continue;
    n++;
    positions[id] = n;
  }
  return positions;
}

/// The ids whose relative order genuinely changed.
///
/// Uses the longest common subsequence of the survivors: everything in the LCS
/// kept its relative order, so only the items outside it actually moved.
///
/// Comparing positions among survivors is NOT enough on its own. It correctly
/// ignores an insertion (positions shift uniformly, so nothing reads as moved),
/// but moving one item from the back to the front shifts every item after it —
/// so `[A,B,C] → [C,A,B]` would report all three as moved when the user moved
/// one. The LCS is `[A,B]`, so only `C` is reported. At these sizes (tens of
/// items) the quadratic DP is free, and it is the difference between a history
/// that reads as a changelog and one that reads as noise.
Set<String> _movedAmong(List<String> beforeOrder, List<String> afterOrder) {
  final beforeSet = beforeOrder.toSet();
  final afterSet = afterOrder.toSet();
  final beforeSurviving = beforeOrder.where(afterSet.contains).toList();
  final afterSurviving = afterOrder.where(beforeSet.contains).toList();
  if (beforeSurviving.isEmpty || afterSurviving.isEmpty) return const {};
  final kept = _lcs(beforeSurviving, afterSurviving).toSet();
  return afterSurviving.where((id) => !kept.contains(id)).toSet();
}

/// Longest common subsequence of [a] and [b], both containing unique ids.
///
/// The reconstruction step breaks ties with `>` (advance `j`, keeping `a`'s
/// element). A two-element swap is inherently ambiguous — `[A,B] → [B,A]` is
/// equally well described as "A moved down" or "B moved up" — and this tie-break
/// reports the item that moved to an EARLIER position, which is how someone
/// describes a drag-up and is the more common reorder gesture. Either choice is
/// correct; the point is that a swap reports ONE move, never two.
List<String> _lcs(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <String>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(a[i]);
      i++;
      j++;
    } else if (dp[i + 1][j] > dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}
