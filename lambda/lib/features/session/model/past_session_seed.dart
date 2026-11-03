import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_exercise.dart';
import '../../../data/models/session_exercise_set.dart';

/// A completed session picked to start today's from — "From past session"
/// (2026-10-26).
///
/// The record is the input, not the template: today's session is the
/// record's own arrangement, with each set's numeric kg recorded as the real
/// weight so the user starts where they left off. What is deliberately NOT
/// copied is as much of the rule as what is:
///
/// - **Reps are never copied.** A rep count is today's performance; a copied
///   one would write work that was not done. The cells stay the plan's blue
///   guide (or empty for a freestyle record).
/// - **Notes are never copied.** A note is that performance's remark.
/// - **The planned links are.** Each row keeps the template row it was
///   materialized from, so the original plan rides underneath — the ghost
///   targets, the planned tint and the name — with no new
///   `dim_planned_session` rows. A record whose template has since been
///   deleted degrades to a flat copy: the links stay (plain refs), the
///   guides simply have nothing to draw.
/// - **The variation is** the source row's, except where the plan target it
///   links to already names one: the plan's variation is a real value shown
///   by the card and adopted by the row's first commit, so copying it would
///   be redundant, and copying a different one would contradict the plan the
///   session is following today.
///
/// Read once at selection (the exercise rows and the listing's sets), with
/// the plan resolved live — [exercisesToCopy] is the one place both the
/// page's preview and the view model's materialization ask what Start will
/// write, so the two can never disagree.
class PastSessionSeed {
  const PastSessionSeed({
    required this.source,
    required this.exercises,
    required this.sets,
    this.plan,
  });

  /// The record being repeated.
  final Session source;

  /// The record's exercise rows, in its persisted tab order
  /// (`fact_session_exercise.exercise_order`).
  final List<SessionExercise> exercises;

  /// The record's performed sets — the listing read already filters flagged
  /// rows out, and every row carries its own planned link.
  final List<SessionExerciseSet> sets;

  /// The plan the record rode on, resolved live at selection. Null for a
  /// freestyle record, and for one whose template has since been deleted.
  final PlannedSession? plan;

  /// The plan id today's session links — the record's own, so the log names
  /// the plan it followed even where the template is gone.
  String? get plannedSessionId => source.plannedSessionId;

  /// The name snapshot today's session writes: the template's live name,
  /// because a snapshot is written at creation from the plan as it stands
  /// that day; the record's own snapshot only as a fallback (a plan deleted
  /// since still names what the repeat follows). Null for a freestyle
  /// record, which follows no plan.
  String? get planName {
    final live = plan?.name;
    if (live != null) return live;
    return source.plannedSessionId == null ? null : source.plannedSessionName;
  }

  /// What Start writes, in the order the card draws it.
  ///
  /// [plannedById] is the resolved plan's target lookup (the same
  /// `plannedSetById` the live card reads its ghosts from); it decides only
  /// whether a row's variation is copied, never whether a row is.
  List<SeedExercise> exercisesToCopy(
    Map<String, PlannedSessionExerciseSet> plannedById,
  ) {
    final byExercise = <String, List<SessionExerciseSet>>{};
    for (final set in sets) {
      final id = set.exerciseId;
      if (id == null) continue; // a free row, nothing to arrange it under
      byExercise.putIfAbsent(id, () => []).add(set);
    }
    for (final list in byExercise.values) {
      list.sort((a, b) => a.setNumber.compareTo(b.setNumber));
    }

    // The record's own arrangement: first appearance across its exercise
    // rows is `exercise_order`, renumbered from 1 by the write. An exercise
    // row with nothing performed has nothing to repeat; a set whose exercise
    // row the record no longer holds still gets a group, appended, so no
    // performed set is ever silently dropped.
    final order = <String>[];
    final plannedExerciseByExercise = <String, String?>{};
    for (final exercise in exercises) {
      final id = exercise.exerciseId;
      if (id == null || !byExercise.containsKey(id)) continue;
      if (plannedExerciseByExercise.containsKey(id)) continue;
      order.add(id);
      plannedExerciseByExercise[id] = exercise.plannedExerciseId;
    }
    for (final id in byExercise.keys) {
      if (plannedExerciseByExercise.containsKey(id)) continue;
      order.add(id);
      plannedExerciseByExercise[id] = null;
    }

    return [
      for (final id in order)
        SeedExercise(
          exerciseId: id,
          plannedExerciseId: plannedExerciseByExercise[id],
          sets: [
            for (final set in byExercise[id]!)
              SeedSet(
                source: set,
                // The plan target speaks first where it names a variation;
                // otherwise the row keeps the one it was performed with.
                variationId: plannedById[set.plannedSetId]?.variationId == null
                    ? set.variationId
                    : null,
              ),
          ],
        ),
    ];
  }
}

/// One exercise of a repeated session — the rows Start writes under one tab.
class SeedExercise {
  const SeedExercise({
    required this.exerciseId,
    required this.plannedExerciseId,
    required this.sets,
  });

  final String exerciseId;

  /// The plan's exercise row the source tab was linked to, copied so the
  /// plan keeps riding underneath today's session too.
  final String? plannedExerciseId;

  final List<SeedSet> sets;
}

/// One row Start writes: the source set's numbers, ready to copy. [source]
/// is kept for the row's identity (and its variation's name); [weight] and
/// [plannedSetId] read straight off it.
class SeedSet {
  const SeedSet({required this.source, required this.variationId});

  final SessionExerciseSet source;

  /// The variation the copy takes — the plan target's name is left to the
  /// card (a real value adopted by the first commit), so a row whose target
  /// names one copies none.
  final String? variationId;

  double? get weight => source.weight;

  String? get plannedSetId => source.plannedSetId;
}
