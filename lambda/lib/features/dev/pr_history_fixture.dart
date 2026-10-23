import '../../data/models/session_exercise_set.dart';
import '../session/model/pr_engine.dart';

/// The PR History demo's world — hard-coded sets only, no database, no
/// viewmodel, nothing that can reach the user's account (2026-10-21).
///
/// The feeds are derived with the production engine ([prEvents]) rather than
/// typed in as `PrEvent`s, so the demo cannot drift from the app about what a
/// PR is: every victim is the frontier value the killer actually beat, because
/// only a PR can move the frontier.
///
/// The fake session is dated [kDemoToday]; those rows form the exercise card's
/// grid and are the only sets the demo's PRS tile counts.
class DemoExercise {
  const DemoExercise({required this.id, required this.name});

  final String id;
  final String name;
}

const _bench = DemoExercise(id: 'demo-bench', name: 'Bench Press');
const _incline = DemoExercise(id: 'demo-incline', name: 'Incline Bench Press');
const _fly = DemoExercise(id: 'demo-fly', name: 'Cable Fly');

const kDemoExercises = [_bench, _incline, _fly];

const kDemoPausedVariationId = 'demo-var-paused';
const kDemoPausedVariationName = 'Paused';

/// The fake session's timestamp. Every set dated here is on the stage.
final DateTime kDemoToday = DateTime(2026, 10, 20, 18);

const _todaySessionId = 'demo-session-2026-10-20';

DateTime _day(int month, int day) => DateTime(2026, month, day, 10);

PastSetRow _set({
  required String id,
  required DemoExercise exercise,
  required DateTime date,
  required num weight,
  required num reps,
  int setNumber = 1,
  String? variationId,
  String? variationName,
  String sessionId = '',
}) => PastSetRow(
  sessionExerciseSetId: id,
  sessionExerciseId: '$id-exercise',
  sessionId: sessionId.isEmpty ? 'demo-session-$id' : sessionId,
  userId: 'demo-user',
  setNumber: setNumber,
  reps: [reps],
  sessionCreatedDate: date,
  exerciseId: exercise.id,
  variationId: variationId,
  weight: weight.toDouble(),
  exerciseName: exercise.name,
  variationName: variationName,
);

