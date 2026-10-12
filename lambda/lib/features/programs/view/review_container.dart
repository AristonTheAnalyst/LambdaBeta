import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_content.dart';
import '../../../data/models/program_review.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/floating_bar.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../goals/view/goal_row.dart';
import '../../goals/view/goal_sheet.dart';
import '../../reviews/view/review_scope_sheet.dart';
import '../model/program_achievements.dart';
import '../model/program_content_diff.dart';
import '../viewmodel/workout_editor_viewmodel.dart';
import 'content_diff_sheet.dart';
import 'plan_session_screen.dart';
import 'record_workout_screen.dart';
import 'review_notes_sheet.dart';
import 'review_workout_note_sheet.dart';

/// The review currently being taken, or null.
///
/// A review is not a screen. It is a *ceremony* around the editors that already
/// exist: you pick a scope, the normal editor opens for it, you look through
/// the plan and change what needs changing, and when you finish the plan is
/// snapshotted onto the review row. That is why this is above the navigator
/// rather than a route — the bar has to survive drilling into a workout, and
/// the editor has to be the real one, not a copy.
///
/// Deliberately a plain top-level notifier, matching `themeNotifier`: the
/// session outlives every route in the stack, which is exactly the lifetime no
/// widget owns.
final reviewSessionNotifier = ValueNotifier<ReviewSession?>(null);

/// The open review's per-exercise notes, keyed by `planned_exercise_id`.
///
/// Top-level and short-lived for the same reason [reviewSessionNotifier] is:
/// a note belongs to the pass, not to any one route — the user drills from a
/// workout list into a workout and back, and what they wrote at either depth
/// has to be visible at both. Seeded from the row when the review opens,
/// cleared with it, and updated by [saveReviewExerciseNote] so the screen
/// always shows what the row holds.
final reviewNotesNotifier = ValueNotifier<Map<String, String>>(const {});

/// Records — or, with a blank [note], clears — one exercise's note on the
/// open review.
///
/// The row is written FIRST and the notifier only follows: the database is
/// what survives a leaving, and a save that failed must not leave the screen
/// showing a note the record does not have. [ProgramHistoryRepository]
/// re-reads the row before merging the key, so what is held here being stale
/// can never drop another exercise's note.
Future<void> saveReviewExerciseNote({
  required String reviewId,
  required String plannedExerciseId,
  required String? note,
}) async {
  final text = note?.trim() ?? '';
  await ProgramHistoryRepository().setExerciseNote(
    reviewId,
    plannedExerciseId,
    note: text.isEmpty ? null : text,
  );
  final next = Map<String, String>.of(reviewNotesNotifier.value);
  if (text.isEmpty) {
    next.remove(plannedExerciseId);
  } else {
    next[plannedExerciseId] = text;
  }
  reviewNotesNotifier.value = next;
}

/// The open review's per-workout notes, keyed by `planned_session_id`.
///
/// The workout-level sibling of [reviewNotesNotifier]: what was said about a
/// workout as a whole, rather than about one lift inside it. Same lifetime and
/// the same contract — seeded from the row when the review opens, cleared with
/// it, and kept in step with the record by [saveReviewWorkoutNote].
final reviewWorkoutNotesNotifier = ValueNotifier<Map<String, String>>(const {});

/// Records — or, with a blank [note], clears — one workout's note on the open
/// review.
///
/// Deliberately identical to [saveReviewExerciseNote]: the row is written
/// FIRST and the notifier only follows, because the database is what survives
/// a leaving, and a save that failed must not leave the bar showing a note the
/// record does not have. [ProgramHistoryRepository] re-reads the row before
/// merging the key, so what is held here being stale can never drop another
/// workout's note.
Future<void> saveReviewWorkoutNote({
  required String reviewId,
  required String plannedSessionId,
  required String? note,
}) async {
  final text = note?.trim() ?? '';
  await ProgramHistoryRepository().setWorkoutNote(
    reviewId,
    plannedSessionId,
    note: text.isEmpty ? null : text,
  );
  final next = Map<String, String>.of(reviewWorkoutNotesNotifier.value);
  if (text.isEmpty) {
    next.remove(plannedSessionId);
  } else {
    next[plannedSessionId] = text;
  }
  reviewWorkoutNotesNotifier.value = next;
}

/// What the review ceremony is currently examining. Everything the bar, the
/// landing and the notes sheet need, carried forward by [copyWith] as the pass
/// advances.
class ReviewSession {
  const ReviewSession({
    required this.reviewId,
    required this.programId,
    required this.sessionIds,
    this.goalIds = const [],
    this.reviewed = const {},
    this.activeSessionId,
    this.activeWorkoutName,
    this.title,
    this.sinceDate,
    this.achievements,
  });

  final String reviewId;

  /// The program this pass belongs to, or null — a **standalone** review,
  /// which is what the library's Reviews tab starts: the set and the goals
  /// are the whole scope, and there is no program behind either.
  final String? programId;

  /// The workouts this pass covers, in the order the picker listed them. The
  /// set is the scope — there is no other.
  final List<String> sessionIds;

  /// The goals the pass picked, in the order the picker listed them. A review
  /// contains workouts **and** goals; this is the goals half of it. An id that
  /// no longer resolves is dropped where the goals are read, not here.
  final List<String> goalIds;

  /// Which of [sessionIds] have been Done, and when. Read back from the row
  /// when a resume opens it, so ticks survive leaving the app.
  final Map<String, DateTime> reviewed;

  /// The workout currently open under the bar, or null on the landing. This is
  /// what decides the bar's mode: with a workout under it the verbs are Note,
  /// Compare and Done, without one they are Finish.
  final String? activeSessionId;

  /// The open workout's display name, so the Note sheet can say which workout
  /// it is about without re-reading the row. Follows [activeSessionId]:
  /// cleared with it, replaced when another workout opens.
  final String? activeWorkoutName;

  /// What the pass is called, when the user named it.
  final String? title;

  /// Where the "since" window opens — the completion of the previous review
  /// covering these workouts, or the run's start. Null hides the line.
  final DateTime? sinceDate;

  /// What the program produced inside that window, carried to the finish sheet
  /// rather than shown on the review itself.
  ///
  /// The workouts are where the plan is examined; this is the context for the
  /// notes written at the end, and the notes are the record of *why* the plan
  /// now says what it says. Captured at start because the derivation belongs to
  /// the history screen that already ran it — re-deriving here would read the
  /// whole training history a second time for a sheet the user may never open.
  /// Null for a standalone pass, which has no program to derive against.
  final ProgramAchievements? achievements;

  /// True while the landing is the page under the bar.
  bool get isOverview => activeSessionId == null;

  /// The pass with the open workout deliberately hidden — what the
  /// landing-side bars read.
  ///
  /// The landing is never showing a workout, even in the windows where
  /// [activeSessionId] is set: it is set BEFORE the editor is pushed — so the
  /// editor's chrome comes up already wearing the workout's verbs — and
  /// cleared once that route is gone, and the landing is visible through both
  /// transitions. A landing bar that read the flag live would swap its verbs
  /// the instant a card is tapped, while the editor is still sliding in (and
  /// swap them back under its exit). Hiding it here keeps the bar's mode a
  /// fact of the SCREEN: the route's own bar is the pass's, the pushed
  /// editor's bar is the workout's, whatever the notifier currently says.
  ReviewSession get asLanding => copyWith(clearActiveSession: true);

  /// How many of the set have been Done.
  int get reviewedCount =>
      sessionIds.where(reviewed.containsKey).length;

  /// The same pass with the scope, the ticks, or the open workout moved on.
  ///
  /// Replaces the object rather than mutating it, so identity checks against
  /// [reviewSessionNotifier]'s value must compare [reviewId] instead.
  ReviewSession copyWith({
    List<String>? sessionIds,
    List<String>? goalIds,
    Map<String, DateTime>? reviewed,
    String? activeSessionId,
    String? activeWorkoutName,
    bool clearActiveSession = false,
  }) {
    return ReviewSession(
      reviewId: reviewId,
      programId: programId,
      sessionIds: sessionIds ?? this.sessionIds,
      goalIds: goalIds ?? this.goalIds,
      reviewed: reviewed ?? this.reviewed,
      activeSessionId: clearActiveSession
          ? null
          : activeSessionId ?? this.activeSessionId,
      activeWorkoutName: clearActiveSession
          ? null
          : activeWorkoutName ?? this.activeWorkoutName,
      title: title,
      sinceDate: sinceDate,
      achievements: achievements,
    );
  }
}

/// Publishes the ambient [ReviewSession] to the whole tree, above the
/// navigator so every pushed route and `useRootNavigator` sheet is a
/// descendant. That is what lets the editor's own bottom bar carry the review
/// bar without either knowing about the other.
class ReviewScope extends InheritedNotifier<ValueNotifier<ReviewSession?>> {
  ReviewScope({super.key, required super.child})
    : super(notifier: reviewSessionNotifier);

  static ReviewSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReviewScope>()
      ?.notifier
      ?.value;
}

/// Opens the ceremony for [session] — pushes the editor route and puts the bar
/// up. The future resolves with the review route's result: [true] finished,
/// [false] left.
///
/// Refuses while another review is already open. The session is a single
/// top-level notifier, so two live reviews would fight over it — the second
/// route's dispose tears the first bar down. The buttons are disabled first;
/// this is the backstop behind them.
Future<bool?> startReview(BuildContext context, ReviewSession session) {
  if (reviewSessionNotifier.value != null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('A review is already open.')),
    );
    return Future<bool?>.value();
  }
  reviewSessionNotifier.value = session;
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: kReviewRouteName),
      builder: (_) => ReviewRoute(session: session),
    ),
  );
}

/// Walks the navigator back out of a review: everything the user drilled into
/// on top of the review route, then the review route itself, carrying [result]
/// back to whoever awaited [startReview].
///
/// Returns whether a review route was actually in the stack. The notifier is
/// checked first because `popUntil` with a predicate that never matches pops
/// **everything** — an editor with no review under it must not be unwound by
/// what it believed was a tab tap.
bool unwindReview(BuildContext context, {bool? result}) {
  if (reviewSessionNotifier.value == null) return false;
  final nav = Navigator.of(context, rootNavigator: true);
  var atReview = false;
  nav.popUntil((route) {
    if (route.settings.name == kReviewRouteName) atReview = true;
    return atReview;
  });
  if (atReview) nav.pop(result);
  return atReview;
}

