import '../../../data/models/program_history.dart';
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
  })  : _history = historyRepository ?? ProgramHistoryRepository(),
        _programs = programRepository ?? ProgramRepository(),
        _sessions = sessionRepository ?? SessionRepository();

  final ProgramHistoryRepository _history;
  final ProgramRepository _programs;
  final SessionRepository _sessions;

  /// What the program produced between [from] and [until].
  ///
  /// [runId] is what makes this a report on a RUN rather than on the user's
  /// training: PR events are filtered to that run's sessions, so a bench PR hit
  /// mid-way through a different program is not claimed as this one's.
  ///
  /// The frontier that decides what counts as a PR stays GLOBAL — the full
  /// timeline goes into [prsAcrossScopes] and only the resulting events are
  /// filtered. Filtering the sets first would reset the frontier inside the
  /// window and report every decent lift as a PR.
  ///
  /// Goals are deliberately NOT filtered this way. A goal is a target on a
  /// lift ("bench 100 × 1"), and it is met or not by what was actually
  /// benched — which program's session it happened in does not change whether
  /// the user did the thing they said they would.
  ///
  /// [programId] is required because goals are scoped, not owned by a run: the
  /// question "what was being chased here" cannot be answered without knowing
  /// which program (and, when a block was running, which block — see
  /// [Goal.appliesDuring]). [blockId] is the running block, not a filter on
  /// the sessions above.
  Future<ProgramAchievements> derive({
    required String userId,
    required DateTime from,
    required String programId,
    DateTime? until,
    String? blockId,
    String? runId,
  }) async {
    final end = until ?? DateTime.now();

    final sets = await _sessions.loadPastSetsTimeline(userId);
    final sessions = runId == null
        ? const <AchievementSession>[]
        : await _history.fetchRunSessions(runId);
    // The program's own goals, plus the running block's — a union, because a
    // program-level target is being chased inside every one of its blocks.
    final goals = (await _programs.fetchGoals(userId, programId: programId))
        .where((g) => g.appliesDuring(blockId))
        .toList(growable: false);
    final weight = await _history.weightWindow(
      userId: userId,
      from: from,
      to: end,
    );

    var prs = prsAcrossScopes(sets, from, end);
    if (runId != null) {
      final sessionIds = sessions.map((s) => s.sessionId).toSet();
      prs = prs
          .where((e) => sessionIds.contains(e.sessionId))
          .toList(growable: false);
    }

    return ProgramAchievements(
      from: from,
      until: end,
      sessions: sessions,
      prs: prs,
      goals: evaluateGoals(
        goals: goals,
        sets: sets,
        from: from,
        to: end,
        // A goal's own variation narrows what counts as evidence; null means
        // any variation of the exercise, which is how every goal read before
        // the column existed.
        variationIdOf: (g) => g.variationId,
      ),
      weightStart: weight.start,
      weightEnd: weight.end,
    );
  }
}
