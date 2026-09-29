import '../../../data/models/program_revision.dart';

/// What kind of thing changed.
enum RevisionEntity { block, session, exercise, set }

/// How it changed.
enum RevisionChangeKind { added, removed, edited, moved }

/// One line in a version comparison.
class RevisionChange {
  const RevisionChange({
    required this.entity,
    required this.kind,
    required this.id,
    required this.label,
    this.detail,
    this.sessionId,
    this.sessionName,
    this.exerciseId,
    this.exerciseName,
  });

  final RevisionEntity entity;
  final RevisionChangeKind kind;

  /// The id of the changed thing — a `session_id`, `planned_exercise_id`,
  /// `planned_set_id` or `block_id`.
  final String id;

  /// The primary noun: a workout name, an exercise name, "Set 3", a block name.
  final String label;

  /// The delta, e.g. `2 → 4 sets` or `60 × 5 → 65 × 5`. Null for added/removed,
  /// where the label says everything.
  final String? detail;

  // Parent context, so a UI can group nested changes under their workout.
  final String? sessionId;
  final String? sessionName;
  final String? exerciseId;
  final String? exerciseName;

  @override
  String toString() => '${kind.name} ${entity.name} $label'
      '${detail != null ? ' ($detail)' : ''}';
}

/// The result of comparing two revisions.
class RevisionDiff {
  const RevisionDiff(this.changes);

  const RevisionDiff.empty() : changes = const [];

  final List<RevisionChange> changes;

  bool get isEmpty => changes.isEmpty;
  bool get isNotEmpty => changes.isNotEmpty;

  int countOf(RevisionChangeKind kind) =>
      changes.where((c) => c.kind == kind).length;

  int get addedCount => countOf(RevisionChangeKind.added);
  int get removedCount => countOf(RevisionChangeKind.removed);
  int get editedCount => countOf(RevisionChangeKind.edited);
  int get movedCount => countOf(RevisionChangeKind.moved);

  /// Changes touching a given workout, in emitted order.
  List<RevisionChange> forSession(String sessionId) =>
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

/// Compares two program contents and reports what changed between them.
///
/// Passing null for [from] means "the first version" — everything in [to] is
/// reported as added. A null [to] reports everything as removed.
///
/// [exerciseNames] and [blockNames] are optional id→name maps so the diff can
/// render real nouns without resolving anything itself. The snapshot stores
/// ids only (names resolve live, like every other surface), so without a map an
/// exercise falls back to a generic label.
///
/// **Move detection is the part that decides whether this reads as signal or
/// noise.** A move is reported only when an item's position among the items
/// that SURVIVE from [from] to [to] actually changed. Comparing raw positions
/// would report every subsequent workout as moved the moment one is inserted
/// at the head — which is exactly what makes version histories unreadable.
/// This also means renumbering orders without changing relative order reports
/// nothing, correctly.
RevisionDiff diffRevisions(
  ProgramRevisionContent? from,
  ProgramRevisionContent? to, {
  Map<String, String> exerciseNames = const {},
  Map<String, String> blockNames = const {},
}) {
  final before = from ?? const ProgramRevisionContent();
  final after = to ?? const ProgramRevisionContent();
  final changes = <RevisionChange>[];

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
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.added,
        id: session.sessionId,
        label: session.name,
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
      continue;
    }

    if (movedSessions.contains(session.sessionId)) {
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.moved,
        id: session.sessionId,
        label: session.name,
        detail: 'position ${beforePositions[session.sessionId]} → '
            '${afterPositions[session.sessionId]}',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if (prior.name != session.name) {
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: 'renamed: ${prior.name} → ${session.name}',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if ((prior.notes ?? '') != (session.notes ?? '')) {
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.edited,
        id: session.sessionId,
        label: session.name,
        detail: 'notes edited',
        sessionId: session.sessionId,
        sessionName: session.name,
      ));
    }

    if (prior.blockId != session.blockId) {
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.edited,
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
      changes.add(RevisionChange(
        entity: RevisionEntity.session,
        kind: RevisionChangeKind.edited,
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
    ));
  }

  // Removed workouts last — they have no place in the new ordering.
  for (final session in before.sessions) {
    if (afterById.containsKey(session.sessionId)) continue;
    changes.add(RevisionChange(
      entity: RevisionEntity.session,
      kind: RevisionChangeKind.removed,
      id: session.sessionId,
      label: session.name,
      sessionId: session.sessionId,
      sessionName: session.name,
    ));
  }

  return RevisionDiff(List.unmodifiable(changes));
}

