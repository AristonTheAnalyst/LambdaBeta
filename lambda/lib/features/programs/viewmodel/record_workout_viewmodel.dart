import 'package:flutter/foundation.dart';

import '../../../data/cache/past_sets_timeline_cache.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/program_content.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../session/model/pr_engine.dart';
import '../model/program_achievements.dart';

/// One workout's story while it is being read: which frozen version is on
/// screen, and which exercise of it.
///
/// The versions are read once, before the page opens — walking between them
/// is a change of what the one page draws, never a read, so a step repaints
/// instead of spinning (2026-10-26). The page owns the marks, the notes and
/// the diff; this owns the *which*: the version on screen, the pair the eye
/// flips across, and the version the marks are read against.
///
/// The state also carries the library context a record's floor reads
/// (2026-10-27): the timeline PRs are derived from, the goals it measures and
/// the exercise notes it shelves. A record is a read, so the context is read
/// live — a PR landed today is still a fact about the exercise the version
/// names — while the version itself stays frozen. All of it is empty until
/// [RecordWorkoutViewModel.loadContext] answers, and every getter treats the
/// empty case as the answer it is.
class RecordWorkoutState {
  const RecordWorkoutState({
    this.versions = const [],
    this.index = -1,
    this.active = 0,
    this.goalTimeline = const [],
    this.allPrEvents = const [],
    this.goals = const [],
    this.lessonsByExercise = const {},
    this.goalSetIds = const {},
  });

  /// The workout's versions, newest first: the current plan when the workout
  /// still exists, then every completed review's end and start.
  final List<WorkoutVersion> versions;

  /// Which version is on screen; -1 when the review this page was opened
  /// from recorded nothing of the workout (a row written before snapshots
  /// existed). That is a fact the page says, not a version to draw.
  final int index;

  /// The exercise on screen, an index into the sorted exercises of the
  /// version on screen. Kept across a step — an index into a list both sides
  /// mostly hold — and clamped where the next version is shorter.
  final int active;

  /// The user's whole timeline, oldest first — what the goals are measured
  /// against, the same list the session floors derive their `G` badges from
  /// (2026-10-27). Empty until the context read lands.
  final List<PastSetRow> goalTimeline;

  /// Every PR the user ever landed, oldest first — the trophy's whole shelf.
  final List<PrEvent> allPrEvents;

  /// Every goal the user owns, any scope. The bullseye filters by exercise.
  final List<Goal> goals;

  /// Exercise notes by exercise id — the note tile's shelf.
  final Map<String, List<Lesson>> lessonsByExercise;

  /// The set ids that met a goal — a PR on one of them draws green in the PR
  /// History sheet, the session floors' rule (2026-10-26).
  final Set<String> goalSetIds;

  WorkoutVersion? get version =>
      index < 0 || index >= versions.length ? null : versions[index];

  bool get hasRecord => version != null;

  ContentSession? get shown => version?.session;

  bool get isStart => version?.isStart ?? false;

  bool get isCurrent => version?.isCurrent ?? false;

  /// The version's exercises in the order the plan itself keeps — the same
  /// sort every session surface draws by, so the card and the floor always
  /// agree about which one is active — **plus the pass's removals** on an
  /// end, which have no row of their own in the snapshot (2026-10-27).
  List<ContentExercise> get exercises {
    final entries =
        [
          for (final exercise in shown?.exercises ?? const <ContentExercise>[])
            (exercise, 0),
          for (final exercise in removedExercises) (exercise, 1),
        ]..sort((a, b) {
          final byOrder = a.$1.exerciseOrder.compareTo(b.$1.exerciseOrder);
          // A removed group shares its old slot with a kept one: it stands after
          // it, so "this was here and is gone" reads below what stayed.
          return byOrder != 0 ? byOrder : a.$2.compareTo(b.$2);
        });
    return [for (final entry in entries) entry.$1];
  }

