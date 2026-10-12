import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';
import 'program_achievements.dart';

/// Assembles a [ProgramAchievements] from the repos.
///
/// Lives here, beside the pure derivation rules rather than on a repository,
/// because `lib/data` never imports `lib/features` — a repository returning
/// [ProgramAchievements] would invert the layering. The rules themselves
/// ([evaluateGoals], [prsAcrossScopes]) are pure and host-tested; this class is
/// only the wiring, so that the review sheet and the run-close path share ONE
/// derivation and cannot disagree about what a program achieved.
class AchievementsDerivation {
  AchievementsDerivation({
    ProgramHistoryRepository? historyRepository,
    ProgramRepository? programRepository,
    SessionRepository? sessionRepository,
    PlannedSessionRepository? plannedSessionRepository,
  }) : _history = historyRepository ?? ProgramHistoryRepository(),
       _programs = programRepository ?? ProgramRepository(),
       _sessions = sessionRepository ?? SessionRepository(),
       _planned = plannedSessionRepository ?? PlannedSessionRepository();

  final ProgramHistoryRepository _history;
  final ProgramRepository _programs;
  final SessionRepository _sessions;

  /// Read for one thing only: which block each reviewed workout sits in, so a
  /// set scope can put the right block goals in force.
  final PlannedSessionRepository _planned;

  /// What the program produced between [from] and [until], at one scope.
  ///
  /// [programId] and [blockId] ARE the scope, and they narrow three things
  /// differently — each on purpose:
  ///
  /// * **Sessions** are the scope's runs inside the window. Null [blockId] is
  ///   the program's scope, which is every run of it: a review of a blocked
  ///   program asks what the program did, and most of what it did happened
  ///   inside a block. [sessionId] narrows further to one planned session's
  ///   logged sessions. Attribution is what keeps this honest — a session with
  ///   no run, or one belonging to another program, is not claimed.
  /// * **PRs** are the window's events among *those* sessions, so a bench PR
  ///   hit mid-way through a different program is not claimed as this one's.
  ///   The frontier that decides what counts as a PR stays GLOBAL — the full
  ///   timeline goes into [prsAcrossScopes] and only the resulting events are
  ///   filtered. Filtering the sets first would reset the frontier inside the
  ///   window and report every decent lift as a PR.
  /// * **Goals** are filtered by [Goal.appliesDuring] rather than by session
  ///   attribution. A goal is a target on a lift ("bench 100 × 1"), and it is
  ///   met or not by what was actually benched — which program's session it
  ///   happened in does not change whether the user did the thing they said
  ///   they would.
  ///
  /// There is no `runId`: a run was the scope when every review was about one,
  /// and a program-scoped review spanning several runs cannot be expressed as
  /// a single one. Where a run's boundaries still matter they arrive as
  /// [from] — [ProgramHistoryRepository.checkpointFor] falls back to the run's
  /// start on a first run.
  ///
  /// [sessionIds] is the same scope in **set** form — a review covers named
  /// workouts, so it asks by workouts: the sessions are those of the named
  /// plans, and the goals in force are the program's own plus the goals of
  /// every block any of them sits in. [blockId] stays for the run-close path,
  /// whose scope is the run: a block run's logged sessions include freestyle
  /// ones a set of planned ids could never name.
  Future<ProgramAchievements> derive({
    required String userId,
    required DateTime from,
    required String programId,
    DateTime? until,
    String? blockId,
    List<String>? sessionIds,
  }) async {
    final end = until ?? DateTime.now();

    final sets = await _sessions.loadPastSetsTimeline(userId);
    final sessions = await _history.fetchScopedSessions(
      programId: programId,
      from: from,
      to: end,
      blockId: blockId,
      sessionIds: sessionIds,
    );
    // The program's own goals, plus the running block's — a union, because a
    // program-level target is being chased inside every one of its blocks.
    // A set scope asks the same question by workouts: the blocks any of them
    // sits in.
    final allGoals = await _programs.fetchGoals(
      userId,
      programId: programId,
    );
    final goalBlocks = sessionIds == null
        ? null
        : {
            for (final link in await _planned.fetchProgramLinks(programId))
              if (sessionIds.contains(link.plannedSessionId)) link.blockId,
          };
    final goals = allGoals
        .where(
          (g) => goalBlocks == null
              ? g.appliesDuring(blockId)
              : g.blockId == null || goalBlocks.contains(g.blockId),
        )
        .toList(growable: false);
    final weight = await _history.weightWindow(
      userId: userId,
      from: from,
      to: end,
    );

    final loggedIds = sessions.map((s) => s.sessionId).toSet();
    final prs = prsAcrossScopes(
      sets,
      from,
      end,
    ).where((e) => loggedIds.contains(e.sessionId)).toList(growable: false);

    return ProgramAchievements(
      from: from,
      until: end,
      sessions: sessions,
      prs: prs,
      goals: evaluateGoals(goals: goals, sets: sets, from: from, to: end),
      weightStart: weight.start,
      weightEnd: weight.end,
    );
  }
}
