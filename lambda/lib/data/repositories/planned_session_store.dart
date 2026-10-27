import '../models/planned_session.dart';
import '../models/planned_session_exercise.dart';
import '../models/planned_session_exercise_set.dart';
import '../models/planned_session_program.dart';

/// The planned-session reads and writes the workout editor spends.
///
/// `PlannedSessionRepository` is the real store — every write lands on the
/// live dim rows. A review pass hands the editor a **staged** store instead
/// (2026-10-27): inside a review the same calls land in a copy of the rows
/// kept on the review itself, and the rows are only written when the pass
/// finishes. The editor does not know which one it was handed, which is what
/// keeps "a review edits the plan at the end" a fact of the store rather than
/// a flag threaded through every call site.
///
/// Only what the editor spends is here. Listing, duplicating, programs and
/// links stay on the concrete repository: a review edits the workouts it was
/// given, it never creates or removes one.
abstract interface class PlannedSessionStore {
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId);

  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId, {
    bool includeArchived = false,
  });

  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId, {
    bool includeArchived = false,
  });

  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String plannedSessionId, {
    bool includeArchived = false,
  });

  Future<PlannedSession> createPlannedSession(
    String userId, {
    String? name,
    String? notes,
  });

  Future<void> updatePlannedSession(
    String sessionId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    String userId = '',
  });

  Future<void> deletePlannedSession(String sessionId);

  Future<PlannedSessionProgram> createProgramLink(
    String userId, {
    required String programId,
    required String plannedSessionId,
    int? sequenceOrder,
    int? dayOfWeek,
    int? weekOffset,
    String? blockId,
  });

  Future<PlannedSessionExercise> createPlannedExercise(
    String userId,
    String plannedSessionId, {
    String? exerciseId,
    required int exerciseOrder,
  });

  Future<void> deletePlannedExercise(String plannedExerciseId);

  Future<void> restorePlannedExercise(
    String plannedExerciseId, {
    required int exerciseOrder,
  });

  Future<PlannedSessionExerciseSet> createPlannedSet(
    String userId,
    String plannedExerciseId, {
    required String plannedSessionId,
    String? exerciseId,
    String? variationId,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  });

  Future<void> updatePlannedSet(
    String plannedSetId, {
    String? targetWeight,
    bool clearWeight = false,
    String? targetReps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? targetNotes,
    bool clearNotes = false,
  });

  Future<void> deletePlannedSet(String plannedSetId);

  Future<void> restorePlannedSet(String plannedSetId, {required int setNumber});

  Future<void> renumberPlannedSets(List<String> orderedSetIds);

  Future<void> renumberExerciseOrders(
    String plannedSessionId,
    List<(int, int)> orderToIndex,
  );
}