  /// The review's own start, when the version on screen is its end and that
  /// start holds the workout — the only place a removed group survives. Null
  /// on a start (nothing has been removed yet), on a review that kept only
  /// one document, and on the current plan (no review holds it).
  WorkoutVersion? get startPair {
    final current = version;
    if (current == null || current.side != WorkoutVersionSide.end) return null;
    final pair = sibling;
    return pair != null && pair.session != null ? pair : null;
  }

  /// The exercises the pass removed: held by its start, gone from its end
  /// (2026-10-27). The finish's snapshot drops the removed group, so the end
  /// has no row to mark — the group is drawn from the start's frozen copy
  /// instead, as the ordinary card it had, wearing only the red minus the
  /// added group wears green. Empty wherever there is no start to read a
  /// removal off.
  List<ContentExercise> get removedExercises {
    final start = startPair?.session;
    if (start == null || shown == null) return const [];
    final kept = {
      for (final exercise in shown!.exercises) exercise.plannedExerciseId,
    };
    return [
      for (final exercise in start.exercises)
        if (!kept.contains(exercise.plannedExerciseId)) exercise,
    ];
  }

  /// The planned-exercise ids the card draws as removed on the version on
  /// screen — the set the screen marks with the red minus.
  Set<String> get removedIds => {
    for (final exercise in removedExercises) exercise.plannedExerciseId,
  };

  /// The exercise on the card, clamped when a step lands on a shorter
  /// version — never past the end, and null on a version with none.
  ContentExercise? get activeExercise {
    final list = exercises;
    if (list.isEmpty) return null;
    return list[active.clamp(0, list.length - 1)];
  }

  /// There is a version older than the one on screen.
  bool get canStepOlder => hasRecord && index < versions.length - 1;

  /// There is a version newer than the one on screen.
  bool get canStepNewer => hasRecord && index > 0;

  /// The other side of the review the version on screen belongs to — the
  /// pair the eye flips across. Null on the current plan, which no review
  /// recorded, and on a review that kept only one of its two documents.
  WorkoutVersion? get sibling {
    final current = version;
    if (current == null || current.reviewId == null || current.isCurrent) {
      return null;
    }
    for (final other in versions) {
      if (other.reviewId == current.reviewId &&
          other.isStart != current.isStart) {
        return other;
      }
    }
    return null;
  }

  /// Whether the eye is offered. Both sides must hold the workout: a flip
  /// onto a page saying "the workout was not there" would read as data gone
  /// missing, which is the one thing a record must never look like.
  bool get canFlip {
    final pair = sibling;
    return pair != null && pair.session != null && shown != null;
  }

  /// The newest version any review left — what the current plan is read
  /// against, so its marks say what has changed since the last record.
  WorkoutVersion? get newestEnd {
    for (final version in versions) {
      if (version.side == WorkoutVersionSide.end) return version;
    }
    return null;
  }

  /// The version the marks are read against: on a review version its own
  /// review's other side; on the current plan the newest end, because there
  /// is no "before" but the last record.
  WorkoutVersion? get markReference => isCurrent ? newestEnd : sibling;

  /// The review's exercise notes, keyed by `planned_exercise_id`. Only an end
  /// version carries notes — they are the pass's product, not the state it
  /// found — so a start or a current version answers empty.
  Map<String, String> get exerciseNotes => version?.exerciseNotes ?? const {};

  /// The review's note for the workout as a whole, under the same rule.
  String? get workoutNote => version?.workoutNote;

  RecordWorkoutState copyWith({
    List<PastSetRow>? goalTimeline,
    List<PrEvent>? allPrEvents,
    List<Goal>? goals,
    Map<String, List<Lesson>>? lessonsByExercise,
    Set<String>? goalSetIds,
  }) => RecordWorkoutState(
    versions: versions,
    index: index,
    active: active,
    goalTimeline: goalTimeline ?? this.goalTimeline,
    allPrEvents: allPrEvents ?? this.allPrEvents,
    goals: goals ?? this.goals,
    lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
    goalSetIds: goalSetIds ?? this.goalSetIds,
  );
}