/// The name [startReview]'s route carries, so the bar can unwind back to it
/// after a finish without knowing how deep the user drilled.
const kReviewRouteName = 'lambda-review';

/// The name the record route carries — deliberately not [kReviewRouteName]:
/// that name is what [unwindReview] pops down to, and a record must never be
/// what a live pass unwinds into.
const kReviewRouteNameRecord = 'lambda-review-record';

/// The record [openCompletedReview] opens, built from a completed row and the
/// set the list resolved for it — never the row's raw columns, which are null
/// on legacy rows.
ReviewSession completedReviewSession({
  required ProgramReview review,
  required List<String> sessionIds,
}) => ReviewSession(
  reviewId: review.reviewId,
  programId: review.programId,
  sessionIds: sessionIds,
  goalIds: review.storedGoalIds ?? const [],
  reviewed: review.reviewedSessions,
  title: review.title,
);

/// Opens a completed review as a record: the same landing the pass had, read
/// only.
///
/// Nothing is published to [reviewSessionNotifier] — a record is not a pass
/// being taken — so the route can never disturb a pass running elsewhere, and
/// [ReviewRoute]'s dispose never clears a session it did not set. Refuses
/// while a pass is live for the mirror-image reason [startReview] refuses:
/// the notifier and the ceremony answer for one review at a time.
Future<bool?> openCompletedReview(
  BuildContext context,
  ReviewSession session,
) {
  if (reviewSessionNotifier.value != null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('A review is already open.')),
    );
    return Future<bool?>.value();
  }
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: kReviewRouteNameRecord),
      builder: (_) => ReviewRoute(session: session, readOnly: true),
    ),
  );
}

/// The review's landing, and the base the workouts are drilled into from.
///
/// It owns the editor those workouts open in — a bare
/// [WorkoutEditorViewModel], because a pass is not an editor *of* anything:
/// there is no program behind a standalone review, and the editor reads only
/// the workout it is handed. The set itself is re-resolved from the live rows
/// whenever that editor closes, so a rename or a deletion made in there shows
/// here rather than being remembered stale.
class ReviewRoute extends StatefulWidget {
  const ReviewRoute({
    super.key,
    required this.session,
    this.readOnly = false,
    this.userId,
    this.plannedRepository,
    this.programRepository,
    this.exerciseRepository,
    this.historyRepository,
  });

  final ReviewSession session;

  /// Whether this route is a record — a completed pass opened to be read.
  /// A record never touches [reviewSessionNotifier] and never writes.
  final bool readOnly;

  /// The signed-in user the landing resolves goal names for. Overridable for
  /// the same reason `ReviewsViewModel`'s is: a host test cannot construct
  /// `Supabase.instance` at all.
  final String? userId;

  /// The stores the landing resolves its cards with — injectable so a host
  /// test can render a landing with no database under it. Null = the real
  /// repositories; a real caller never passes one.
  final PlannedSessionRepository? plannedRepository;
  final ProgramRepository? programRepository;
  final ExerciseRepository? exerciseRepository;

  /// The store a record reads its snapshot through — same seam rules as the
  /// three above. A pass never touches it from here: the writes it makes run
  /// through the ceremony's own verbs.
  final ProgramHistoryRepository? historyRepository;

  @override
  State<ReviewRoute> createState() => _ReviewRouteState();
}

class _ReviewRouteState extends State<ReviewRoute> {
  /// The editor drilled-into workouts share — one piece of state instead of a
  /// copy per push, so going back to the landing and opening another workout
  /// cannot accumulate editors that disagree.
  ///
  /// Built on the first open, not with the route: a record never opens one,
  /// and constructing a [WorkoutEditorViewModel] evaluates the global
  /// PowerSync database through its lesson repository — which is also what
  /// lets a host test render a record with no database under it.
  WorkoutEditorViewModel? _editor;
  WorkoutEditorViewModel get _editorFor => _editor ??= WorkoutEditorViewModel();

  late final _planned = widget.plannedRepository ?? PlannedSessionRepository();
  late final _programs = widget.programRepository ?? ProgramRepository();
  late final _exercises = widget.exerciseRepository ?? ExerciseRepository();
  late final _history =
      widget.historyRepository ?? ProgramHistoryRepository();

  /// The set as the landing shows it, resolved from the live rows — null
  /// until the read lands, so a card never shows a workout the read has not
  /// confirmed is still there.
  List<_ReviewCard>? _cards;

  /// The goals the pass picked, resolved for the landing — null until the
  /// read lands. An id that no longer resolves is dropped, not shown as a
  /// hole.
  List<_GoalCard>? _goals;

  bool get _loading => _cards == null || _goals == null;

  /// The pass as it stands: the live session rather than the one this route
  /// opened with, because the scope can be edited while the pass runs (the add
  /// sheet). Falls back to the opening session when the notifier is empty or
  /// holds a different review — the guard every read here applies by id.
  ReviewSession get _session {
    final live = reviewSessionNotifier.value;
    return (live != null && live.reviewId == widget.session.reviewId)
        ? live
        : widget.session;
  }

  /// The signed-in user — the route's injected one in a test, the real
  /// session otherwise. Only evaluated where goals resolve.
  String get _userId => widget.userId ?? _currentUserId();

  @override
  void initState() {
    super.initState();
    // A record's notes are the live pass's, not the row's — the notifiers are
    // this ceremony's working state, and a record opens none.
    if (!widget.readOnly) _seedNotes();
    _loadCards();
    _loadGoals();
  }

  /// Resolves the set from the live rows — once at open, and again after
  /// every editor pop: the pass exists to edit these workouts, so a rename
  /// made in there has to show here, and a workout deleted in there has to
  /// drop.
  ///
  /// A workout that no longer resolves is skipped, not fatal: it is no longer
  /// available, and the landing says how many were dropped rather than
  /// pretending the set was always this size. The card itself is the name and
  /// the tick (2026-10-10) — where the workout sits and how big it is are not
  /// read for it.
  Future<void> _loadCards() async {
    final ids = _session.sessionIds;
    final cards = <_ReviewCard>[];
    for (final id in ids) {
      final workout = await _planned.fetchPlannedSessionById(id);
      if (workout == null) continue;
      cards.add(_ReviewCard(workout: workout));
    }
    if (!mounted) return;
    setState(() => _cards = cards);
  }

