import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/models/program.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/data/models/program_progress.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/models/program_run.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/features/programs/model/achievements_derivation.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';

/// In-memory stand-ins for the program repositories.
///
/// Each one `implements` its repository and leaves everything unexercised to
/// `noSuchMethod` — a host test has no PowerSync, so a call that reached the
/// database would be a mistake worth failing on. Only the methods the run
/// lifecycle actually calls are implemented, and each records what it was
/// asked, so the tests assert on the conversation rather than on the effect.
///
/// Shared because the lifecycle's contract — the id, the block, the closing
/// record — is asserted from three angles: the lifecycle itself, the detail
/// view model, and the library view model.

// ── Fixtures ────────────────────────────────────────────────────────────────

Program testProgram({
  String programId = 'p1',
  String userId = 'u1',
  String name = 'Base',
  bool usesBlocks = false,
  int? defaultTargetSessions,
}) => Program(
  programId: programId,
  userId: userId,
  name: name,
  usesBlocks: usesBlocks,
  defaultTargetSessions: defaultTargetSessions,
  createdDate: DateTime(2026, 1, 1),
  updatedDate: DateTime(2026, 1, 1),
);

ProgramBlock testBlock({
  String blockId = 'b1',
  String programId = 'p1',
  String userId = 'u1',
  String name = 'Accumulation',
  int order = 1,
  int? targetWeeks,
  int? targetSessions,
  DateTime? startDate,
}) => ProgramBlock(
  blockId: blockId,
  userId: userId,
  programId: programId,
  name: name,
  blockOrder: order,
  targetWeeks: targetWeeks,
  targetSessions: targetSessions,
  startDate: startDate,
);

ProgramRun testRun({
  String programRunId = 'run-1',
  String programId = 'p1',
  String userId = 'u1',
  DateTime? startedDate,
  bool isCurrent = true,
  DateTime? endedDate,
  String? blockId,
  int? targetSessions,
  int? targetWeeks,
  DateTime? endDate,
  String? progressionMode = 'order',
}) => ProgramRun(
  programRunId: programRunId,
  programId: programId,
  userId: userId,
  startedDate: startedDate ?? DateTime(2026, 2, 1),
  isCurrent: isCurrent,
  // A run is paused exactly when it is off and unstamped, so fixture
  // callers get the state by not passing one: `testRun(isCurrent: false)`.
  endedDate: endedDate,
  blockId: blockId,
  targetSessions: targetSessions,
  targetWeeks: targetWeeks,
  endDate: endDate,
  progressionMode: progressionMode,
);

/// The same run in another state — the model has no `copyWith`, and the fake
/// has to move rows between states the way the SQL does.
ProgramRun _inState(
  ProgramRun r, {
  required bool isCurrent,
  DateTime? endedDate,
}) => ProgramRun(
  programRunId: r.programRunId,
  programId: r.programId,
  userId: r.userId,
  startedDate: r.startedDate,
  isCurrent: isCurrent,
  endedDate: endedDate,
  blockId: r.blockId,
  targetSessions: r.targetSessions,
  targetWeeks: r.targetWeeks,
  endDate: r.endDate,
  progressionMode: r.progressionMode,
);

// ── Runs ────────────────────────────────────────────────────────────────────

/// One call to [ProgramRunRepository.startProgramRun], kept whole so a test
/// can assert on any part of it without re-deriving the arguments.
class StartedRun {
  StartedRun({
    required this.userId,
    required this.programId,
    required this.returned,
    this.progressionMode,
    this.targetSessions,
    this.targetWeeks,
    this.endDate,
    this.blockId,
  });

  final String userId;
  final String programId;
  final String? progressionMode;
  final int? targetSessions;
  final int? targetWeeks;
  final DateTime? endDate;
  final String? blockId;

  /// What the repository handed back — the id every later write must address.
  final ProgramRun returned;
}

class UpdateConfigCall {
  UpdateConfigCall({required this.programRunId, this.values = const {}});

  final String programRunId;
  final Map<String, Object?> values;
}

class FakeProgramRunRepository implements ProgramRunRepository {
  /// The run [getCurrentRun] answers with. Starting a run replaces it, exactly
  /// as the real repository's write does — by stepping it aside, not by ending
  /// it.
  ProgramRun? currentRun;

  /// Open runs that are not current, most recently started first — what
  /// [fetchPausedRuns] answers with. A superseding begin and [pauseCurrentRun]
  /// both move the previous current run here.
  final pausedRuns = <ProgramRun>[];

  /// Runs readable by [fetchRunById], keyed by id.
  final runsById = <String, ProgramRun>{};

  /// What [getProgress] and [progressFor] answer with.
  ProgramProgress? progress;

  /// Set to make [startProgramRun] throw — the write the whole begin hangs on.
  bool failStart = false;