/// Owns the walk over one workout's versions (2026-10-26).
///
/// Every version is already in hand when this is built, so the walk is
/// synchronous: [stepOlder] / [stepNewer] move along the stack and [flip]
/// jumps to the other side of the review on screen — the eye — with no reads
/// in between and no spinner to show.
///
/// The floor's doors, though, are live reads (2026-10-27): [loadContext]
/// brings the timeline, the PR feed, the goals and the exercise notes in once,
/// after the page has already drawn, and the doors answer from them exactly as
/// the planner's and the session floors' do. A failed read leaves its shelf
/// empty — a door that cannot answer is quiet, never a blocker.
class RecordWorkoutViewModel extends ValueNotifier<RecordWorkoutState> {
  RecordWorkoutViewModel({
    List<WorkoutVersion> versions = const [],
    int initialIndex = 0,
    String? userId,
    Future<List<PastSetRow>> Function(String userId)? timelineLoader,
    LessonRepository? lessonRepository,
    ProgramRepository? programRepository,
  }) : _userId = userId,
       _timelineLoader =
           timelineLoader ?? ((id) => PastSetsTimelineCache.instance.get(id)),
       _lessonRepoOverride = lessonRepository,
       _programRepoOverride = programRepository,
       super(
         RecordWorkoutState(
           versions: List<WorkoutVersion>.unmodifiable(versions),
           index: initialIndex >= 0 && initialIndex < versions.length
               ? initialIndex
               : -1,
         ),
       );

  final String? _userId;
  final Future<List<PastSetRow>> Function(String userId) _timelineLoader;
  final LessonRepository? _lessonRepoOverride;
  final ProgramRepository? _programRepoOverride;

  // Built on first use, not in the constructor: the repositories open the
  // database as they are made, and a record with no user (a host test) must
  // be constructible without one (2026-10-27).
  late final LessonRepository _lessonRepo =
      _lessonRepoOverride ?? LessonRepository();
  late final ProgramRepository _programRepo =
      _programRepoOverride ?? ProgramRepository();

  bool _contextLoaded = false;
  bool _contextLoading = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The floor's shelves, read once (2026-10-27): the timeline (through the
  /// shared cache — the first reader pays the query), the goal list, the
  /// lessons for every exercise any version holds. Each read is swallowed on
  /// failure: a record must draw whatever answered.
  Future<void> loadContext() async {
    final userId = _userId;
    if (userId == null || _contextLoaded || _contextLoading) return;
    _contextLoading = true;

    var timeline = const <PastSetRow>[];
    try {
      timeline = await _timelineLoader(userId);
    } catch (_) {
      // The shelves are extras on a record; an unanswered read is quiet.
    }
    // Oldest first — the order the goal engine and the PR feed walk in. The
    // cache's `asc` copy is the same sort; sorting here keeps the loader
    // seam a plain list.
    final asc = [...timeline]
      ..sort((a, b) {
        final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
        return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
      });

    var goals = const <Goal>[];
    try {
      goals = [
        for (final option in await _programRepo.fetchGoalOptions(userId))
          option.goal,
      ];
    } catch (_) {
      // The bullseye reads 0; the other doors still answer.
    }

    final exerciseIds = <String>{
      for (final version in value.versions)
        for (final exercise in version.session?.exercises ?? const [])
          if (exercise.exerciseId != null) exercise.exerciseId!,
    };
    var lessons = const <String, List<Lesson>>{};
    if (exerciseIds.isNotEmpty) {
      try {
        lessons = await _lessonRepo.fetchLessonsForExercises(
          userId,
          exerciseIds.toList(),
        );
      } catch (_) {
        // The note tile reads 0; its sheet still opens on an empty shelf.
      }
    }

    _contextLoading = false;
    _contextLoaded = true;
    if (_disposed) return;
    value = value.copyWith(
      goalTimeline: asc,
      allPrEvents: prEvents(asc),
      goals: goals,
      lessonsByExercise: lessons,
      goalSetIds: goalAchievingSetIds(goals: goals, sets: asc),
    );
  }