  /// Resolves the goals the pass picked, in the order they were picked.
  ///
  /// The row is built live ([goalExerciseNameFor] / [goalTargetValue]), the
  /// same rule goals follow everywhere: a renamed exercise renames it here
  /// too. A missing id drops silently — the set shrinks rather than the
  /// landing growing a card for something that is not there.
  Future<void> _loadGoals() async {
    final ids = _session.goalIds;
    final options = await _programs.fetchGoalOptionsByIds(ids);
    final byId = {for (final o in options) o.goal.goalId: o};
    final details = byId.isEmpty
        ? const <String, ExerciseDetail>{}
        : await _exercises.fetchExerciseDetailMap(_userId);

    final goals = <_GoalCard>[];
    for (final id in ids) {
      final option = byId[id];
      if (option == null) continue;
      goals.add(
        _GoalCard(
          goal: option.goal,
          exerciseName: goalExerciseNameFor(option.goal, details),
          target: goalTargetValue(
            option.goal.targetWeight,
            option.goal.targetReps,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _goals = goals);
  }

  /// Loads the notes the review already carries — it may be a resume, and the
  /// pass may have been left and come back to. Both levels in one read: the
  /// per-exercise notes and the per-workout ones live on the same row.
  ///
  /// Guarded on the session still being this one: a second review can replace
  /// the notifier while this read is in flight, and the late maps must not
  /// land on it. A read that fails leaves the maps empty rather than blocking
  /// the editor — the bar shows no note, and re-taking it writes through the
  /// repository's own fresh read, so nothing is lost but the display.
  void _seedNotes() {
    ProgramHistoryRepository().fetchReview(widget.session.reviewId).then((row) {
      if (!mounted || row == null) return;
      // Compared by id, not identity: the session is replaced as the pass
      // advances ([ReviewSession.copyWith]), so the object that started this
      // read is no longer the value even while the same review is open.
      if (reviewSessionNotifier.value?.reviewId != widget.session.reviewId) {
        return;
      }
      reviewNotesNotifier.value =
          Map<String, String>.unmodifiable(row.exerciseNotes);
      reviewWorkoutNotesNotifier.value =
          Map<String, String>.unmodifiable(row.workoutNotes);
    });
  }

  @override
  void dispose() {
    // Only clear what is still ours. A second review started from within the
    // first (or a sign-out redirect, or a hot restart) disposes this route
    // with a different session already live, and blanking that one would tear
    // the bar out from under the review the user is actually in.
    //
    // Deferred past the frame, because the write notifies `ReviewScope`,
    // which marks itself needing to build — and the cases this guard exists
    // for (a hot restart, a router redirect) unmount the tree *during* a
    // build. Writing here directly tripped "setState() or markNeedsBuild()
    // called when widget tree was locked" on every hot restart.
    // Ours is judged by review id, not identity: the session is replaced as
    // the pass advances ([ReviewSession.copyWith]), so the object that opened
    // this route is no longer the live value even while the same review is
    // open. A record never owns the notifier, and says so structurally rather
    // than by the id happening not to match.
    final reviewId = widget.session.reviewId;
    if (!widget.readOnly &&
        reviewSessionNotifier.value?.reviewId == reviewId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (reviewSessionNotifier.value?.reviewId == reviewId) {
          reviewSessionNotifier.value = null;
          // The notes go with the session they belong to. Both are guarded by
          // the same identity check: clearing a DIFFERENT review's notes would
          // blank the bars of the review the user is actually in.
          reviewNotesNotifier.value = const {};
          reviewWorkoutNotesNotifier.value = const {};
        }
      });
    }
    // Safe despite children holding it: they are pushed routes, and a route
    // can only be disposed after everything above it has gone. Null for a
    // record, which never built one.
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The live copy: Done and opening a workout replace it through the
    // notifier, and both the bar and the landing read whatever lands there.
    //
    // Registered only for a pass — a record reads its own session, and
    // depending on the notifier would let a pass running elsewhere re-render
    // it. The lookup still happens (`maybeOf`) so the dependency is declared
    // in the one branch that wants it.
    final scoped = ReviewScope.maybeOf(context);
    final live = (!widget.readOnly &&
            scoped != null &&
            scoped.reviewId == widget.session.reviewId)
        ? scoped
        : widget.session;
    if (_loading) {
      return _ReviewShell(
        session: live,
        readOnly: widget.readOnly,
        body: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final cards = _cards!;
    // Every workout in the set is gone — deleted between the pass being
    // started and being opened. Only then is there nothing to walk; a partial
    // drop is noted on the landing instead.
    if (cards.isEmpty) return _missing(live);
    return _ReviewLanding(
      session: live,
      cards: cards,
      goals: _goals!,
      missingCount: live.sessionIds.length - cards.length,
      readOnly: widget.readOnly,
      // A pass opens the real editor; a record opens the workout as the
      // record has it — a different reader for a different question.
      onOpen: widget.readOnly
          ? _openRecordWorkout
          : (card) => _openWorkout(live, card),
      onScopeChanged: _syncScope,
      onGoalDescriptionChanged: _setGoalDescription,
      onFinish: widget.readOnly
          ? null
          : () => _finishPass(
              live,
              label: cards.length == 1 ? cards.first.name : null,
            ),
    );
  }

  /// Re-reads the pass after the add sheet closed, and resolves the landing
  /// again.
  ///
  /// The row is the truth and the sheet the editor: reading the scope back
  /// rather than trusting what the sheet said means a dismissal mid-edit, a
  /// rollback, or a write that landed differently all end the same way — with
  /// the landing showing what the pass actually covers. Nothing is re-resolved
  /// when neither half moved, so a sheet closed without a tick costs one read
  /// and no rebuild.
  Future<void> _syncScope() async {
    final row = await ProgramHistoryRepository().fetchReview(
      widget.session.reviewId,
    );
    if (!mounted) return;
    final current = reviewSessionNotifier.value;
    final ids = row?.storedSessionIds;
    if (row == null || current == null || ids == null) return;
    if (current.reviewId != row.reviewId) return;
    // Both halves: a goal ticked on its own leaves the workout list identical,
    // and reading that as "nothing changed" would drop the edit the sheet just
    // wrote.
    final goalIds = row.storedGoalIds ?? const <String>[];
    if (listEquals(ids, current.sessionIds) &&
        listEquals(goalIds, current.goalIds)) {
      return;
    }

    reviewSessionNotifier.value = current.copyWith(
      sessionIds: ids,
      goalIds: goalIds,
    );
    await _loadCards();
    await _loadGoals();
  }

  /// Writes a goal's notes from the landing's focused sheet, then rebuilds
  /// the card in place — the sheet reads the goal row it was opened with, so
  /// a card left stale would show the old text on the next tap.
  ///
  /// Failures propagate: the write comes from a live box, and the sheet that
  /// owns it is the one that keeps the text and says it could not save.
  Future<void> _setGoalDescription(String goalId, String description) async {
    await ProgramRepository().updateGoalDescription(goalId, description);
    if (!mounted) return;
    final goals = _goals;
    if (goals == null) return;
    final text = description.trim();
    setState(() {
      _goals = [
        for (final card in goals)
          if (card.goal.goalId == goalId)
            _GoalCard(
              goal: text.isEmpty
                  ? card.goal.copyWith(clearDescription: true)
                  : card.goal.copyWith(description: text),
              exerciseName: card.exerciseName,
              target: card.target,
            )
          else
            card,
      ];
    });
  }

  /// Opens one workout: the real editor, on the root navigator, with the
  /// pass's bar in place of its own.
  ///
  /// [ReviewSession.activeSessionId] is what tells the bar which mode it is
  /// in, and it is set — with the workout's display name, which the Note sheet
  /// titles itself with — before the push so the workout's chrome comes up
  /// already wearing the review's verbs. It is cleared when the workout route
  /// is disposed — however it went — so the landing's bar offers Finish again.
  /// Both moments are on this side of the transition: the landing never reads
  /// the flag ([ReviewSession.asLanding]) and the editor's bar stops reading
  /// it only once its route is actually gone ([_WorkoutRoute]), so neither
  /// screen's bar moves before the screen carrying it does.
  Future<void> _openWorkout(ReviewSession session, _ReviewCard card) async {
    reviewSessionNotifier.value = session.copyWith(
      activeSessionId: card.sessionId,
      activeWorkoutName: card.name,
    );
    await Navigator.of(context, rootNavigator: true).push(
      _WorkoutRoute(
        reviewId: session.reviewId,
        workoutId: card.sessionId,
        builder: (_) =>
            PlanSessionScreen(viewModel: _editorFor, workout: card.workout),
      ),
    );
    if (!mounted) return;
    // The editor may have renamed (or deleted) the workout it was opened on —
    // the landing reads the live rows, so it re-resolves the set now.
    _loadCards();
  }

  /// Opens one workout AS THE RECORD HAS IT — the completed review's two
  /// states of it, read only, with the review's own notes.
  ///
  /// Both sides come off the row: the workout as the review found it
  /// (`baseline`, captured when the pass began) and as it completed it
  /// (`snapshot`). The reader flips between them; neither is the live plan,
  /// which keeps being edited and would otherwise rewrite history under it.
  ///
  /// The row is read before the push, not in the screen: the record is one
  /// read of one row, and the route already holds every seam needed to make it
  /// (the reader itself takes plain data and loads nothing, which is also what
  /// keeps the loading and no-record states out of it).
  ///
  /// A row with no snapshot — a dismissed completion, or one written before
  /// snapshots existed — resolves to no record and the reader says so, rather
  /// than drawing an empty grid that would read as "no sets". No baseline and
  /// there is simply one side: the reader offers no eye.
  Future<void> _openRecordWorkout(_ReviewCard card) async {
    final row = await _history.fetchReview(widget.session.reviewId);
    if (!mounted) return;

    // One side of the review's documents, narrowed to this workout. Narrowing
    // is the pass's own read ([contentInScope]) — the review covers a set, and
    // this screen is about one workout of it.
    ContentSession? side(ProgramContent? content) {
      if (content == null) return null;
      final scoped = contentInScope(content, sessionId: card.sessionId);
      return scoped.sessions.isEmpty ? null : scoped.sessions.first;
    }

    final before = side(row?.baseline);
    final after = side(row?.snapshot);
    // Names come from the library, live — the record stores ids, and a rename
    // shows through here as it does everywhere else.
    var names = const <String, String>{};
    var variationNames = const <String, String>{};
    if (before != null || after != null) {
      names = await _exercises.fetchExerciseNameMap(_userId);
      variationNames = await _exercises.fetchVariationNameMap(_userId);
      if (!mounted) return;
    }

    // The bar's own reading of the pass: the ticks the row recorded, with this
    // workout open under it. Built from the row when it is still there, and
    // from the session the landing opened this record with when it is not.
    final session =
        (row == null
                ? widget.session
                : completedReviewSession(
                    review: row,
                    sessionIds: widget.session.sessionIds,
                  ))
            .copyWith(
              activeSessionId: card.sessionId,
              activeWorkoutName: card.name,
            );

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordWorkoutScreen(
          session: session,
          name: card.name,
          before: before,
          after: after,
          beforeDate: row?.createdDate,
          afterDate: row?.completedDate,
          exerciseNotes: row?.exerciseNotes ?? const {},
          workoutNote: row?.workoutNotes[card.sessionId],
          exerciseNames: names,
          variationNames: variationNames,
        ),
      ),
    );
  }

  /// Finishes the pass: the whole set is snapshotted, and the ticks that were
  /// made are kept as the record of what was walked.
  ///
  /// Unticked workouts do not block a finish — the user may have seen all they
  /// need — but they are asked about once, because the tick is the explicit
  /// "finished with this one" and silence would let it pass for one.
  Future<void> _finishPass(ReviewSession session, {String? label}) async {
    final done = session.reviewedCount;
    final total = session.sessionIds.length;
    if (done < total) {
      if (!await confirmPartialFinish(context, reviewed: done, total: total) ||
          !mounted) {
        return;
      }
    }

    final notes = await showReviewNotesSheet(
      context,
      session: session,
      label: label,
    );
    // Dismissed the sheet — back to the landing, still reviewing.
    if (notes == null || !mounted) return;

    try {
      await ProgramHistoryRepository().completeReview(
        session.reviewId,
        userId: _currentUserId(),
        outcome: kOutcomeReviewed,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      // Unwind only — `ReviewRoute`'s dispose clears the notifier once the
      // route is actually gone, which is what lets the bar ride the pop
      // transition out instead of the page reflowing under it.
      unwindReview(context, result: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finish the review: $e')),
      );
    }
  }

  /// Every workout in the set is gone — deleted between the pass being
  /// started and being opened. Says so rather than opening the wrong editor or
  /// a blank screen, and still offers Finish on a live pass: a pass whose
  /// workouts no longer exist is the one review nothing else in the UI can
  /// close out. A record offers neither — it is closed, and the next Close
  /// answers false where [unwindReview] would no-op with no notifier set.
  Widget _missing(ReviewSession session) => _ReviewShell(
    session: session,
    readOnly: widget.readOnly,
    onFinish: widget.readOnly ? null : () => _finishPass(session),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The workouts in this review are no longer available.',
              textAlign: TextAlign.center,
              style: AppFonts.ui(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: () => widget.readOnly
                  ? Navigator.of(context, rootNavigator: true).pop(false)
                  : unwindReview(context, result: false),
              child: Text(
                'Close',
                style: AppFonts.ui(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The one question a finish with unticked work asks: "[reviewed] of [total]
/// reviewed — finish anyway?".
///
/// Asked once, and only when work is left: the tick is the explicit "finished
/// with this one", so a silent finish would let the unticked workouts pass for
/// walked. It does not block — the user may have seen all they need — and
/// everything in the set is saved with the review either way, ticked or not.
///
/// Top-level so the wording and the abort are pinnable without a database
/// under the route: the landing's finish is the caller, and it must not go on
/// to the notes sheet unless this comes back true.
Future<bool> confirmPartialFinish(
  BuildContext context, {
  required int reviewed,
  required int total,
}) async {
  final finish = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '$reviewed of $total reviewed',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
      content: Text(
        'Finish anyway? The workouts left unticked are saved with the '
        'review as they stand.',
        style: AppFonts.ui(color: AppColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Keep reviewing',
            style: AppFonts.ui(color: AppColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Finish anyway',
            style: AppFonts.ui(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return finish == true;
}

/// The editor push a review does, carrying the pass so its disposal marks the
/// pass back on the landing.
///
/// The mark cannot ride the `await push`: a route's future resolves when the
/// pop BEGINS, and clearing [ReviewSession.activeSessionId] then would strip
/// the workout's verbs off its bar while the editor is still sliding out —
/// the same early flip, mirrored. Disposal lands once the route is actually
/// gone (after the exit transition), so the workout's bar rides its own exit
/// out, exactly as the pass's bar rides [ReviewRoute]'s (see `_finishPass`).
class _WorkoutRoute extends MaterialPageRoute<void> {
  _WorkoutRoute({
    required super.builder,
    required this.reviewId,
    required this.workoutId,
  });

  final String reviewId;
  final String workoutId;

  @override
  void dispose() {
    // Deferred past the frame, same as ReviewRoute's: the navigator can
    // finalize a route while the tree is locked, and the write below notifies
    // ReviewScope.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _clearActiveSession(reviewId, workoutId),
    );
    super.dispose();
  }
}

/// Marks the pass as back on the landing, when the workout route is gone.
///
/// Guarded on the review still being this one and the open workout still being
/// this route's: the pass may have been replaced entirely while the workout
/// route was up, and a newer workout's flag is never an older route's to
/// clear.
void _clearActiveSession(String reviewId, String workoutId) {
  final current = reviewSessionNotifier.value;
  if (current == null || current.reviewId != reviewId) return;
  if (current.activeSessionId != workoutId) return;
  reviewSessionNotifier.value = current.copyWith(clearActiveSession: true);
}

/// The container's chrome for its two states that have no landing under them:
/// still loading, and the set that is gone.
///
/// A bare page with the review's bar floating at the floor, so a way out
/// exists everywhere. Without it the only exit is the system back gesture,
/// which takes the route away leaving the review open with nothing on screen
/// saying so. Finish is offered only where the caller can honestly finish —
/// nothing is loaded while the set is still arriving.
class _ReviewShell extends StatelessWidget {
  const _ReviewShell({
    required this.session,
    required this.body,
    this.onFinish,
    this.readOnly = false,
  });

  final ReviewSession session;
  final Widget body;

  /// Finishes the pass from the shell. Null while the set is still loading —
  /// there is nothing loaded to record — and on a record, which is closed
  /// already.
  final Future<void> Function()? onFinish;

  /// Whether this shell stands over a record — its bar reads "Review
  /// Complete" while the cards load, like the landing's does.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FloatingBarOverlay(
        // The shell is the route's own page, never a workout's — [asLanding]
        // keeps its bar in the pass's mode through the windows where an
        // editor is being pushed or popped over it.
        bar: ReviewBar(
          session: session.asLanding,
          onFinish: onFinish,
          readOnly: readOnly,
        ),
        child: body,
      ),
    );
  }
}

/// The review's first page: the workouts the pass covers and the goals it
/// picked, as two tabs rather than one list under the other.
///
/// This is the landing the ceremony opens on and returns to, and it is where
/// the pass is finished — Finish is a decision about the whole set, and the
/// set is what this page shows. A ticked card says the workout was Done: the
/// tick is the record of walking it, not of opening it.
///
/// The two halves switch rather than stack: a long workout list buried the
/// goals at its foot, and goals have no less claim to the top of the page.
/// The bar below stays the whole set's, whichever tab is up.
class _ReviewLanding extends StatefulWidget {
  const _ReviewLanding({
    required this.session,
    required this.cards,
    required this.goals,
    required this.missingCount,
    required this.onOpen,
    required this.onScopeChanged,
    required this.onGoalDescriptionChanged,
    required this.onFinish,
    this.readOnly = false,
  });

  final ReviewSession session;
  final List<_ReviewCard> cards;

  /// The goals the pass covers, resolved. A goal has no editor — it is read,
  /// not walked — so its card opens the focused sheet instead of a route.
  final List<_GoalCard> goals;

  /// Workouts in the set that no longer resolve — dropped from the cards but
  /// still part of what the review covers.
  final int missingCount;

  /// Whether this landing is a record — a completed pass opened to be read.
  /// A record keeps the same lists and ticks, loses every affordance that
  /// writes, and gains the Summary tab.
  final bool readOnly;

  final ValueChanged<_ReviewCard> onOpen;

  /// Called after the add sheet closes: the pass may cover a different set of
  /// workouts and goals now, and the route above re-reads it.
  final Future<void> Function() onScopeChanged;

  /// Writes a goal's notes from the focused sheet. The route above owns the
  /// row and the rebuild; this page only hands the write through.
  final Future<void> Function(String goalId, String description)
  onGoalDescriptionChanged;

  /// Finishes the pass. Null on a record — it is closed already.
  final Future<void> Function()? onFinish;

  @override
  State<_ReviewLanding> createState() => _ReviewLandingState();
}

/// One tab of the landing's strip. An ordered list rather than bare indices:
/// the record's third tab would otherwise make a stored `1` mean two different
/// things, and the list is the strip's own order.
enum _LandingTab {
  workouts('Workouts'),
  goals('Goals'),
  summary('Summary');

  const _LandingTab(this.label);

  final String label;
}

class _ReviewLandingState extends State<_ReviewLanding> {
  /// Which half of the pass is showing. Workouts first: the walking happens
  /// there, and a pass cannot have none.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // A pass with no goals gets no second tab — not an empty one: the strip
    // is the claim that there is something under it.
    final goals = widget.goals;
    // The Summary tab is the record's: what the pass produced, read once it
    // is over. An open pass has no such promise to make, and a legacy
    // program review with no goals reads Workouts | Summary.
    final tabs = <_LandingTab>[
      _LandingTab.workouts,
      if (goals.isNotEmpty) _LandingTab.goals,
      if (widget.readOnly) _LandingTab.summary,
    ];
    final tab = tabs[_tab.clamp(0, tabs.length - 1)];
    // Reviewed = workouts ticked + goals holding a status report (2026-10-10):
    // the two halves of the pass, counted off the cards and rows actually on
    // screen. A row the landing could not resolve — a workout or goal since
    // deleted — is left out of the tally: it cannot be walked or reported, and
    // a count it held would be a gate that never opens.
    final workoutsReviewed = widget.cards
        .where((card) => session.reviewed.containsKey(card.sessionId))
        .length;
    final goalsReported = goals.where((goal) => goal.reported).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FloatingBarOverlay(
        // The bar alone again: the add control that used to rise off it is a
        // tile in the list now, where the row it would add lands.
        //
        // [asLanding]: the page under this bar is the pass, even in the
        // moment a card is tapped and the editor is still sliding in — see
        // the getter for why the landing must not follow `activeSessionId`.
        bar: ReviewBar(
          session: session.asLanding,
          readOnly: widget.readOnly,
          onFinish: widget.onFinish,
          // The count and the Finish gate both read the whole pass, both
          // halves — this is the one bar that can see all of it. A record's
          // bar does not read the count at all: the walk is over.
          overviewProgress: widget.readOnly
              ? null
              : (
                  done: workoutsReviewed + goalsReported,
                  total: widget.cards.length + goals.length,
                ),
        ),
        child: Builder(
          // Below the overlay, so the inset knows a bar is there.
          builder: (context) => Column(
            children: [
              PageHeader(
                title: session.title ?? 'Review',
                left: IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.primary),
                  // A record is not unwound — nothing is open to unwind — so
                  // its arrow pops the route it is on.
                  onPressed: () => widget.readOnly
                      ? Navigator.of(context, rootNavigator: true).pop(false)
                      : unwindReview(context, result: false),
                ),
              ),
              if (tabs.length > 1)
                SlideTabBar(
                  tabs: [for (final t in tabs) t.label],
                  activeIndex: tabs.indexOf(tab),
                  onTap: (i) => setState(() => _tab = i),
                  // The dot rides the half that still holds something
                  // unreviewed — the same halves the bar's count stands on, so
                  // the gate always points at its own reason (2026-10-10). A
                  // record is not asking for anything: no dot, however the
                  // pass was left.
                  dotTabs: widget.readOnly
                      ? const {}
                      : {
                          if (workoutsReviewed < widget.cards.length) 0,
                          if (goalsReported < goals.length) 1,
                        },
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    FloatingBarOverlay.contentInset(context),
                  ),
                  children: switch (tab) {
                    _LandingTab.workouts => _workoutList(),
                    _LandingTab.goals => _goalList(),
                    _LandingTab.summary => _summaryList(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds more workouts or goals to a pass that is already running: the scope
  /// sheet, opened on the half whose tile was tapped — and on that half alone,
  /// the other riding along untouched — then the landing resolved again: the
  /// pass may cover a different set now, and the bar's count and the tabs are
  /// read off it.
  Future<void> _addToReview(ReviewScopeSection section) async {
    final session = widget.session;
    await showReviewScopeSheet(
      context,
      reviewId: session.reviewId,
      userId: _currentUserId(),
      sessionIds: session.sessionIds,
      goalIds: session.goalIds,
      section: section,
    );
    if (!mounted) return;
    await widget.onScopeChanged();
  }

  /// Takes one workout out of the pass — the swipe card's verb.
  ///
  /// The write is the scope sheet's own ([ProgramHistoryRepository
  /// .setReviewScope]): the row is what the pass is, and the landing then
  /// re-reads it rather than trusting the list it just drew. Order is
  /// preserved and nothing else is touched, so a workout the landing could not
  /// resolve stays in the scope instead of being quietly dropped along with
  /// the one that was swiped.
  ///
  /// The last workout is refused, in the sheet's own words: removal here can
  /// empty the set in a single gesture, and a review with no workouts is the
  /// one shape a review cannot have.
  Future<void> _removeWorkout(_ReviewCard card) async {
    final session = widget.session;
    if (session.sessionIds.length <= 1) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'A review needs at least one workout — add another before '
            'taking this one out.',
          ),
        ),
      );
      return;
    }
    try {
      await ProgramHistoryRepository().setReviewScope(
        session.reviewId,
        sessionIds: [
          for (final id in session.sessionIds)
            if (id != card.sessionId) id,
        ],
        goalIds: session.goalIds,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not remove the workout: $e')),
      );
      return;
    }
    if (!mounted) return;
    await widget.onScopeChanged();
  }

  /// Every workout the pass covers, one card each, with the count of any that
  /// no longer resolve.
  ///
  /// A swipe takes a workout out of the pass — the same edit the scope sheet
  /// writes, made where the set is read rather than behind an extra visit. The
  /// card's own tap opens the workout, so the drawer is the gesture's only
  /// vocabulary, and it matches the swipe-to-reveal the app uses everywhere it
  /// offers a per-row verb.
  ///
  /// A record's cards keep their tap — they open the workout as the record
  /// has it, read only — but lose the drawer and the add tile: the set is what
  /// it was, and a record is a reading.
  List<Widget> _workoutList() {
    final missingCount = widget.missingCount;
    return [
      for (final card in widget.cards) ...[
        if (widget.readOnly)
          _WorkoutCard(
            card: card,
            reviewed: widget.session.reviewed.containsKey(card.sessionId),
            onTap: () => widget.onOpen(card),
          )
        else
          SwipeActions(
            // Keyed by the workout so a removal never hands an open drawer's
            // state to the card that slides up into its place.
            key: ValueKey(card.sessionId),
            actions: [
              SwipeAction(
                icon: Icons.remove_circle_outline,
                label: 'Remove',
                color: AppColors.danger,
                onTap: () => _removeWorkout(card),
              ),
            ],
            child: _WorkoutCard(
              card: card,
              // Read from the live session at build time, not baked into the
              // card, so a tick shows the moment it is recorded.
              reviewed: widget.session.reviewed.containsKey(card.sessionId),
              onTap: () => widget.onOpen(card),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
      // Directly under the last card, where the next one would land — that is
      // the claim the shape makes, so the prose below it comes after. The label
      // says what a tap does; this page's tiles are the only way into the scope
      // sheet, so the bare glyph the circle wore is not enough.
      if (!widget.readOnly)
        _AddTile(
          label: 'Add workouts to review',
          // The rows' own radius, like the goals tile: the cards above it are
          // md now (2026-10-10).
          radius: AppRadius.md,
          onPressed: () => _addToReview(ReviewScopeSection.workouts),
        ),
      if (missingCount > 0) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          missingCount == 1
              ? '1 workout in this review is no longer available.'
              : '$missingCount workouts in this review are no longer available.',
          style: AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted),
        ),
      ],
    ];
  }

  /// The goals the pass covers. A goal has no editor — it is read, not walked
  /// — so a row opens the focused sheet instead of a route; the same sheet the
  /// Library's Goals tab opens, so a pass is a second door into one view
  /// rather than a second view.
  ///
  /// A record's rows open the same sheet with no writer wired: the report it
  /// would take is already made, so the sheet reads the goal back whole — its
  /// description and the history the axes stand on — with edit mode gone.
  List<Widget> _goalList() => [
    for (final goal in widget.goals) ...[
      if (widget.readOnly)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showGoalSheet(
            context,
            goal: goal.goal,
            exerciseName: goal.exerciseName,
            onDescriptionChanged: null,
            // The axes are the goal's live history, read the same way the
            // pass reads them: a goal is read, not walked, and a completed
            // review did not freeze the sets it measures.
            loadPastSets: () =>
                SessionRepository().loadPastSetsTimeline(_currentUserId()),
          ),
          child: GoalRow(
            exerciseName: goal.exerciseName,
            target: goal.target,
            onDelete: null,
          ),
        )
      else
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showGoalSheet(
            context,
            goal: goal.goal,
            exerciseName: goal.exerciseName,
            onDescriptionChanged: (description) =>
                widget.onGoalDescriptionChanged(goal.goal.goalId, description),
            // The history is read here, not fetched with the card: a pass can
            // run for a while, and the sheet's whole point is the axes as they
            // stand now.
            loadPastSets: () =>
                SessionRepository().loadPastSetsTimeline(_currentUserId()),
          ),
          child: GoalRow(
            exerciseName: goal.exerciseName,
            target: goal.target,
            // No × on the review's copy: an open pass is not where a goal is
            // deleted, and the row is read here, not managed.
            onDelete: null,
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
    ],
    // Same shape as the rows above, at the rows' own radius: this one is a
    // goal row that has not been filled in yet.
    if (!widget.readOnly)
      _AddTile(
        label: 'Add goals to review',
        onPressed: () => _addToReview(ReviewScopeSection.goals),
        radius: AppRadius.md,
      ),
  ];

  /// The record's third tab, a placeholder for now — an empty state in the
  /// app's own voice, so the strip's claim that something lives under it is
  /// not a lie.
  List<Widget> _summaryList() => [
    Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Text(
        'Nothing here yet.',
        textAlign: TextAlign.center,
        style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
      ),
    ),
  ];
}

/// The other place to add to a pass: a card-shaped hole at the foot of the
/// list it would add to.
///
/// It borrows the shape of the rows above it — same radius, same outline — so
/// it reads as one of them that has not been filled in: the next workout would
/// land exactly here. That is the one thing a floating control cannot say,
/// which is why this shape is the one the landing keeps.
///
/// Flat: no fill, no blur, no shadow. All it takes from the floating layer is
/// its rim — [ContainerTone.outlineBright], bright enough to read where
/// [ContainerTone.outline]'s house hairline is not — and the accent its add
/// carries everywhere else.
class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.label,
    required this.onPressed,
    this.radius = AppRadius.lg,
  });

  /// What a tap adds — the words say it, so the glyph need not spell it out:
  /// it leads the line, because the tile is an addition, not a row.
  final String label;

  final VoidCallback onPressed;

  /// The radius of the list this tile ends — workout cards are
  /// [AppRadius.lg] ([AppCard]), goal rows [AppRadius.md].
  final double radius;

  /// Height. Shallower than a card on purpose: a full-height tile would read
  /// as a row, and this is the absence of one.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque: the tile's fill is transparent, so the drag area is the whole
      // box rather than the label.
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: height,
        decoration: lambdaBox(ContainerTone.outlineBright, radius: radius),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One goal on the landing, resolved against the live rows.
class _GoalCard {
  const _GoalCard({
    required this.goal,
    required this.exerciseName,
    required this.target,
  });

  /// The row itself — the focused sheet reads it (targets, variation, and the
  /// notes it edits), so the card carrying only a label would have to be
  /// looked up again the moment it is tapped.
  final Goal goal;

  /// The exercise's live name, built with [goalExerciseNameFor].
  final String exerciseName;

  /// The target, built with [goalTargetValue] — the row's own right-aligned
  /// element, the same split the review pickers' rows make (2026-10-10).
  final String target;

  /// Whether the goal holds its status report — the sheet's own text field.
  /// That is what "reviewed" means for a goal (2026-10-10): a target is
  /// examined by saying how it stands, and nothing else on the row can
  /// carry it.
  bool get reported => goal.description?.trim().isNotEmpty ?? false;
}

/// One workout on the landing, resolved against the live rows.
class _ReviewCard {
  const _ReviewCard({required this.workout});

  final PlannedSession workout;

  String get sessionId => workout.sessionId;
  String get name => toProperCase(workout.name);
}

/// One workout's card: its name, and whether the pass has walked it.
///
/// Nothing else — no block, no exercise count, no "Done" and no date
/// (2026-10-10): what the pass needs from a workout at a glance is whether it
/// has been examined, and the tick says it the way the pickers' rows do.
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.card,
    required this.reviewed,
    required this.onTap,
  });

  final _ReviewCard card;

  /// Whether this pass has Done the workout. True = the green tick, the
  /// record of walking it; false = nothing, like an unticked picker row.
  final bool reviewed;

  /// What the card opens: on a pass the workout under the pass's bar, on a
  /// record the same workout as the record has it — the route decides which,
  /// and the card is a door either way.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      // The goal rows' own box (2026-10-10): the landing's two lists are one
      // stack with two kinds of row in it, so a workout card wears the same
      // radius, padding, text size and weight as a goal card, and only the
      // contents differ.
      radius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          if (reviewed) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.check_circle, size: 14, color: AppColors.success),
          ],
        ],
      ),
    );
  }
}