  /// Set to make [fetchPausedRuns] throw — the courtesy read behind the
  /// confirmation's "paused programs stay paused" line.
  bool failFetchPaused = false;

  /// When set, [startProgramRun] hands back exactly this run instead of
  /// minting one. The only way to model the case the real repository makes
  /// hard: a begin that lands on the id that is already current.
  ProgramRun? startReturns;

  final starts = <StartedRun>[];
  final updateConfigCalls = <UpdateConfigCall>[];
  final endCalls = <String>[];
  final endRunCalls = <String>[];
  final pauseCalls = <String>[];
  final resumeCalls = <String>[];
  final fetchByIdCalls = <String>[];
  int _n = 0;

  @override
  Future<ProgramRun?> getCurrentRun(String userId) async => currentRun;

  @override
  Future<ProgramRun?> fetchRunById(String programRunId) async {
    fetchByIdCalls.add(programRunId);
    return runsById[programRunId];
  }

  /// Every run this fake knows of for one program, newest first.
  ///
  /// Answered from the fake's own bookkeeping rather than a canned list, so a
  /// test that begins, resumes or ends a run sees the block sequence move
  /// without having to set anything up — and so a test can never assert
  /// against a sequence the fake's own run state contradicts.
  @override
  Future<List<ProgramRun>> fetchRunsForProgram(String programId) async {
    final runs = runsById.values.where((r) => r.programId == programId).toList()
      ..sort((a, b) => b.startedDate.compareTo(a.startedDate));
    return runs;
  }

  @override
  Future<List<ProgramRun>> fetchPausedRuns(String userId) async {
    if (failFetchPaused) throw StateError('paused read failed');
    return List.unmodifiable(pausedRuns);
  }

  @override
  Future<ProgramRun?> fetchPausedRun(String userId, {String? programId}) async {
    for (final r in pausedRuns) {
      if (programId == null || r.programId == programId) return r;
    }
    return null;
  }

  /// Steps the current run aside: off, and deliberately not stamped — the pair
  /// of writes the real repository makes, and the whole difference between
  /// pausing and ending.
  @override
  Future<void> pauseCurrentRun(String userId) async {
    pauseCalls.add(userId);
    final run = currentRun;
    if (run == null) return;
    _pause(run);
  }