/// Every set the fake user ever logged, oldest first. Bench carries the story
/// the sheet is for: an early dual kill (70×8 beats both 65×8 and 70×5 — the
/// sheet names the same-weight 70×5 alone, the weight not being new), a
/// paused line that never touches the regular one, and today's pair of PRs.
final List<PastSetRow> kDemoPastSets = [
  // ── Bench Press ──
  _set(id: 'bench-1', exercise: _bench, date: _day(8, 4), weight: 60, reps: 10),
  _set(id: 'bench-2', exercise: _bench, date: _day(8, 11), weight: 65, reps: 8),
  _set(id: 'bench-3', exercise: _bench, date: _day(8, 14), weight: 70, reps: 5),
  // The dual kill: raised the best weight at 8 reps AND the best reps at 70.
  _set(id: 'bench-4', exercise: _bench, date: _day(8, 18), weight: 70, reps: 8),
  _set(id: 'bench-5', exercise: _bench, date: _day(9, 1), weight: 90, reps: 3),
  _set(
    id: 'bench-6',
    exercise: _bench,
    date: _day(9, 8),
    weight: 100,
    reps: 10,
  ),
  _set(
    id: 'bench-7',
    exercise: _bench,
    date: _day(9, 15),
    weight: 105,
    reps: 5,
  ),
  // Paused is its own frontier — the first paused set is a FIRST PR even
  // though the regular line is already at 90 × 3 by then.
  _set(
    id: 'bench-p1',
    exercise: _bench,
    date: _day(9, 2),
    weight: 60,
    reps: 5,
    variationId: kDemoPausedVariationId,
    variationName: kDemoPausedVariationName,
  ),
  _set(
    id: 'bench-p2',
    exercise: _bench,
    date: _day(9, 9),
    weight: 70,
    reps: 5,
    variationId: kDemoPausedVariationId,
    variationName: kDemoPausedVariationName,
  ),
  _set(
    id: 'bench-p3',
    exercise: _bench,
    date: _day(9, 16),
    weight: 80,
    reps: 3,
    variationId: kDemoPausedVariationId,
    variationName: kDemoPausedVariationName,
  ),
  // Today: the heavy triple first, the rep PR second, a back-off that is not
  // a PR (100 × 12 already covers 100 × 10).
  _set(
    id: 'bench-8',
    exercise: _bench,
    date: kDemoToday,
    weight: 110,
    reps: 3,
    setNumber: 1,
    sessionId: _todaySessionId,
  ),
  _set(
    id: 'bench-9',
    exercise: _bench,
    date: kDemoToday,
    weight: 100,
    reps: 12,
    setNumber: 2,
    sessionId: _todaySessionId,
  ),
  _set(
    id: 'bench-10',
    exercise: _bench,
    date: kDemoToday,
    weight: 100,
    reps: 10,
    setNumber: 3,
    sessionId: _todaySessionId,
  ),

  // ── Incline Bench Press ──
  _set(id: 'inc-1', exercise: _incline, date: _day(9, 3), weight: 24, reps: 12),
  _set(
    id: 'inc-2',
    exercise: _incline,
    date: _day(9, 10),
    weight: 28,
    reps: 10,
  ),
  _set(id: 'inc-3', exercise: _incline, date: _day(9, 17), weight: 32, reps: 6),
  // Today: a rep PR, then a weight PR that beats the old best at 8 reps.
  _set(
    id: 'inc-4',
    exercise: _incline,
    date: kDemoToday,
    weight: 28,
    reps: 14,
    setNumber: 1,
    sessionId: _todaySessionId,
  ),
  _set(
    id: 'inc-5',
    exercise: _incline,
    date: kDemoToday,
    weight: 30,
    reps: 8,
    setNumber: 2,
    sessionId: _todaySessionId,
  ),

  // ── Cable Fly ──
  _set(id: 'fly-1', exercise: _fly, date: _day(9, 4), weight: 15, reps: 15),
  _set(id: 'fly-2', exercise: _fly, date: _day(9, 11), weight: 20, reps: 10),
  _set(
    id: 'fly-3',
    exercise: _fly,
    date: kDemoToday,
    weight: 22.5,
    reps: 8,
    setNumber: 1,
    sessionId: _todaySessionId,
  ),
];

/// Every exercise's all-time PR events, oldest first — the engine's own order
/// (the sheet reverses it for the feed).
final Map<String, List<PrEvent>> kDemoPrsByExercise = {
  for (final exercise in kDemoExercises)
    exercise.id: prEvents([
      for (final set in kDemoPastSets)
        if (set.exerciseId == exercise.id) set,
    ]),
};

List<PrEvent> demoPrsFor(String exerciseId) =>
    kDemoPrsByExercise[exerciseId] ?? const [];

/// The exercise's PRs from the fake session on [kDemoToday] — what the card's
/// PRs pill quotes ("+2 PRs"), beside the all-time feed the pill opens.
int demoSessionPrsFor(String exerciseId) => [
  for (final event in demoPrsFor(exerciseId))
    if (event.achievedDate.isAtSameMomentAs(kDemoToday)) event,
].length;

/// The sets that are PRs in the fake session — the accent rows in the grid.
/// Derived, so the demo's 5 can never disagree with its feeds.
final Set<String> kDemoSessionPrSetIds = {
  for (final prs in kDemoPrsByExercise.values)
    for (final event in prs)
      if (event.achievedDate.isAtSameMomentAs(kDemoToday) &&
          event.sessionExerciseSetId != null)
        event.sessionExerciseSetId!,
};

final int kDemoSessionPrCount = kDemoSessionPrSetIds.length;

/// Today's sets for one exercise, in grid order.
List<PastSetRow> demoSessionRows(String exerciseId) => [
  for (final set in kDemoPastSets)
    if (set.exerciseId == exerciseId &&
        set.sessionCreatedDate.isAtSameMomentAs(kDemoToday))
      set,
]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