/// Puts the review's bar over [child] while a review runs, and leaves [child]
/// bare when none does.
///
/// The pass is a ceremony around the editors, and it holds the floor: the
/// bottom of the screen belongs to the review for as long as it is open. Where
/// the editor has its own chrome below ([editorNavBar]) that chrome stands
/// down; where the page is one of the states with no editor at all — an
/// editor's own loading or failure page — this is what keeps the bar on
/// screen.
///
/// Pass null [settle] where there is no editor underneath: nothing has been
/// examined, so the bar offers only what it can honestly offer.
///
/// [onComparison] is the same rule for Compare, in the other direction: it is
/// the surface that can show a comparison, so a bar built without one does not
/// offer the verb. [comparing] is that surface saying the record is up.
///
/// Changes is the deliberate exception to the rule: its sheet shows itself, so
/// it rides only on a workout being open — a page with no editor underneath
/// (nothing to settle) still offers the read, because the sheet is the whole
/// of what the button is.
///
/// [onExerciseTap] is a screen offering its own body to the sheet: a row in
/// the sheet opens the exercise on the screen below it — the editor's workout,
/// or a snapshot's record. A page that holds no exercises (or a bar with
/// nothing under it) leaves it null, and the sheet's exercise cards are simply
/// inert.
/// [readOnly] is for the page that is itself a record: a completed review's
/// workout, read with the pass's own chrome. Its bar wears the record's
/// settled state and locks every verb that writes ([ReviewBar.readOnly]).
///
/// [session] is the pass the bar is over, when it is not the one in scope —
/// the same record reader, which is a pass being READ rather than a pass being
/// taken and so publishes nothing for the scope to find. Null reads the scope,
/// which is every bar during a pass.
Widget reviewChrome(
  BuildContext context, {
  required Widget child,
  required Future<bool> Function()? settle,
  Future<bool> Function()? settleForCompare,
  ValueChanged<ReviewComparison?>? onComparison,
  bool comparing = false,
  bool readOnly = false,
  ReviewSession? session,
  Future<ReviewComparison> Function()? loadComparison,
  Widget? aboveBar,
  ValueChanged<String>? onExerciseTap,
}) {
  final resolved = session ?? ReviewScope.maybeOf(context);
  if (resolved == null) return child;
  final settleNow = settle;
  return FloatingBarOverlay(
    above: aboveBar,
    bar: ReviewBar(
      session: resolved,
      settleForCompare: settleForCompare,
      onComparison: onComparison,
      comparing: comparing,
      readOnly: readOnly,
      loadComparison: loadComparison,
      onExerciseTap: onExerciseTap,
      // Done is the review's verb for one workout, and its mark needs the
      // editor's save underneath it: a tick over unsaved edits would say
      // "finished with this one" about a change that never landed. The
      // un-mark asks nothing, so it comes through the same wiring. No settle
      // to give, no toggle to offer.
      onSetDone: settleNow == null
          ? null
          : (done) =>
                setActiveWorkoutDone(context, settle: settleNow, done: done),
    ),
    child: child,
  );
}