List<RevisionChange> _compareBlocks({
  required Map<String, RevisionBlock> before,
  required Map<String, RevisionBlock> after,
  required List<String> beforeOrder,
  required List<String> afterOrder,
}) {
  final changes = <RevisionChange>[];
  final surviving =
      afterOrder.where(before.containsKey).toList(growable: false);
  final beforePositions = _positionsAmong(surviving, beforeOrder);
  final afterPositions = _positionsAmong(surviving, afterOrder);
  final movedBlocks = _movedAmong(beforeOrder, afterOrder);

  for (final id in afterOrder) {
    final prior = before[id];
    final block = after[id]!;
    if (prior == null) {
      changes.add(RevisionChange(
        entity: RevisionEntity.block,
        kind: RevisionChangeKind.added,
        id: id,
        label: block.name,
      ));
      continue;
    }
    if (movedBlocks.contains(id)) {
      changes.add(RevisionChange(
        entity: RevisionEntity.block,
        kind: RevisionChangeKind.moved,
        id: id,
        label: block.name,
        detail: 'position ${beforePositions[id]} → ${afterPositions[id]}',
      ));
    }
    if (prior.name != block.name) {
      changes.add(RevisionChange(
        entity: RevisionEntity.block,
        kind: RevisionChangeKind.edited,
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
      changes.add(RevisionChange(
        entity: RevisionEntity.block,
        kind: RevisionChangeKind.edited,
        id: id,
        label: block.name,
        detail: 'targets changed',
      ));
    }
  }

  for (final id in beforeOrder) {
    if (after.containsKey(id)) continue;
    changes.add(RevisionChange(
      entity: RevisionEntity.block,
      kind: RevisionChangeKind.removed,
      id: id,
      label: before[id]!.name,
    ));
  }

  return changes;
}

/// Sets are ordered by `set_number` in the document, so array position is the
/// set order and `set_number` itself is positional, not an edit field.
List<RevisionChange> _compareExercises({
  required RevisionSession session,
  required RevisionSession prior,
  required Map<String, String> exerciseNames,
}) {
  final changes = <RevisionChange>[];

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
      changes.add(RevisionChange(
        entity: RevisionEntity.exercise,
        kind: RevisionChangeKind.added,
        id: id,
        label: name,
        detail: '${exercise.sets.length} sets',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
      ));
      continue;
    }

    // A different lift under the same group id is a replace, never an edit —
    // rendering it as an edit would show a nonsense weight/reps diff between
    // two unrelated exercises.
    if (priorExercise.exerciseId != exercise.exerciseId) {
      final priorName = _exerciseLabel(priorExercise.exerciseId, exerciseNames);
      changes.add(RevisionChange(
        entity: RevisionEntity.exercise,
        kind: RevisionChangeKind.removed,
        id: id,
        label: priorName,
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: priorExercise.exerciseId,
        exerciseName: priorName,
      ));
      changes.add(RevisionChange(
        entity: RevisionEntity.exercise,
        kind: RevisionChangeKind.added,
        id: id,
        label: name,
        detail: 'replaced $priorName',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
      ));
      continue;
    }

    if (movedExercises.contains(id)) {
      changes.add(RevisionChange(
        entity: RevisionEntity.exercise,
        kind: RevisionChangeKind.moved,
        id: id,
        label: name,
        detail: 'position ${beforePositions[id]} → ${afterPositions[id]}',
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: name,
      ));
    }

    changes.addAll(_compareSets(
      exercise: exercise,
      prior: priorExercise,
      session: session,
      exerciseName: name,
    ));
  }

  for (final exercise in prior.exercises) {
    final id = exercise.plannedExerciseId;
    if (afterById.containsKey(id)) continue;
    final name = _exerciseLabel(exercise.exerciseId, exerciseNames);
    changes.add(RevisionChange(
      entity: RevisionEntity.exercise,
      kind: RevisionChangeKind.removed,
      id: id,
      label: name,
      sessionId: session.sessionId,
      sessionName: session.name,
      exerciseId: exercise.exerciseId,
      exerciseName: name,
    ));
  }

  return changes;
}

List<RevisionChange> _compareSets({
  required RevisionExercise exercise,
  required RevisionExercise prior,
  required RevisionSession session,
  required String exerciseName,
}) {
  final changes = <RevisionChange>[];

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

  RevisionChange build(
    RevisionChangeKind kind,
    RevisionSet set,
    String label, {
    String? detail,
  }) =>
      RevisionChange(
        entity: RevisionEntity.set,
        kind: kind,
        id: set.plannedSetId,
        label: label,
        detail: detail,
        sessionId: session.sessionId,
        sessionName: session.name,
        exerciseId: exercise.exerciseId,
        exerciseName: exerciseName,
      );

  for (var i = 0; i < exercise.sets.length; i++) {
    final set = exercise.sets[i];
    final priorSet = beforeById[set.plannedSetId];
    final label = 'Set ${i + 1}';

    if (priorSet == null) {
      changes.add(build(RevisionChangeKind.added, set, label,
          detail: _setSummary(set)));
      continue;
    }

    if (movedSets.contains(set.plannedSetId)) {
      changes.add(build(RevisionChangeKind.moved, set, label,
          detail: 'position ${beforePositions[set.plannedSetId]} → '
              '${afterPositions[set.plannedSetId]}'));
    }

    if (priorSet.targetWeight != set.targetWeight ||
        priorSet.targetReps != set.targetReps) {
      changes.add(build(
        RevisionChangeKind.edited,
        set,
        label,
        detail: '${_setSummary(priorSet)} → ${_setSummary(set)}',
      ));
    }

    if (priorSet.variationId != set.variationId) {
      changes.add(build(RevisionChangeKind.edited, set, label,
          detail: 'variation changed'));
    }

    if ((priorSet.targetNotes ?? '') != (set.targetNotes ?? '')) {
      changes.add(build(RevisionChangeKind.edited, set, label,
          detail: 'notes edited'));
    }
  }

  for (var i = 0; i < prior.sets.length; i++) {
    final set = prior.sets[i];
    if (afterById.containsKey(set.plannedSetId)) continue;
    changes.add(build(RevisionChangeKind.removed, set, 'Set ${i + 1}',
        detail: _setSummary(set)));
  }

  return changes;
}

String _setSummary(RevisionSet set) {
  final weight = (set.targetWeight?.trim().isNotEmpty ?? false)
      ? set.targetWeight!.trim()
      : '—';
  final reps =
      (set.targetReps?.trim().isNotEmpty ?? false) ? set.targetReps!.trim() : '—';
  if (weight == '—' && reps == '—') return 'empty';
  return '$weight × $reps';
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

String _blockLabel(String? blockId, Map<String, String> names) {
  if (blockId == null) return 'no block';
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