  /// Older — one step down the stack, toward the workout's first record. No
  /// move at the oldest end.
  void stepOlder() {
    if (!value.canStepOlder) return;
    _moveTo(value.index + 1);
  }

  /// Newer — one step up the stack, toward the current plan. No move at the
  /// newest end.
  void stepNewer() {
    if (!value.canStepNewer) return;
    _moveTo(value.index - 1);
  }

  /// The eye: the same workout on the other side of the review on screen. A
  /// no-op where there is no pair to flip across — the current plan, or a
  /// review whose other side does not hold the workout.
  void flip() {
    if (!value.canFlip) return;
    final pair = value.sibling!;
    final at = value.versions.indexOf(pair);
    if (at >= 0) _moveTo(at);
  }

  /// Switching exercises is looking, and stays — on every version. The index
  /// is clamped when drawn, so a shorter version never lands nowhere.
  void selectExercise(int index) {
    if (index == value.active) return;
    value = RecordWorkoutState(
      versions: value.versions,
      index: value.index,
      active: index,
      goalTimeline: value.goalTimeline,
      allPrEvents: value.allPrEvents,
      goals: value.goals,
      lessonsByExercise: value.lessonsByExercise,
      goalSetIds: value.goalSetIds,
    );
  }

  void _moveTo(int index) {
    value = RecordWorkoutState(
      versions: value.versions,
      index: index,
      active: value.active,
      goalTimeline: value.goalTimeline,
      allPrEvents: value.allPrEvents,
      goals: value.goals,
      lessonsByExercise: value.lessonsByExercise,
      goalSetIds: value.goalSetIds,
    );
  }

  // ── The floor's shelves (2026-10-27) ─────────────────────────────────────

  /// Every PR [exerciseId] ever landed — all its variations, oldest first —
  /// the trophy's feed, the same one the planner and the session floors open.
  List<PrEvent> prHistoryFor(String exerciseId) => [
    for (final event in value.allPrEvents)
      if (event.exerciseId == exerciseId) event,
  ];

  /// How many PRs the exercise ever landed — what lights the trophy.
  int prCountFor(String exerciseId) =>
      value.allPrEvents.where((e) => e.exerciseId == exerciseId).length;

  List<Lesson> lessonsFor(String exerciseId) =>
      value.lessonsByExercise[exerciseId] ?? const [];

  int lessonCountFor(String exerciseId) => lessonsFor(exerciseId).length;

  /// The exercise's notes, re-read on demand — the notes modal's own loading
  /// path, the same shape the editor and the session VMs give it.
  Future<void> loadLessonsFor(String exerciseId) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final lessons = await _lessonRepo.fetchLessons(userId, exerciseId);
      if (_disposed) return;
      final map = Map<String, List<Lesson>>.from(value.lessonsByExercise);
      map[exerciseId] = lessons;
      value = value.copyWith(lessonsByExercise: map);
    } catch (_) {
      // The shelf keeps what it had.
    }
  }

  List<Goal> goalsForExercise(String exerciseId) => [
    for (final goal in value.goals)
      if (goal.exerciseId == exerciseId) goal,
  ];

  /// How many of the exercise's goals still stand — what lights the bullseye.
  /// Ownership is [goalCompletionSet]'s call, the same rule the goals sheet
  /// and the `G` badge use, over the record's timeline.
  int openGoalsFor(String exerciseId) {
    var open = 0;
    for (final goal in goalsForExercise(exerciseId)) {
      if (goalCompletionSet(goal: goal, sets: value.goalTimeline) == null) {
        open++;
      }
    }
    return open;
  }
}
