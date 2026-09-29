/// A block's length, and the arithmetic that keeps its two spellings equal.
///
/// Lives in `core/utils/` beside `date_range.dart` for a structural reason, not
/// a stylistic one: `lib/data/` never imports `lib/features/`, and
/// `ProgramProgress` — a data-layer model — needs [endDateFor] to answer "has
/// this block run its course?". That is why these functions take the raw
/// numbers rather than a `ProgramBlock`, and why the enum sits here with them:
/// it is the shared vocabulary for the one concept both layers speak.
library;

/// How a block is bounded: by calendar weeks, or by a count of sessions.
///
/// Never both. A block that carried both would have two answers to "is this
/// phase over?", and every reader — the progress bar, the finish check, the
/// prompt that asks to end it — would have to pick one arbitrarily. The
/// database enforces the same rule (`dim_program_block_length_check`), so this
/// enum is the client's spelling of an invariant that is already true on disk.
enum BlockLengthMode {
  weeks,
  sessions;

  String get label => switch (this) {
        BlockLengthMode.weeks => 'Weeks',
        BlockLengthMode.sessions => 'Sessions',
      };
}

/// Which length a block carries.
///
/// Sessions wins when both are set. That ordering is only reachable on legacy
/// or corrupt data — the constraint makes it unwritable — and sessions is the
/// safer reading of the two: it is the mode that forbids an end date, so it is
/// the one that does not ask a possibly-stale `end_date` to be trusted.
///
/// Neither set reads as weeks, which is what a new block opens on: weeks is the
/// mode that fills in an end date, so it is the more legible starting point.
/// A block that declares neither is open-ended — no length, no prompt, ended by
/// hand.
BlockLengthMode blockLengthModeOf({int? targetWeeks, int? targetSessions}) =>
    targetSessions != null ? BlockLengthMode.sessions : BlockLengthMode.weeks;

/// `Ends` = `Starts` + [weeks] weeks + [days] days — the projection a block's
/// end date is.
///
/// The two numbers are the stored length; the end date is what they project to.
/// That is what makes a late start push the end out, and what keeps the length
/// fields and `Ends` from ever disagreeing: one value, shown two ways.
///
/// [days] is a **remainder** — the part of a length whole weeks cannot express —
/// so `8 weeks 3 days` projects 59 days out, not 56. It defaults to zero, which
/// is what leaves the whole-week callers (a run's own target, a legacy read)
/// saying exactly what they said before.
///
/// Two deliberate details:
///
/// * The date part is built through the `DateTime` constructor rather than
///   `add(Duration(days: 7 * weeks + days))`, so the result is always the
///   intended calendar day. Adding an absolute duration across a
///   daylight-saving boundary lands an hour off and can render the end date a
///   day early.
/// * The time of day is carried through, so an end derived from a run's
///   `started_date` (a real timestamp) still means "the same time, N weeks
///   later" rather than silently snapping to midnight.
DateTime endDateFor(DateTime start, int weeks, [int days = 0]) {
  final day = start.day + 7 * weeks + days;
  return start.isUtc
      ? DateTime.utc(
          start.year, start.month, day, start.hour, start.minute, start.second)
      : DateTime(
          start.year, start.month, day, start.hour, start.minute, start.second);
}

/// The exact inverse of [endDateFor]: the length between two dates, split into
/// whole weeks and a remainder of days.
///
/// Exact rather than rounded — 60 days reads back as `8 weeks 4 days`, never as
/// `9 weeks`. That exactness is the point of carrying a remainder at all: with
/// it, picking an `Ends` and reading the length back is a round trip, so the two
/// spellings of one value cannot disagree about the day the block finishes.
///
/// The day difference is taken over UTC-normalised dates, because `inDays` on
/// two local dates is off by one across a daylight-saving boundary (seven
/// calendar days can measure 167 hours) — and an exact inverse has no rounding
/// left to absorb that the way the old whole-week one did.
///
/// Null when there is no end at all, or when the end does not follow the start —
/// a length has to be positive, and returning a token `1 day` would invent a
/// plan.
({int weeks, int days})? lengthBetween({
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  if (startDate == null || endDate == null) return null;
  final days = _utcDay(endDate).difference(_utcDay(startDate)).inDays;
  if (days <= 0) return null;
  return (weeks: days ~/ 7, days: days % 7);
}

/// A block's length in words — "8 weeks 3 days", "24 sessions", "3 days" — or
/// null when it declares no length at all.
///
/// The quantity only: no "as set on the block", no trailing period. Each caller
/// wraps it in its own sentence, and one of them is a program card where the
/// phrase is the entire line. What no caller may do is spell the number itself:
/// five surfaces describe a length and each used to do exactly that, which is
/// survivable in two units and not in three — the failure mode is one screen
/// calling a block "8 weeks" that another correctly calls "8 weeks 3 days".
///
/// Follows [blockLengthModeOf]'s precedence, so it can never describe a shape
/// `dim_program_block_length_check` forbids.
String? blockLengthPhrase({
  required int? targetWeeks,
  required int? targetSessions,
  int? targetDays,
}) {
  final mode = blockLengthModeOf(
    targetWeeks: targetWeeks,
    targetSessions: targetSessions,
  );
  if (mode == BlockLengthMode.sessions) {
    // Non-null by definition — that is what the sessions mode *is*.
    return _plural(targetSessions!, 'session');
  }
  final weeks = targetWeeks;
  if (weeks == null) return null;
  final days = targetDays ?? 0;
  final parts = <String>[
    if (weeks > 0) _plural(weeks, 'week'),
    if (days > 0) _plural(days, 'day'),
  ];
  // `0 weeks 0 days` is unwritable — the CHECK requires a positive total — but a
  // malformed read should come out as "no length", not as an empty string.
  return parts.isEmpty ? null : parts.join(' ');
}

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Whether a run is measured by a count of sessions rather than by the calendar.
///
/// A block states its own unit, so a run with a block simply reads what the
/// block declared — and a block declaring neither target is bounded by nothing
/// at all, ended by hand. A blockless run has no declaration to read, so it
/// falls back to its progression mode, which is what has always decided this:
/// order walks a list and counts, frequency assigns days to a calendar.
///
/// One spelling, used by both the reader (`ProgramProgress.boundedBySessions`)
/// and the writer that fills in the numbers it reads (`getProgress`) — the two
/// disagreeing is exactly how a progress bar ends up measuring something other
/// than what the finish check uses.
bool isSessionsBounded({
  required bool hasBlock,
  required int? blockTargetSessions,
  required String? progressionMode,
}) =>
    hasBlock ? blockTargetSessions != null : progressionMode != 'frequency';

/// Whether two instants fall on the same calendar day, ignoring both the time
/// and which flavour they are. Used by the block editor's dirty check and by
/// its Starts/Ends anchoring.
bool sameCalendarDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