  @override
  Future<ProgramRun> startProgramRun(
    String userId,
    String programId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async {
    if (failStart) throw StateError('start failed');
    if (startReturns != null) {
      final reused = startReturns!;
      currentRun = reused;
      runsById[reused.programRunId] = reused;
      return reused;
    }
    // Mirrors the real write: the run being replaced is paused first, in the
    // same move — whatever program it belonged to. A fake that just overwrote
    // `currentRun` would let a close-on-replace regression pass every test in
    // this suite.
    final previous = currentRun;
    if (previous != null) _pause(previous);
    final run = testRun(
      // A fresh id per call, like the real repository — a caller that reuses
      // its own id instead of this one is exactly what the tests catch.
      programRunId: 'run-${++_n}',
      programId: programId,
      userId: userId,
      blockId: blockId,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate,
      progressionMode: progressionMode,
    );
    starts.add(
      StartedRun(
        userId: userId,
        programId: programId,
        returned: run,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        blockId: blockId,
      ),
    );
    currentRun = run;
    runsById[run.programRunId] = run;
    return run;
  }

  void _pause(ProgramRun run) {
    final paused = run.asPaused();
    currentRun = null;
    pausedRuns.removeWhere((r) => r.programRunId == paused.programRunId);
    pausedRuns.insert(0, paused);
    runsById[paused.programRunId] = paused;
  }

  @override
  Future<void> endRun(String programRunId) async {
    endRunCalls.add(programRunId);
    final run = runsById[programRunId] ?? currentRun;
    if (run == null) return;
    final ended = _inState(
      run,
      isCurrent: false,
      endedDate: DateTime(2026, 3, 3),
    );
    runsById[programRunId] = ended;
    pausedRuns.removeWhere((r) => r.programRunId == programRunId);
    if (currentRun?.programRunId == programRunId) currentRun = null;
  }

  @override
  Future<void> resumeRun(String userId, String programRunId) async {
    resumeCalls.add(programRunId);
    ProgramRun? run = runsById[programRunId];
    if (run == null) {
      for (final r in pausedRuns) {
        if (r.programRunId == programRunId) {
          run = r;
          break;
        }
      }
    }
    // A resume that found nothing to resume leaves the current run alone
    // rather than clearing it — the real UPDATE simply matches no row.
    if (run == null) return;
    // Whatever is current steps aside first — the ordering the real
    // transaction exists for.
    final previous = currentRun;
    if (previous != null && previous.programRunId != programRunId) {
      _pause(previous);
    }
    final resumed = _inState(run, isCurrent: true, endedDate: null);
    pausedRuns.removeWhere((r) => r.programRunId == programRunId);
    currentRun = resumed;
    runsById[programRunId] = resumed;
  }

  @override
  Future<void> updateRunConfig(
    String programRunId, {
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) async {
    updateConfigCalls.add(
      UpdateConfigCall(
        programRunId: programRunId,
        values: {
          'progressionMode': progressionMode,
          'targetSessions': targetSessions,
          'targetWeeks': targetWeeks,
          'endDate': endDate,
          'clearSessions': clearSessions,
          'clearWeeks': clearWeeks,
          'clearEndDate': clearEndDate,
        },
      ),
    );
  }

  @override
  Future<void> endCurrentRun(String userId) async {
    endCalls.add(userId);
    final run = currentRun;
    // Stamped, not just cleared: an end that only dropped the pointer would
    // leave the row looking paused to every later read.
    if (run != null) {
      runsById[run.programRunId] = _inState(
        run,
        isCurrent: false,
        endedDate: DateTime(2026, 3, 3),
      );
    }
    currentRun = null;
  }

  @override
  Future<ProgramProgress?> getProgress(String userId) async => progress;

  @override
  Future<ProgramProgress?> progressFor(ProgramRun run) async => progress;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── History ─────────────────────────────────────────────────────────────────

class CloseRunCall {
  CloseRunCall({
    required this.userId,
    required this.programId,
    required this.runId,
    required this.achievementsJson,
    this.blockId,
  });

  final String userId;
  final String programId;
  final String runId;
  final String achievementsJson;
  final String? blockId;
}

class FakeProgramHistoryRepository implements ProgramHistoryRepository {
  /// An existing checkpoint, or null to let [checkpointFor] answer with the
  /// fallback — which is what makes "the window opens at the run's start"
  /// assertable end to end through the derivation's `from`.
  DateTime? checkpoint;

  /// Every `fallback` the callers passed, so a test can assert the window
  /// really opens at the run's start and not at "now".
  final fallbacks = <DateTime?>[];

  /// Every scope the window was asked about, in order — so a test can assert a
  /// block's record was opened at that block's checkpoint rather than the
  /// program's, which a fake that ignored the argument could not tell apart.
  final scopes = <String?>[];

  /// Every session scope asked about, in order — a session-scoped window is
  /// that workout's, and only that workout's.
  final sessionScopes = <String?>[];

  /// Set to make [closeRun] throw — the run ended, the record did not.
  bool failClose = false;

  final closeCalls = <CloseRunCall>[];
  List<DueItem> due = const [];

  /// What [fetchReviews] answers with — the timeline a test hands the view
  /// model. Empty by default, which is what a fresh program has.
  List<ProgramReview> reviews = const [];

  @override
  Future<DateTime> checkpointFor(
    String programId, {
    String? blockId,
    String? sessionId,
    DateTime? fallback,
  }) async {
    scopes.add(blockId);
    sessionScopes.add(sessionId);
    fallbacks.add(fallback);
    return checkpoint ?? fallback ?? DateTime(2026, 3, 1);
  }

  @override
  Future<ProgramReview> closeRun({
    required String userId,
    required String programId,
    required String runId,
    required String achievementsJson,
    String? blockId,
  }) async {
    if (failClose) throw StateError('history write failed');
    closeCalls.add(
      CloseRunCall(
        userId: userId,
        programId: programId,
        runId: runId,
        achievementsJson: achievementsJson,
        blockId: blockId,
      ),
    );
    // The record the repository would write back: a completed close review
    // scoped to the block it ended, or to the program when there is none.
    return ProgramReview(
      reviewId: 'review-${closeCalls.length}',
      userId: userId,
      programId: programId,
      programRunId: runId,
      blockId: blockId,
      kind: kReviewKindClose,
      outcome: kOutcomeClosed,
      completedDate: DateTime(2026, 3, 2),
      createdDate: DateTime(2026, 3, 2),
      achievementsJson: achievementsJson,
    );
  }

  @override
  Future<List<DueItem>> fetchDueItems(String userId) async => due;

  @override
  Future<List<ProgramReview>> fetchReviews(String programId) async => reviews;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Derivation ──────────────────────────────────────────────────────────────

class DeriveCall {
  DeriveCall({
    required this.userId,
    required this.from,
    required this.programId,
    this.blockId,
    this.sessionId,
  });

  final String userId;
  final DateTime from;
  final String programId;

  /// The scope the caller asked about, which is what decides whether the
  /// report covers one block, one workout or every run of the program. Null is
  /// the program's own scope, never "unknown".
  final String? blockId;

  /// The narrower session scope, when the review examines one workout.
  final String? sessionId;
}

class FakeAchievementsDerivation implements AchievementsDerivation {
  final calls = <DeriveCall>[];

  @override
  Future<ProgramAchievements> derive({
    required String userId,
    required DateTime from,
    required String programId,
    DateTime? until,
    String? blockId,
    String? sessionId,
  }) async {
    calls.add(
      DeriveCall(
        userId: userId,
        from: from,
        programId: programId,
        blockId: blockId,
        sessionId: sessionId,
      ),
    );
    return ProgramAchievements(from: from);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Programs, workouts, exercises ───────────────────────────────────────────

/// Covers what the two program view models read on load and on a goal/goal-
/// delete; everything else throws, which is the point.
class FakeProgramRepository implements ProgramRepository {
  FakeProgramRepository({List<Program>? programs, List<Goal>? goals})
    : programs = programs ?? [testProgram()],
      goals = goals ?? [];

  List<Program> programs;
  List<Goal> goals;
  List<ProgramBlock> blocks = const [];
  final deletedPrograms = <String>[];

  /// Every goal a view model has asked to create, in order.
  ///
  /// Recorded rather than applied for the same reason [FakePlannedSessions]
  /// records its moves: what the screen got right is *which scope it filed the
  /// goal under*, and a fake that stored the goal itself would hide a caller
  /// that passed the wrong block. It is applied as well, so the reload that
  /// follows a create sees the row it just wrote.
  final createdGoals = <Goal>[];

  @override
  Future<void> createGoal(String userId, Goal goal) async {
    createdGoals.add(goal);
    goals = [...goals, goal];
  }

  @override
  Future<List<Program>> fetchPrograms(String userId) async => programs;

  @override
  Future<Program?> fetchProgram(String programId) async {
    for (final p in programs) {
      if (p.programId == programId) return p;
    }
    return null;
  }

  @override
  Future<List<ProgramBlock>> fetchBlocks(String programId) async => blocks;

  @override
  Future<List<Goal>> fetchGoals(
    String userId, {
    String? programId,
    String? blockId,
    String? programRunId,
  }) async => goals;

  @override
  Future<void> deleteProgram(String programId) async {
    deletedPrograms.add(programId);
    programs = [
      for (final p in programs)
        if (p.programId != programId) p,
    ];
  }

  /// Every length a view model has asked a program to remember, in order.
  ///
  /// Recorded verbatim — the guard that decides whether a call is worth
  /// making (a block run remembers nothing) lives in the real repository, so
  /// a fake that re-applied it would hide a caller passing the wrong thing.
  final rememberedTargets =
      <({String programId, String? blockId, int? count})>[];

  @override
  Future<void> rememberDefaultTargetSessions(
    String programId, {
    String? blockId,
    required int? targetSessions,
  }) async {
    rememberedTargets.add((
      programId: programId,
      blockId: blockId,
      count: targetSessions,
    ));
  }

  @override
  Future<Map<String, int>> fetchActiveBlockCounts(String userId) async {
    final counts = <String, int>{};
    for (final b in blocks) {
      if (b.isArchived) continue;
      counts[b.programId] = (counts[b.programId] ?? 0) + 1;
    }
    return counts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One recorded file-into-a-block move: which links, and where to.
typedef AssignCall = ({
  String programId,
  List<String> linkIds,
  String? blockId,
});

class FakePlannedSessions implements PlannedSessionRepository {
  List<PlannedSession> workouts = const [];
  List<PlannedSessionProgram> links = const [];

  /// Every [assignLinksToBlock] the screen made, in order. Recorded rather
  /// than applied because the caller's job is the *conversation* — the id of
  /// the link and the block it names — and a fake that re-filed its own list
  /// would hide a caller that passed the wrong link.
  final assignCalls = <AssignCall>[];

  @override
  Future<void> assignLinksToBlock(
    String programId,
    List<String> linkIds,
    String? blockId,
  ) async {
    assignCalls.add((programId: programId, linkIds: linkIds, blockId: blockId));
  }

  @override
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
    String? blockId,
  }) async => workouts;

  @override
  Future<List<PlannedSessionProgram>> fetchProgramLinks(
    String programId, {
    String? blockId,
  }) async => links;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The one repository that cannot be default-constructed off-device:
/// `LessonRepository`'s constructor evaluates the global PowerSync database.
/// Any host test that builds a view model hosting a workout editor must pass
/// this, or construction throws before a single test statement runs.
class FakeLessons implements LessonRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeExercises implements ExerciseRepository {
  /// What the name maps resolve to. A snapshot stores ids only, so a test that
  /// asserts on a rendered noun has to supply the map — and one that asserts a
  /// missing name falls back has to leave it empty.
  Map<String, String> exerciseNames = const {};
  Map<String, String> variationNames = const {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async =>
      const [];

  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => const {};

  @override
  Future<Map<String, String>> fetchExerciseNameMap(String userId) async =>
      exerciseNames;

  @override
  Future<Map<String, String>> fetchVariationNameMap(String userId) async =>
      variationNames;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