/// The workout's Note: the sheet, and the write of whatever it returns.
///
/// Called from the editor's header — the control sits beside the workout's
/// name, which is what the note is about. Write-through like the exercise
/// notes — the note belongs to the pass, and a save that failed must not leave
/// the header showing a note the record does not have, so the notifier only
/// moves in [saveReviewWorkoutNote], after the row has landed.
Future<void> editActiveWorkoutNote(
  BuildContext context,
  ReviewSession session,
) async {
  final workoutId = session.activeSessionId;
  if (workoutId == null) return;
  final next = await showReviewWorkoutNoteSheet(
    context,
    workoutName: session.activeWorkoutName ?? 'This workout',
    initialValue: reviewWorkoutNotesNotifier.value[workoutId] ?? '',
  );
  if (next == null) return;
  try {
    await saveReviewWorkoutNote(
      reviewId: session.reviewId,
      plannedSessionId: workoutId,
      note: next,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Could not save the note: $e')),
    );
  }
}

/// The workout's Done, both directions: records the tick on the review, or
/// takes it back off. Done is a decision, and a decision made by mistake is
/// unmade by the same button.
///
/// Settle first — but only on the way in. Done means "finished with this one"
/// and a tick over unsaved edits would say that when it is not true, so the
/// mark asks the editor to land first and a save that failed keeps the user in
/// the workout. Un-marking claims nothing about the editor — it retracts a
/// claim — so it asks nothing and settles nothing: a pending edit stays
/// pending, and the editor's own back guard still owns it.
///
/// The write goes to the row before the map is updated: the database is what
/// survives leaving, and a screen showing a tick the record does not have is
/// the one outcome worth avoiding.
///
/// The open workout stays open either way — the tick is a state of the workout
/// under the bar, not a way out of it. The bar reads it straight back off the
/// session ([ReviewSession.reviewed] by [ReviewSession.activeSessionId]), so
/// the press is answered where it was made and leaving stays the header's.
Future<void> setActiveWorkoutDone(
  BuildContext context, {
  required Future<bool> Function() settle,
  required bool done,
}) async {
  final session = reviewSessionNotifier.value;
  final workoutId = session?.activeSessionId;
  if (session == null || workoutId == null) return;
  if (done && !await settle()) return;
  if (!context.mounted) return;

  final history = ProgramHistoryRepository();
  try {
    if (done) {
      await history.markWorkoutReviewed(session.reviewId, workoutId);
    } else {
      await history.unmarkWorkoutReviewed(session.reviewId, workoutId);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Could not record this workout: $e'
              : 'Could not unmark this workout: $e',
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;

  final current = reviewSessionNotifier.value;
  if (current == null || current.reviewId != session.reviewId) return;
  final reviewed = Map<String, DateTime>.of(current.reviewed);
  if (done) {
    reviewed[workoutId] = DateTime.now();
  } else {
    reviewed.remove(workoutId);
  }
  reviewSessionNotifier.value = current.copyWith(reviewed: reviewed);
}

/// The plan editors' own chrome.
///
/// Outside a review it is the app's floating nav bar, which they draw
/// themselves because they are pushed on the root navigator over the tab
/// shell. Inside one it is the review's own bar — the same container, the
/// pass's controls in place of the tabs — because a review is a ceremony, not
/// somewhere to browse, and two floating bars stacked at the floor was a
/// worse answer than either alone.
///
/// One helper for all of them so the chrome, the tabs it lights and the
/// one-way exit through the unsaved-changes guard cannot drift between
/// editors. Tab taps belong to the nav bar and the guard behind it; during a
/// review there is no nav bar, and the pass leaves through the editor's own
/// back guard instead.
Widget editorNavBar(
  BuildContext context, {
  required Widget child,
  required ValueChanged<int> onTap,
  required Future<bool> Function()? settle,
  Future<bool> Function()? settleForCompare,
  ValueChanged<ReviewComparison?>? onComparison,
  bool comparing = false,
  Widget? aboveBar,
  ValueChanged<String>? onExerciseTap,
}) {
  final session = ReviewScope.maybeOf(context);
  if (session != null) {
    return reviewChrome(
      context,
      child: child,
      settle: settle,
      settleForCompare: settleForCompare,
      onComparison: onComparison,
      comparing: comparing,
      aboveBar: aboveBar,
      onExerciseTap: onExerciseTap,
    );
  }
  return ScrollShrinkNavBar(
    currentIndex: libraryTabIndex,
    onTap: onTap,
    items: appTabItems,
    aboveBar: aboveBar,
    child: child,
  );
}

/// The two sides of a review's comparison, scoped to what the review is
/// looking at, plus the names the diff renders them with.
class ReviewComparison {
  const ReviewComparison({
    required this.before,
    required this.after,
    required this.exerciseNames,
    this.variationNames = const {},
    this.beforeNotes = const {},
  });

  /// The plan at the last finished review of this scope — or as found when
  /// this pass began. Null when neither was recorded.
  final ProgramContent? before;

  final ProgramContent after;

  final Map<String, String> exerciseNames;

  /// Variation names by id, resolved live — the documents carry ids only, and
  /// a changes sheet has to read "Bench Press · Paused" rather than a uuid.
  /// Same doctrine as [exerciseNames]; defaulted so a comparison built without
  /// a library in hand (tests) still reads.
  final Map<String, String> variationNames;

  /// What [before]'s review said about its exercises, keyed by
  /// `planned_exercise_id` — the record's own note box. Notes live on the
  /// review row rather than in the document, so whoever draws the record has
  /// to be handed them. Empty for a baseline (the plan as found had no notes
  /// of its own), and defaulted so a comparison built without them reads.
  final Map<String, String> beforeNotes;
}

/// Gathers everything a comparison taken mid-review needs.
///
/// The "after" side is built live because the pass IS the editing: what the
/// review has changed is exactly the difference between the plan as last
/// reviewed (or as found) and the plan as it stands. Live means the pass's own
/// scope — the whole program for a program review, the picked set and goals
/// for a standalone one.
///
/// Compare is a per-workout verb — it runs from inside one workout — so both
/// documents are narrowed to [ReviewSession.activeSessionId]: the "before"
/// side is the newest completed review whose set **contains** that workout
/// (its whole-program snapshot narrowed the same way), else this pass's own
/// baseline. A workout nobody has reviewed yet says "no earlier version"
/// rather than borrowing a neighbour's comparison.
Future<ReviewComparison> loadReviewComparison(
  ReviewSession session, {
  required String userId,
}) async {
  final workoutId = session.activeSessionId;
  if (workoutId == null) {
    throw StateError('Compare needs a workout open.');
  }
  final history = ProgramHistoryRepository();
  final review = await history.fetchReview(session.reviewId);
  final base = review == null
      ? null
      : await history.comparisonBase(review, sessionId: workoutId);
  final programId = session.programId;
  final live = programId == null
      ? await history.buildContentForSessions(
          userId: userId,
          sessionIds: session.sessionIds,
          goalIds: session.goalIds,
        )
      : await history.buildContent(userId: userId, programId: programId);
  final library = ExerciseRepository();
  final names = await library.fetchExerciseNameMap(userId);
  final variations = await library.fetchVariationNameMap(userId);

  return ReviewComparison(
    before: base == null
        ? null
        : contentInScope(base.content, sessionId: workoutId),
    after: contentInScope(live, sessionId: workoutId),
    exerciseNames: names,
    variationNames: variations,
    beforeNotes: base?.notes ?? const {},
  );
}

/// What the bar says once the workout on screen has been ticked: the answer to
/// Done, and the resting state it leaves behind it — the bar stays on the
/// workout, reading this, with the floor turned green.
const String kReviewCompleteLabel = 'Review Complete';

/// What a record's workout bar names the side on screen (2026-10-12): the
/// workout as the pass completed it — where the screen opens — and, once the
/// eye is pressed, the workout as the pass found it. A record is the one bar
/// whose two documents are both frozen, so its label reads the side rather
/// than the walk, and the walking words ([kReviewCompleteLabel], 'In Review',
/// 'Previously') stay where something is still moving.
const String kReviewAfterLabel = 'After Review';
const String kReviewBeforeLabel = 'Before Review';

/// How long the label takes to change — the rise [kReviewCompleteLabel] comes
/// in on, and the way back for every other label it swaps with.
const Duration _labelSwap = Duration(milliseconds: 180);

/// The review's bar: the app's floating container, carrying the pass instead
/// of the tabs.
///
/// While a review runs this is the only chrome at the floor — the nav bar
/// stands down for the length of the ceremony. The bar reads its mode off the
/// session: **overview** (the landing, no workout open) shows how far the pass
/// has got and Finish; **workout** shows the workout's verbs as glyphs, in the
/// order they are reached for — **Compare** (a toggle, not a one-shot: it
/// turns the workout's sets into the record and back, so the button reads
/// pressed while the record is up — the eye fills and the label turns to
/// 'Previously' — the leftmost, because reading the record is
/// what the pass is for) **· Changes** (the same comparison as a card per
/// exercise — changed or not — always new vs old, so it restores the current
/// contents first) **· Note** (the workout's own, bright once the pass holds
/// one) **· Done** (a tick, and a toggle — a decision about the workout,
/// answered where it is made: the tick landing turns the bar green and reads
/// [kReviewCompleteLabel], tapping it again takes the tick back off and the
/// bar returns to the pass's own words, and the workout stays on screen under
/// it both ways). Leaving
/// is not on the bar at all: the pass is left the way the editor is left,
/// through its own back guard (the header's arrow, the iOS back-swipe, the
/// system back button), so the bar holds decisions about the review rather
/// than about navigation.
class ReviewBar extends StatefulWidget {
  const ReviewBar({
    super.key,
    required this.session,
    this.readOnly = false,
    this.settleForCompare,
    this.onComparison,
    this.comparing = false,
    this.onFinish,
    this.onSetDone,
    this.loadComparison,
    this.onExerciseTap,
    this.overviewProgress,
  });

  final ReviewSession session;

  /// Whether this bar is over a record — a completed pass opened to be read.
  /// A record is a walk that has happened: over a workout the label names the
  /// frozen side on screen ([kReviewAfterLabel], accented rim and words, the
  /// way the eye's own reading is; [kReviewBeforeLabel] once the eye is
  /// pressed, so the swap is seen as well as read), and on the landing it
  /// reads [kReviewCompleteLabel] with the floor green, like a tick that has
  /// landed.
  ///
  /// Every verb that writes is locked here, and the two the record has a
  /// standing answer for are still drawn: the tick wears what the record says
  /// about the open workout and the note glyph stays greyed, both disabled.
  /// Nothing a record's bar offers can change the record — which is also why
  /// the landing (no workout open) passes no callbacks at all.
  final bool readOnly;

  /// Settles the editor ahead of a read of the record, silently — the Compare
  /// flip and the Changes sheet both read SAVED state, and neither changes
  /// anything, so neither asks anything.
  final Future<bool> Function()? settleForCompare;

  /// Hands the loaded comparison to the surface that can show it — the workout
  /// editor flips its sets to the record while it is non-null, and back to the
  /// plan when it is null. Null hides Compare: a bar with nothing able to show
  /// a comparison has nothing to offer.
  ///
  /// Changes deliberately does NOT read this: its sheet shows itself, so it
  /// needs only a workout open — a landed record is something a bar with no
  /// flipping surface can still honestly tell.
  final ValueChanged<ReviewComparison?>? onComparison;

  /// Whether the record is on screen right now. It decides the label and the
  /// compare eye's fill — and the next tap leaves the record rather than
  /// reading it again, because the surface holding it already has it.
  final bool comparing;

  /// Finishes the whole pass. Offered on the landing, where the decision about
  /// the set belongs; null hides Finish.
  final Future<void> Function()? onFinish;

  /// Sets whether the open workout is Done — the tick, both ways. Done is a
  /// toggle, so the callback takes the state to write rather than being two
  /// verbs; built by the editor's own chrome, which is what knows how to
  /// settle it. Null hides the button.
  ///
  /// The bar keeps no answer of its own: the session's [ReviewSession.reviewed]
  /// is where the tick is read from, so a press that never moved it leaves the
  /// bar saying exactly what it said before.
  final Future<void> Function(bool done)? onSetDone;

  /// How Compare and Changes gather their two sides. Null reads the stores; a
  /// test injects a stub so the buttons can be exercised without a database
  /// underneath.
  final Future<ReviewComparison> Function()? loadComparison;

  /// The pass counted whole — workouts ticked plus goals reported, over both
  /// halves — when the bar is the landing's. Null (every other bar, and every
  /// bar in a test that does not care) counts workouts alone off the session,
  /// which is all a bar over one workout can know. When given, it is also the
  /// Finish gate: the pass is finished as a whole or not at all, and the
  /// count says how much of it is left (2026-10-10).
  final ({int done, int total})? overviewProgress;

  /// Where a tap on one of the changes sheet's exercise cards goes — the
  /// exercise group's `planned_exercise_id`, to the screen holding the workout
  /// (the editor's own wiring, handed down through `reviewChrome`; a snapshot
  /// wires its own). Null — no such screen underneath, so nowhere to go — and
  /// the cards stay inert.
  final ValueChanged<String>? onExerciseTap;

  @override
  State<ReviewBar> createState() => _ReviewBarState();
}

class _ReviewBarState extends State<ReviewBar> {
  bool _finishing = false;
  bool _comparing = false;
  bool _readingChanges = false;
  bool _settingDone = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final onSetDone = widget.onSetDone;
    final onFinish = widget.onFinish;
    // The pass's count, from the whole pass when the bar knows it. The landing
    // hands in workouts-plus-goals; every other bar counts the workouts its own
    // session holds, because that is all it is over.
    final overviewProgress = widget.overviewProgress;
    final passDone = overviewProgress?.done ?? session.reviewedCount;
    final passTotal = overviewProgress?.total ?? session.sessionIds.length;
    // Every workout verb needs a workout open; on top of that Compare needs
    // somewhere that can show the comparison it loads.
    final openWorkout = session.activeSessionId;
    final hasWorkout = openWorkout != null;
    // The tick has landed on the workout under the bar: the bar is done with
    // counting and rests on what it has to say. Green is the palette's word
    // for it — `success`, the colour every other finished thing in the app
    // wears. Read off the session rather than kept beside it, so the tick is
    // one fact: the button and the write can never disagree, and the same tap
    // is the way back off.
    final complete =
        openWorkout != null && session.reviewed.containsKey(openWorkout);
    // A record is settled by what it is, not by a tick under the bar: the
    // walk is over, and the bar says so without counting.
    final settled = complete || widget.readOnly;
    // A record's workout names the SIDE on screen rather than the walk that
    // produced it (2026-10-12): both of a record's documents are frozen, so
    // the eye flips between the two states a review leaves behind — the one
    // it produced ('After Review', where the screen opens) and the one it
    // found ('Before Review'). Two states of one thing, so the eye moves the
    // words the way it moves the sets. The landing has no side to name and
    // keeps the settled words, and so does every bar over a pass, where the
    // answer to Done outranks what the eye is showing.
    final readingSide = widget.readOnly && hasWorkout;
    final readingBefore = readingSide && widget.comparing;
    // What is on screen — the label is its reading and the compare eye's fill
    // its glyph (see below), and the tick's answer when it lands. The plan
    // itself is untouched underneath, so the words and the eye are the whole
    // of the signal.
    final label = readingBefore
        ? kReviewBeforeLabel
        : readingSide
        ? kReviewAfterLabel
        : settled
        ? kReviewCompleteLabel
        : widget.comparing
        ? 'Previously'
        : session.isOverview
        ? 'In Review · $passDone of $passTotal'
        : 'In Review';
    // The bar's own radius, not the button's default: a tighter corner sitting
    // inside the container's rounder one reads as a different object resting on
    // it, and these are the bar's own controls.
    const radius = FloatingBar.cornerRadius;
    // What the bar's answers light up in. Everywhere else in the app that is
    // the accent; here it is the green — the colour the tick answers in, worn
    // by the controls that carry something the pass HAS: a recorded note, the
    // tick, Finish. Compare is not one of them: a lens is not a claim.
    final highlight = AppColors.success;
    final actions = <Widget>[
      // The workout verbs are glyphs, not words: they are the pass's repeat
      // business — a flip, a diff, a note, a tick, once per workout, however
      // many workouts there are — and words on the bar every time read
      // heavier than the decision they carry. Finish, which is asked once and
      // about the whole set, keeps its word.
      if (hasWorkout && widget.onComparison != null)
        Semantics(
          button: true,
          selected: widget.comparing,
          label: 'Compare with the record',
          child: GlassButton(
            label: '',
            // An eye: the button is "show me the record", and the eye is the
            // one glyph that says that without a word — outlined at rest and
            // filled while the record is up, so the toggle wears its state
            // (2026-10-10; the fill is ink, not colour — see below).
            icon: widget.comparing
                ? Icons.visibility
                : Icons.visibility_outlined,
            compact: true,
            radius: radius,
            loading: _comparing,
            // The page's own ink — white on the dark theme, black on the
            // light — never the review's green. Colour on this bar is what the
            // pass HAS (the tick, a note, Finish); showing the record is a
            // lens, not a claim, and a lens wears no colour.
            //
            // And the page under it takes no styling of its own while the
            // record is up (2026-10-09, for now): the record and the plan read
            // through identical chrome — the label and the eye's fill are what
            // say which one is on screen.
            color: AppColors.primary,
            onPressed: _compare,
          ),
        ),
      if (hasWorkout)
        // The changes sheet: what this workout holds now against the record,
        // as a list — the same two sides Compare flips between, read side by
        // side instead. Offered wherever a workout is open, not gated on a
        // surface that can flip: the sheet carries itself, and "what changed"
        // is exactly the question a pass is here to answer. Wears Compare's
        // own ink for the same reason — a read of the record, not a claim.
        Semantics(
          button: true,
          label: 'Changes since the record',
          child: GlassButton(
            label: '',
            // Two shapes half over each other: difference, without a word.
            icon: Icons.difference_outlined,
            compact: true,
            radius: radius,
            loading: _readingChanges,
            color: AppColors.primary,
            onPressed: _showChanges,
          ),
        ),
      if (hasWorkout)
        // The workout's note. The glyph is the one a set's own note wears
        // ([SessionSetRow]'s swipe), and it brightens once the pass holds a
        // note for this workout — the button says what has been recorded, not
        // just what can be.
        //
        // Greyed while the record is up: the note it writes is the plan's,
        // and the plan is not what is on screen — the card below shows the
        // record's own note in its place (2026-10-10).
        ValueListenableBuilder<Map<String, String>>(
          valueListenable: reviewWorkoutNotesNotifier,
          builder: (context, notes, _) {
            final noted = notes.containsKey(session.activeSessionId);
            return Semantics(
              button: true,
              label: 'Workout note',
              child: GlassButton(
                label: '',
                icon: Icons.sticky_note_2_outlined,
                compact: true,
                radius: radius,
                // Locked on a record as well: the note this writes is the
                // plan's, and a record holds no plan to write to.
                disabled: widget.comparing || widget.readOnly,
                color: noted ? highlight : AppColors.muted,
                onPressed: () => editActiveWorkoutNote(context, session),
              ),
            );
          },
        ),
      // On a record the tick is drawn but locked (2026-10-12): the mark is a
      // fact the record carries, and the reader shows it the way the card
      // shows a ticked workout — wearing the answer, with the write taken out
      // of it. So it is the same button, disabled, and green whenever the
      // record says the workout was Done.
      if (hasWorkout && (onSetDone != null || widget.readOnly))
        Semantics(
          button: true,
          // The button says what the tap does, so it says the other thing once
          // the tick is up: the same glyph puts it on and takes it off. On a
          // record it does neither, and the label says so.
          label: widget.readOnly
              ? (complete ? 'Reviewed' : 'Not reviewed')
              : complete
              ? 'Unmark this workout'
              : 'Done with this workout',
          child: GlassButton(
            label: '',
            icon: Icons.check,
            compact: true,
            radius: radius,
            loading: _settingDone,
            // Also locked while the record is up: the tick is the pass's
            // verdict on the plan, and judging the record from inside it
            // would answer a question the pass did not ask (2026-10-10). And
            // on a record itself the answer is already written down: the
            // glyph reads it, and nothing here can change it.
            disabled: widget.comparing || widget.readOnly,
            // Green is the answer, so it arrives with the answer: unticked,
            // the tick is an ordinary control in the page's own ink, and the
            // review's colour lands with the mark — a button wearing the
            // colour of a state it is not in reads as the state.
            color: complete ? highlight : AppColors.primary,
            onPressed: () => _setDone(!complete),
          ),
        ),
      if (onFinish != null)
        GlassButton(
          label: 'Finish',
          compact: true,
          radius: radius,
          loading: _finishing,
          color: highlight,
          // Gated on the whole pass where the bar knows it (2026-10-10):
          // Finish is the verdict on everything the review covers, so it waits
          // until every workout is ticked and every goal has its status report
          // — the tabs' dots say which half is holding it up. A bar with no
          // tally of its own stays the plain button.
          disabled:
              overviewProgress != null &&
              overviewProgress.done < overviewProgress.total,
          onPressed: _handleFinish,
        ),
    ];
    return FloatingBar(
      // The floor itself turns green when the pass is walked — rim and words
      // together, so the whole surface says done rather than one part of it.
      // A record flipping to its earlier side is not that: the turn is to the
      // reader's own colour, accent, so rim and words move as one there too.
      rimColor: readingBefore
          ? AppColors.accent
          : settled
          ? AppColors.success
          : null,
      // One row, all parts on it: the label takes what is left after the
      // buttons, so a long pass is still readable at a glance.
      child: Padding(
        // Right only (2026-10-10): the label centres itself in the room the
        // bar leaves it, and that room starts at the rim — an inset on this
        // side would be a margin the eye cannot see, pushing the words right
        // of the space they are measured against. The glyphs keep their 12pt
        // off the rim.
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: _labelSwap,
                // Only the line arriving moves: it rises in from below and
                // fades up as it comes. Everything this label says is one line
                // of text, so a change to it has to read as a change and not
                // as the same label in different words — but two lines of it
                // on screen at once read worse than either.
                //
                // Both lines ride this one builder — the switcher hands the
                // outgoing copy of the widget its controller, reversed — so
                // "the old words are simply gone" has to be said here, by
                // drawing nothing: any exit at all, a slide or a fade or even
                // a line apart, is a second line on screen for as long as it
                // lasts. Dropped outright, what the eye follows is the new
                // line coming up into the place the old one held.
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    final arriving =
                        animation.status == AnimationStatus.forward ||
                        animation.status == AnimationStatus.completed;
                    if (!arriving) return const SizedBox.shrink();
                    final risen = Curves.easeOut.transform(animation.value);
                    return Opacity(
                      opacity: risen,
                      child: FractionalTranslation(
                        translation: Offset(0, 1 - risen),
                        child: child,
                      ),
                    );
                  },
                ),
                // Centred in the room the glyphs leave it (2026-10-10): the
                // slot is most of the bar and starts at the rim, and a line
                // pinned to its left edge reads as a bar with a gap, not a bar
                // with a label. And clipped to the line's own band, so the
                // rise reads as a roll inside the bar rather than a line
                // climbing out of it.
                layoutBuilder: (current, previous) => Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  children: [...previous, ?current],
                ),
                child: Text(
                  label,
                  // Keyed by the words: a swap in place is the one thing the
                  // switcher must NOT animate, and the same label rebuilt (a
                  // press, a note landing) is not a change it should see.
                  key: ValueKey(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    // The rim's reading in words: green once the pass is
                    // walked, accent for everything still being read.
                    color: settled && !readingBefore
                        ? AppColors.success
                        : AppColors.accent,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < actions.length; i++) ...[
              // Tighter than the usual AppSpacing.sm: four glyphs cost width,
              // and the label is what pays in an ellipsis — 'Review Complete'
              // is the longest line the four-glyph row holds, and the slot was
              // measured to hold a longer one whole (2026-10-10, on 402pt).
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Flips the open workout's tick through the callback the editor's chrome
  /// built — which settles the editor on the way in and writes the row both
  /// ways.
  ///
  /// The flip is answered on the bar and nowhere else: the label and the floor
  /// read the tick straight off the session, so the notifier's move IS the
  /// answer — [kReviewCompleteLabel] and green when it lands, the pass's own
  /// words when it comes back off. The workout's route is NOT left either way.
  /// The tick is what the bar has to say about this workout, and saying it by
  /// walking the user off the screen they just judged put the answer and the
  /// goodbye in the same moment; the bar keeps the verdict up instead, where it
  /// can still be read, and leaving stays the header's — the one place it is
  /// everywhere else in the editor.
  ///
  /// A press that did not land (a save that failed, a write that refused)
  /// changes nothing: the session never moved, so the bar says exactly what it
  /// said before and the tick is pressable again.
  Future<void> _setDone(bool done) async {
    final onSetDone = widget.onSetDone;
    if (onSetDone == null) return;
    setState(() => _settingDone = true);
    await onSetDone(done);
    if (mounted) setState(() => _settingDone = false);
  }

  /// Runs the landing's finish: the partial-review confirm, the notes sheet,
  /// the snapshot. Wrapped in a loading state because the button must not be
  /// pressable twice while the review is being recorded; cleared when the call
  /// returns without completing (a dismissed sheet, a failed write).
  Future<void> _handleFinish() async {
    final onFinish = widget.onFinish;
    if (onFinish == null) return;
    setState(() => _finishing = true);
    await onFinish();
    if (mounted) setState(() => _finishing = false);
  }

  /// Toggles the comparison: this workout at the last finished review that
  /// covered it — or as found when this pass began — in place of the plan.
  ///
  /// The editor settles first, silently: the comparison reads SAVED state, so
  /// an edit still sitting in a form field would read as a change that never
  /// happened. A save that fails aborts — better no comparison than one
  /// against state the user cannot see.
  ///
  /// Leaving reads nothing: the surface holding the record already has it, so
  /// the second tap is a flip back, not a second load.
  ///
  /// The diff sheet lives on, but at its own button: Compare shows the record
  /// in place — the workout's own sets wearing the record's values — while
  /// Changes ([_showChanges]) reads the very same two sides as a list. One
  /// load, two lenses.
  Future<void> _compare() async {
    // The changes sheet is loading its own record: a flip landing now would
    // send the editor the record behind the sheet. One read at a time.
    if (_readingChanges) return;
    if (widget.comparing) {
      widget.onComparison?.call(null);
      return;
    }
    final settle = widget.settleForCompare;
    if (settle == null) return;
    if (!await settle()) return;
    if (!mounted) return;

    setState(() => _comparing = true);
    try {
      final load =
          widget.loadComparison ??
          () => loadReviewComparison(widget.session, userId: _currentUserId());
      final comparison = await load();
      if (!mounted) return;
      setState(() => _comparing = false);

      final before = comparison.before;
      if (before == null || before.sessions.isEmpty) {
        // Nothing to flip to: no earlier version was recorded for this
        // workout. Saying so beats showing the plan back under a heading
        // that claims it is the record.
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text(kNoEarlierVersionNote)));
        return;
      }
      widget.onComparison?.call(comparison);
    } catch (e) {
      if (!mounted) return;
      setState(() => _comparing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not compare: $e')),
      );
    }
  }

  /// Opens the changes sheet: the open workout now against the record Compare
  /// reads, as a card per exercise.
  ///
  /// Back to the current first: the sheet's question is always new vs old, and
  /// a sheet opened while the editor shows the record would leave the screen
  /// claiming the record is up underneath a description of the plan.
  ///
  /// The editor settles first, silently, for Compare's own reason: the
  /// comparison reads SAVED state, and a pending edit would read as a change
  /// that never happened. A settle that fails aborts; a surface with no editor
  /// to settle (a loading or dead-end page) has nothing to land and proceeds.
  ///
  /// A missing earlier version is a state the sheet explains, not a failure —
  /// unlike Compare, which has nothing to show and says so in a SnackBar, the
  /// sheet opens either way, because "there is nothing recorded yet" is worth
  /// reading and the sheet is where it reads.
  ///
  /// No subtitle: the sheet answers inside ONE workout — both sides are
  /// narrowed to it — so there are no two sides for a header to name. The
  /// tap-through is the editor's own ([ReviewBar.onExerciseTap]): the sheet
  /// closes itself, then the workout under it switches to the exercise asked
  /// for.
  Future<void> _showChanges() async {
    // A Compare load in flight is about to hand the editor the record; the
    // sheet must not race it.
    if (_comparing) return;
    if (widget.comparing) widget.onComparison?.call(null);
    final settle = widget.settleForCompare;
    if (settle != null && !await settle()) return;
    if (!mounted) return;

    setState(() => _readingChanges = true);
    try {
      final load =
          widget.loadComparison ??
          () => loadReviewComparison(widget.session, userId: _currentUserId());
      final comparison = await load();
      if (!mounted) return;
      setState(() => _readingChanges = false);

      var before = comparison.before;
      // Compare's own rule: a record that holds none of this workout is no
      // record of it — the sheet then says so rather than diffing against a
      // document about something else.
      if (before != null && before.sessions.isEmpty) before = null;

      showContentDiffSheet(
        context,
        title: kReviewChangesTitle,
        before: before,
        after: comparison.after,
        exerciseNames: comparison.exerciseNames,
        variationNames: comparison.variationNames,
        beforeMissingNote: kNoEarlierVersionNote,
        emptyNote:
            'Nothing has changed — this workout still reads exactly as the '
            'record has it.',
        onExerciseTap: widget.onExerciseTap,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _readingChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read the changes: $e')),
      );
    }
  }
}

/// What Compare says — and what the changes sheet opens with — when the
/// workout has no recorded earlier version: no completed review has ever
/// covered it, and the pass that is running found it as it stands. Shared so
/// the wording is pinned in one place.
const String kNoEarlierVersionNote =
    'No earlier version recorded — there is nothing to compare this against '
    'yet.';

String _currentUserId() {
  final id = Supabase.instance.client.auth.currentUser?.id;
  if (id == null) {
    throw StateError('Cannot finish a review while signed out.');
  }
  return id;
}

