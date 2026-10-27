---
name: app-features
description: >
  Reference for Lambda's core features: which database tables back each
  feature, what is a literal entity vs derived data, and the entity
  relationships. Use when planning feature work, answering "where does X
  live?", auditing schema changes, or when unsure whether something should
  be persisted.
---

# Lambda — Core Features and Where They Live

Naming rules first (from the 2026-08-13 redesign, extended by the 2026-08-24
v2 redesign and 2026-08-26 amendment):
`dim_*` = dimensions (reference data). Top-level dims — exercises,
variations, planned sessions, programs — soft-delete via `date_archived`
timestamptz (NULL = active, sortable latest-first); their child tables and
`dim_lesson` keep the boolean `is_archived` (internal lifecycle only).
`fact_*` = facts (events).
"Workout" language is banned in the DB — templates are **planned sessions**,
logged workouts are **sessions**.

v2 hierarchy (2026-08-24): sessions and templates are THREE levels deep —
`fact_session` → `fact_session_exercise` (the tab layer) →
`fact_session_exercise_set`; `dim_planned_session` →
`dim_planned_session_exercise` → `dim_planned_session_exercise_set`.
Program membership is an M2M join table (`dim_planned_session_program`) and
progression mode lives on the RUN. Full plan of record:
`docs/schema_redesign_v2.md`.

## Features and their tables

| Feature | Table(s) | Literal / Derived |
|---|---|---|
| **Exercise** | `dim_exercise` | Literal |
| **Variations** | `dim_variation` (flat library — no bridge) | Literal |
| **Sessions** (logging a workout) | `fact_session` + `fact_session_exercise` + `fact_session_exercise_set` | Literal |
| **Planning sessions** (session templates) | `dim_planned_session` + `dim_planned_session_exercise` + `dim_planned_session_exercise_set` (+ join rows) | Literal |
| **Programs** | `dim_program` | Literal |
| **Program blocks** (phases) | `dim_program_block` | Literal |
| **Program runs** | `fact_program_run` (carries `progression_mode` + `block_id`) | Literal |
| **Reviews** (a recorded pass over a set of workouts **and goals** — standalone since 2026-10-07) | `fact_program_review` | Literal |
| **Lessons** | `dim_lesson` | Literal |
| **Goals** (multi-set rungs 2026-10-26) | `fact_goal` + `fact_goal_target` | Literal |
| **Friends** (note tiers 2026-10-26) | `dim_friend_code` + `friend_relationship` (carries `nickname`, `share_notes`) | Literal |
| **Bodyweight** | `fact_bodyweight` | Literal |
| **PRs** | *(none)* | **Fully derived** — see below |
| **History / training logs** | *(none)* | **Derived read view** |
| **Analytics / insights** | *(none)* | **Derived, client-side** |

## Feature details

### Exercise — `dim_exercise`
Custom exercises owned per user (`user_id` FK). Columns: `custom_exercise_id`
(PK, client UUID text), `exercise_name`, `date_archived` (timestamptz, NULL =
active). Created inline from the session's add-exercise modal and the
exercise library. Archive (never hard-delete a used one) so historical sets
keep their names; never-used ones hard-delete instead.

### Variations — `dim_variation` (flat library since v2)
Variations (e.g. "Incline", "Paused") are user-created and **independent of
exercises** — the M2M bridge was dropped 2026-08-24. Any variation can be
applied to any exercise's sets; the variation edit modal is name-only (the
old one-way exercise-assignment UI is gone). "Used in N exercises" labels
("did you mean?") derive from logged history, not assignment.
PR scope is unchanged: curves key on (exerciseId, variationId) straight from
the set rows.

### Sessions — `fact_session` + `fact_session_exercise` + `fact_session_exercise_set`
A logged workout, three levels deep.
`fact_session`: `session_id` (PK), `pre_notes`/`post_notes`,
`created_datetime`, `end_datetime` (NULL = session in progress — replaced
`is_active` in v2), `program_run_id` (nullable — program context via the
run; the denormalized program attribution is gone), `planned_session_id`
(nullable FK → `dim_planned_session`, NO ACTION — dims are never
hard-deleted), `planned_session_name` (name snapshot that survives template
renames), `pre_feeling`/`post_feeling`.
`fact_session_exercise` (the tab layer): `session_exercise_id` (PK),
`session_id` (FK → fact_session), `custom_exercise_id` (nullable — a free
tab; FK → dim_exercise), `exercise_order` (real column — replaced the old
JSON blob), `planned_exercise_id` (plain ref → the template group — the
ghost-hint anchor, no FK).
`fact_session_exercise_set`: one logged set — `session_exercise_set_id`
(PK), `session_exercise_id` (FK → the tab row), `custom_variation_id` (FK →
dim_variation; variation stays per set), `set_number`, `weight` (NULL =
bodyweight), `reps` (int[]), `notes`, `planned_set_id` (plain ref to the
template row, no FK). Repos JOIN through the exercise row + the dims to
hydrate `exercise_id`/`exercise_name`/`variation_name` for consumers (PR
engine, rows) — names are always the dims' current names.
Sessions are hard-deleted on cancel (facts don't soft-delete).

### Planning sessions — three-level templates + program join rows
`dim_planned_session`: template (`session_id` PK, `name`, `notes`,
`created_date`, `date_archived` timestamptz NULL = active). Standalone when
no join row references it.
**Recency (agreed 2026-10-07)**: there is **no `updated_date`** on this table
— a workout's "last touched" is `MAX(fact_session.created_datetime)` for its
`planned_session_id`, i.e. when it was last LOGGED. The review picker orders
by `last_logged DESC NULLS LAST, created_date DESC, session_id DESC`; a
workout nobody has ever trained sorts by when it was made. Adding an
`updated_date` would be a schema change and a second definition of recency —
don't, without deciding to replace this one.
`dim_planned_session_exercise`: one group per exercise
(`planned_exercise_id` PK, `planned_session_id`, `custom_exercise_id`,
`exercise_order`, `exercise_name` snapshot, `is_archived`).
`dim_planned_session_exercise_set`: target rows (`planned_set_id` PK,
`planned_exercise_id`, `custom_variation_id`, `set_number`, `target_weight`
/`target_reps` — free TEXT hints ("60-70", "8-15", "AMRAP", "3 RIR"),
`target_notes`, `variation_name`, `is_archived`).
`dim_planned_session_program`: M2M join — `planned_session_program_id` PK,
`program_id` + `planned_session_id` (unique pair), `sequence_order` (order
split), `day_of_week` (1–7) + `week_offset` (0/1 fortnight, NULL = every
week; frequency split). Join rows hard-delete (nothing references them).
No duration dimension — Lambda tracks weight × reps only.
Soft-deleted via `is_archived`. Archiving a program hard-deletes its join
rows — templates become standalone. A logged `fact_session` is a **snapshot
copy** of a template — editing the template never touches past logged
sessions.

### Programs — `dim_program`
Pure blueprint: `program_id` (PK), `user_id`, `program_name`,
`program_description`, `date_archived` (timestamptz, NULL = active),
`program_created_date`, `program_updated_date` (v2 — bumped by every
update), `uses_blocks` (the program's **shape**, fixed at creation: made of
blocks or a list of workouts — stored, not inferred, because a blocked
program with no blocks yet is a real state), and `default_target_sessions`
(a simple program's remembered length). **No progression mode
and no length** — how the program is RUN is a property of the run.
Archive is the normal delete; `hardDeleteProgram` exists for programs with
no sessions and follows a load-bearing dependent-row order (reviews → goals
→ join rows → run unlinks → runs → blocks → program). Duplication
deep-copies the program + its blocks + planned sessions + groups + sets +
links.

### Program blocks — `dim_program_block`
An ordered, duration-bounded phase of a program: `block_id` (PK), `user_id`,
`program_id` (FK), `name`, `notes`, `block_order`,
`target_weeks`/`target_days`/`target_sessions` (length), `start_date`,
`end_date`, `date_archived` (timestamptz, NULL = active — blocks are named,
dated and user-visible with their own run/review trail to keep browsable,
hence the top-level dim treatment). A program either uses blocks or doesn't
(`dim_program.uses_blocks`), never mixed. Length runs out on its own day —
weeks × 7 + days, a remainder is not decoration. A run follows one block at
a time via `fact_program_run.block_id`. Day scheduling (the day picker and
Frequency progression) is retired from the UI (2026-10-03); the
`day_of_week`/`week_offset` columns stay on the join rows, dormant.

### Reviews — `fact_program_review`
A recorded pass over **workouts and goals**, made to decide what to change —
the successor to the versions timeline. `review_id` (PK), `user_id`,
`program_id` (**nullable since 2026-10-07 — NULL = standalone**, no program in
the picture), `program_run_id` (nullable — set when the review answers a
run), `kind` (`review` | `close`), `title`, `notes`, `scheduled_for`,
`completed_date` (NULL = **open**; there is no status column), `outcome`,
`snapshot_content`/`snapshot_hash`, `baseline_content`/`baseline_hash`,
`exercise_notes_json`, `workout_notes_json`, `achievements_json`,
`session_ids_json`, `goal_ids_json`, `reviewed_sessions_json`, `created_date`.

**Scope** — `session_ids_json`: the ordered JSON array of the planned-session
ids the pass covers (ticked in the picker; an empty set is refused
client-side — a review always has ≥1 workout, because goals cannot be walked).
`goal_ids_json`: the ordered goal ids, at any scope — a column rather than a
join table precisely because a goal's scope (program, block, run, or none)
has no bearing on whether it can be examined. `reviewed_sessions_json` is
`{"<planned_session_id>": "<ISO timestamp>"}`, one entry per Done — the tick
map that makes a pass resumable across app exits.
Legacy rows carry `block_id`/`session_id` instead (never both, server CHECK)
and are **not migrated**: `ProgramReview.sessionsIn(links)` resolves any row
into its set — a **standalone** row reads its own stored set and stops there;
otherwise stored set (minus ids the program no longer has), else its one
session, else its block's sessions, else the whole program (where close rows,
whose scope deliberately is everything, land too) — and `reviewScopeKey` is
the canonical key (sorted ids; legacy triple otherwise) the digest chains and
the panel both read. A standalone pass over {A,B} and a program pass over
{A,B} share the `set:` key on purpose: same question, same chain. New rows
write neither legacy column (both null was always legal), so an old build
reads one as a "program" review — the acceptable old behavior.

- **Starting one (2026-10-07)**: the **Reviews tab in the Library**
  (`lib/features/reviews/`) is the only start surface for now — `+` → name
  sheet → selection screen (workouts by recency, goals in library order, both
  offering everything the user has whatever program it hangs off) → Start
  review. The program panel's Review button and the run-finished review
  creation are retired from the UI with their plumbing kept.
- **Cancelling one (2026-10-11)**: an open pass swipes left on its IN PROGRESS
  card in the Reviews list (`SwipeActions`, danger) → confirm dialog
  (`confirmCancelReview`, "Keep reviewing" / "Cancel review") → `deleteReview`
  hard-deletes the row, guarded `completed_date IS NULL` so a pass completed
  on another device is not deleted out from under its record. The drawer only
  reveals; the dialog decides. Ticks, notes, baseline and snapshot are columns
  on that one row — nothing else goes with it — and cancelling a *scheduled*
  pass also removes its `kDueReview` item from `fetchDueItems` (that row is
  otherwise only dismissable by completing). A completed card has no drawer:
  a record is not something a list takes back.
- **Beginning**: `beginReview` = the INSERT plus the "as found" baseline,
  captured from the live rows at the moment the pass starts and idempotent
  by construction (the UPDATE only lands where the baseline is NULL, so a
  resume can never move a live baseline). `scheduleReview` alone is the
  calendar path: a review dated in the future must not freeze today's plan.
- **The pass** opens on a landing (`_ReviewLanding`) — **Workouts | Goals**
  tabs under the header: one card per covered workout on the first, tick +
  date once Done, one per picked goal on the second (tap → read-only view).
  A pass with no goals gets no strip at all rather than an empty second tab —
  the strip is the claim that there is something under it. A workout card
  pushes the real editor (edit mode) with
  `ReviewBar` below it in the same `FloatingBar` container: **Note** /
  **Compare** / **Done** inside a workout, **In Review · N of M** / **Finish**
  on the landing (Finish is a review-level decision, so it lives where the
  review does). **Done** is a toggle: the tick on the way in settles the edits
  first, then `markWorkoutReviewed` read-modify-writes the tick map (guarded on
  `completed_date IS NULL`); tapping it again calls `unmarkWorkoutReviewed`, the
  same write with one key leaving. The workout stays open either way — the bar
  reads the tick back off `ReviewSession.reviewed`, so the notifier's move is
  the answer ("Review Complete" + green, or the pass's own words back).
  Scheduling is retired from the UI for now (repo/VM plumbing stays).
  Notes ride in `exercise_notes_json` (`{"<planned_exercise_id>": "<note>"}`)
  and `workout_notes_json` (`{"<planned_session_id>": "<note>"}`), written
  through as they are typed — they are the review's record, not the
  exercise's or the workout's.
- **Compare** (per workout) = the newest COMPLETED predecessor whose resolved
  set **contains** that workout — both sides narrowed to it via
  `contentInScope(sessionId:)` — else this review's own baseline. "Contains",
  not "equals": a pass over a set including this workout is a look at it, and
  a newer pass that skips it is skipped over, not compared against. The pool
  follows the review's scope: a standalone review walks **every** review the
  user has (`fetchReviewsForUser`), a program review its own. Legacy rows
  qualify by their old scope, exactly as their digests always read. **While
  the eye is up** the plan's own tabs mark the names the record does not hold
  with a green **plus** (`ExerciseMark`, over `workoutExerciseSlots`) — a
  dropped exercise is never listed, so a live pass shows **no minus**, and the
  marks go with the flip: a pass at rest is bare (2026-10-12). The glyph is a
  plus or minus **inside a filled disc** (`Icons.add_circle`/`remove_circle`):
  a bare stroke at 14px read as a hyphen against the name it was about.
- **Finishing** (`completeReview`) writes a `ProgramContent` into
  `snapshot_content`/`snapshot_hash` and stamps `completed_date` + `outcome`
  in one transaction. The snapshot is the **whole program** for a program
  review and the **stored set + picked goals** for a standalone one
  (`buildContentForSessions`); every read-back narrows it (`contentInScope`,
  which keeps an explicitly picked goal even when its block holds no reviewed
  workout). Finish asks once when work is left unticked ("N of M reviewed —
  finish anyway?"). `kOutcomeDismissed` completes without a snapshot ("not
  now"; excluded from the achievements window).
- **Reading a completed one (2026-10-11)**: tapping a COMPLETED card in the
  Reviews list calls `openCompletedReview` → `ReviewRoute(readOnly: true)`
  pushed under `kReviewRouteNameRecord` (deliberately NOT `kReviewRouteName`,
  which is what `unwindReview` pops down to — a record must never be what a
  live pass unwinds into). The same landing, read only: workout cards with no
  swipe and no "+ add" tiles, the ticks as recorded, the bar reading "Review
  Complete" over a green rim, and a third **Summary** tab ("Nothing here yet."
  — a placeholder, records only; an open pass keeps its two tabs and no
  Summary). Nothing is published to `reviewSessionNotifier` — a record is not
  a pass being taken — and nothing writes; the opener refuses with a snackbar
  while a pass is live. The record route takes a lazy `WorkoutEditorViewModel`
  (built on first open) so a record never constructs one. The program history
  panel keeps `showReviewDetailSheet` (the WHAT CHANGED diff the landing
  never shows).
- **A record reads (2026-10-12; a stack since 2026-10-26)**: both lists on a
  record are doors, into readings. A workout card opens `RecordWorkoutScreen`
  — the **pass's own chrome** (header, shared card, the review's bar at the
  floor) over every frozen version of that workout: the current plan when it
  still exists, then each completed review's end (`snapshot_content`, what
  the pass left) and start (`baseline_content`, what it found), newest first,
  read once by `fetchWorkoutVersions` (which walks the user's completed
  reviews and narrows each document to this workout — never the live plan,
  which keeps being edited). The record wears the pass editor's
  whole floor (2026-10-27): a **walker** in the session date bar's ghost-box
  furniture (`Container` + `SessionChevronButton`s + a mono caption) above
  the planner's spent actions row and live `SessionStatsTiles(gain: false)`
  doors, all under the review's own bar — so a completed review is read on
  the page an open one is edited on. The walker steps the stack older
  left, newer right, both ends spent and never absent, and names the version
  on screen `START OF REVIEW - 1 Oct 2026` / `END OF REVIEW - 9 Oct 2026` /
  a lone `CURRENT PLAN`; a step is a repaint, never a read, so there is no
  spinner to wait through. `RecordWorkoutViewModel`
  (`ValueNotifier<RecordWorkoutState>`) owns which version is on screen, the
  sibling pair the eye flips across, the reference the marks read, and the
  floor's shelves — timeline PRs, open goals and exercise notes, read once
  after the page opens through `loadContext` (a failed read leaves its door
  quiet).
  The **eye** is the jump between the two sides of the review on screen —
  offered only where both sides hold the workout (a jump onto "the workout
  was not there" would read as data gone missing), and never on the current
  plan, which belongs to no review. The bar's own label names the side of a
  review version (`kReviewAfterLabel` / `kReviewBeforeLabel`, green rim and
  words at rest turning accent as the eye turns, through the label's usual
  rise) and reads `Current Plan` over the plan (`ReviewBar.recordLabel`).
  **The names carry the versions' disagreement, and both marks live on the
  end** (2026-10-27): an exercise the end holds and its start does not wears
  a green **plus** (the pass added it), and a group the start held and the
  end does not — which the finish's snapshot drops, so the end has no row of
  its own to mark — is drawn as a card from the start's frozen copy that
  wears only the red `ExerciseMark.removed`: the ordinary selector name and
  its plain frozen sets, its pass note where one was left, at its old plan
  position after any kept group sharing the slot. On a record the removal
  is the mark, never a repaint — the open pass's red card stays the open
  pass's (2026-10-27). The start is the
  baseline the pass found and wears no marks at all, and on the current plan
  the reference is the newest end, so its plus says what has changed since
  the last record.
  `ExerciseMark` rides on the shared selector (each glyph a plus or minus
  inside a filled disc), in the field and in every popover row, one
  membership test over `plannedExerciseId` plus the removal set so the marks
  can never disagree across the eye. Names both sides hold stay bare, and a
  version with no reference — a review that kept one document, a plan no
  review has recorded — marks nothing and draws no removed group.
  The bar is handed the row's `ReviewSession` (`reviewChrome(session:,
  readOnly: true, loadComparison:)`), never publishing one, so Compare and
  Changes read those same documents through the injected comparison — a
  review's own delta (start→end) on either of its versions, the newest end →
  plan on the current one; the
  tick is **drawn wearing the record's answer and disabled** — green
  (`success`) under `GlassButton`'s half opacity when the record ticks it —
  and the note glyph stays greyed. Every other callback is null or inert, with
  exercises switchable because looking is not writing. The review's own notes
  ride only the versions the review produced: the exercise's box under its
  sets (`reviewNoteEmptyText` keeps it drawn, reading "No note" where that
  version left none — the pass draws that box under every exercise, so the
  record's furniture does not depend on what was typed) and the workout's
  above the card when that version has one; a start version's box answers
  empty, because the plan as found had no notes of its own. The row is read
  on the route (`_openRecordWorkout` → `fetchReview` for the bar's ticks and
  `fetchWorkoutVersions` for the stack) and the screen takes plain data, so it
  loads nothing and holds no loading state; a review that kept no record of
  the workout (a dismissed completion, a pre-snapshot row) arrives as no
  version and the page says so rather than drawing an empty grid.
  Exercise and variation names resolve live (`fetchExerciseNameMap`/
  `fetchVariationNameMap`) — a rename shows through on a record as it does
  everywhere. A goal row opens
  the same `showGoalSheet` with `onDescriptionChanged: null` — the sheet's
  **record** state: no pencil, no tap-to-edit, no "Add a note…", and no NOTES
  section at all when the record left none. The axes still read the live
  history: a completed review did not freeze the sets a goal measures.
- **Due items**: `fetchDueItems` never returns a standalone row
  (`program_id IS NOT NULL` — `DueItem.programId` is non-nullable, and a pass
  the user started from the library is asking nothing).
- **Run close** (`closeRun`) writes the `kind = 'close'` record with
  `achievements_json` frozen at the run's end.
- **Length reached** (`kDueRunFinished`): `fetchDueItems` raises it while a run
  is at its length AND no completed review carries the run's id
  (`hasCompletedReviewForRun`); the prompt resumes the run's NEWEST open pass
  (`fetchOpenReviewForRun` — panel-started reviews carry the run id too, so
  there is no scope column left to narrow by). Since 2026-10-07 the banner
  answers with **Continue / Change length / End run** directly — so Continue
  no longer clears the prompt (nothing writes the review that satisfied it).
  Nothing ends a run by itself.
- `proposed_content`/`proposed_hash` are **dormant** — the proposal path was
  deleted 2026-10-06; nothing writes or reads them.
- Reviews are hard-deleted only with `hardDeleteProgram` (they pin runs via
  a NO ACTION `program_run_id`, so they go before runs do) — and by
  `deleteReview` for a cancelled open pass (the `completed_date IS NULL`
  guard keeps it to passes, never records).

### Program runs — `fact_program_run`
The commitment: "I'm doing this program for X." Columns: `program_id` (NO
ACTION FK), `started_date`, `ended_date` (NULL = running), `is_current`
(partial unique index — at most one current run per user),
`progression_mode` ('frequency' | 'order' — chosen at run start, v2;
backfilled from the old program column), `target_sessions` (order),
`target_weeks` / `end_date` (frequency), `block_id` (nullable — the block
being followed; NULL = a blockless run, which is every row from before the
column existed). **Frequency** was defined to schedule by the join rows'
`day_of_week`/`week_offset` (fortnight week computed from `started_date`) —
that scheduling UI is retired (2026-10-03) and the mode is currently
unreachable from the app, but the column and the machinery stay;
**order** runs walk the join rows by `sequence_order` with a
completed-session cursor, and **wrap** (the cursor is
`completed % sessionCount`), so "keep going" past the length needs no new
length. Starting a run ends the previous current one.
**"End program" ends the RUN, not the program.** Runs are history — never
deleted when the program is archived.

### Lessons — `dim_lesson`
Per-exercise knowledge/cues (`lesson_text`, `pinned`, `is_archived`).
Lessons are **exercise-specific** (`custom_exercise_id`) and surface
**during a session** — the session screen, planner, and past-session viewer
all show them per exercise. `session_id` (nullable FK → `fact_session`, ON
DELETE SET NULL) records **which logged session the lesson was created in**;
`lesson_created_date` covers the when. Planner-created lessons have NULL
session_id (no logged session existed — a template was being edited).
Reference data, not events — hence a dim despite the legacy `fact_lesson`
name.

### Goals — `fact_goal` (+ `fact_goal_target`, 2026-10-26)
Goals are **PRs to be beat**: a target weight × reps for an exercise
("bench 100kg × 1" = beat the current 1RM). Achievement is **derived on read**
from the logged sets (`evaluateGoals` over `PastSetsTimelineCache`), never
stored as the truth: a scored set meets a rung when its weight ≥ the rung's
weight and its reps ≥ the rung's reps. `program_run_id` is
an optional link to a run (created at run start via prompt). `block_id`
scopes a goal to one phase (CHECK: a block implies a program). Facts —
hard-deleted.

**A goal has one of two shapes, and each shape has one storage.** A
**single-set** goal keeps its pair in `fact_goal.target_weight` /
`target_reps` and writes **no** child rows. A **multi-set** goal lists several
rungs — "100 kg × 5, then 110 kg × 3" — leaves both parent columns NULL, and
writes one `fact_goal_target` row per rung (`target_set_order` 1-based and
dense). Nothing is mirrored onto the parent: two copies would be two answers.
`achieved_date` is a legacy dormant column — the client schema deliberately
does not carry it; a goal's outcome is derived on every read and frozen per
run into `fact_program_review.achievements_json` at close.
`Goal.requirements` is the one reading that covers both (child rows when
present, else the parent pair), and every reader — evaluation, badges,
labels, snapshots — goes through it.

**Evaluation is a match, not a per-rung search.** Each rung means "this set
or better" (weight ≥ w and reps ≥ r), and a multi-set goal is met only when
**distinct** sets satisfy **all** rungs — one strong set cannot tick two
rungs, and a rung is never stranded behind an easy one (the engine is a
Kuhn augmenting-path match over the timeline; greedy in rung order fails when
a 140 set arrives before the 100 it is also better than). The completion
moment is the arrival of the set that finishes the match; every matched set
wears the `G` badge, and the achievement's evidence is the latest witness.
A single-set goal keeps its old rule: the earliest set that reaches the pair.
An exercise goal with no numbers at all ("bench, any set") still means any
performed set. Snapshots (`GoalAchievement`, `ContentGoal`) write the
`targets` list only when it is non-empty, so a single-set document's bytes
and hash never move.

### Friends — `dim_friend_code` + `friend_relationship` (2026-10-23)

There is **no pending state and no request**: entering a friend's code makes
the friendship immediately and mutually. Two tables carry it:

- `dim_friend_code` — one shareable code per user (8 characters,
  `ABCD-EFGH` grouping in the UI). A **side table, not a `dim_user` column**,
  because the user_data stream selects `dim_user *`; a new column would reach
  old app builds that don't know it. It streams to its owner, plus (since
  2026-10-25) to each mutual friend — the Friends list's last-resort name.
- `friend_relationship` — **one row per direction**. `add_friend_by_code`
  writes both rows in one call; every read requires the pair (the
  `friends_data` stream's `my_friends` CTE and `are_friends()` in RLS both
  test both directions), so a half-pair grants nothing. Each row also carries
  the caller's private `nickname` for that friend (2026-10-25) — only the
  owner's own rows ever stream, so a label never reaches the friend. Either
  side can end the friendship with `remove_friend`, which deletes both rows.

The Friends tab (`lib/features/friends/`) shows the user's code, adds by code,
lists friends, and opens a friend's history in the existing **read-only**
viewer: `LogsScreen(userId:, readOnly:)` → `SessionDetailScreen(userId:,
readOnly:, navRoute: '/friends')`, with `showLessonsModal(readOnly:)`.
Completed sessions only; the active session is never synced or shown. PRs and
goal badges derive per friend from `PastSetsTimelineCache.get(friendId)` — the
global `PrService` cache is never used on this path. Codes are stable in v1
(no regeneration). Stream shape, upload maps and the own-row-only mirror rule:
`sync-contract`.

**Note tiers (2026-10-26, #23).** A friendship shares training by default —
completed sessions, their sets and each set's notes. **Notes about the work**
— the exercise notes in `dim_lesson` and a session's `pre_notes`/`post_notes`
— are a second tier the owner opens **per friend**, on the caller's own
directed row (`friend_relationship.share_notes`, default false). The sheet is
reached from the friend row's third swipe (eye); the first tier is drawn as
always-on, not as a choice. The friend never sees the flag. Because the gate
is client-visible only in what ARRIVES, it lives in the `friends_data` stream
(`dim_lesson` only for sharers; `fact_session` split into two disjoint
queries, notes nulled at the source), with `friend_shares_notes()` as the REST
half for `dim_lesson` — RLS is row-level and cannot mask a column, so a
session's note columns stay unreadable only through the stream. Tier 3
(a friend planning on your behalf) lands with coaching authoring (#24).

### Bodyweight — `fact_bodyweight`
Weight measurements: `user_weight`, `user_weight_date` (measurement date),
`created_date` (log date). Profile screen logs these.

### PRs — **fully derived, no table**

**A set `(w, r)` is a PR iff it extends its (exercise × variation) pair's
best-ever frontier** — no prior set did ≥ r reps at ≥ w weight
(`¬∃ prior (w' ≥ w ∧ r' ≥ r)`; one dominance check covers both axes). So
100 × 5 after 110 × 1 IS a PR (110 covers one rep, not five); 100 × 4 after
100 × 5 is not; an identical repeat is not; the first-ever set on a pair is a
"First PR". Bodyweight is weight 0; a null variation is its own key.

**One set = one `PrEvent`**, even when it beats prior records on both
dimensions at once. Each event carries `beforeWeight` (previous best weight
at ≥ this rep count) and `beforeReps` (previous best reps at exactly this
weight) — the two frontier values it beat, both null meaning "First PR"; the
end screen renders both ("was 6 × 10 · 100 × 3").

**Counts, badges, accents, and modals all count events** — the live stats
bar, logs summary, pills and PR modal read the same number and can never
disagree (the pre-2026-08-29 per-axis engine counted one set as up to three
PRs in some surfaces and one in others). A set can also be a goal's achieving
set: it is drawn once as the goal (`G`) but still counts as a PR.

**Lenses are insights-only** — `repMaxCurve`, `weightMaxCurve`,
`repAxisHistory` and `weightAxisHistory` are pure projections over raw set
history for the insight charts (`kTrackedRepCounts` is a display config), and
they never gate detection.

**The pre-2026-08-29 model is gone**: per-axis record types
(`PrType.repMax` / `weightMax`), propagation records (`isPropagated`) and the
`achievedRecords` / `countableRecords` filters were deleted. `fact_pr` was
dropped 2026-08-14 — there is no PR table.

**Engine**: `lib/features/session/model/pr_engine.dart` (`prEvents` + the
lenses), reached via `pr_service.dart` (memoized; `invalidate()` after any set
write) and the live/logs `_recomputePRs`, fed by the oldest-first copy in
`PastSetsTimelineCache`. Editing past data self-heals on the next read —
nothing stale to clean up. Full spec: `docs/pr_methodology.md`.

### History / training logs — **derived read view**
The Sessions browse (the Session tab's Home, and the logs list the
`/logs/:sessionId` records open from — one `LogsScreen`, no Sets tab since
2026-10-23) and the past-session viewer read `fact_session` +
`fact_session_exercise` + `fact_session_exercise_set` joined with current
exercise/variation names. No table of its own. `PastSetRow` (a
`SessionExerciseSet` + session date) powers the per-exercise history
timeline.

### Analytics / insights — **derived, client-side**
The PR insights surfaces (PR modal, PR History, the insight curves and
axis-history sheets) aggregate the local PowerSync mirror — all reads are
local SQLite. The standalone Statistics feature is retired (no
`lib/features/statistics/`). No server-side analytics, no aggregates tables;
at this scale a dedicated OLAP store is not justified, and if reads ever get
slow a client-computed daily-summary table is the fix.

## Features you didn't list (worth remembering)

| Feature | Where | Notes |
|---|---|---|
| **User profile** | `dim_user` | name, DOB, gender, height, weight, `onboarded` flag. `user_`-prefixed columns (legacy naming) |
| **Rest timer** | in-memory only | `fact_rest` was dropped 2026-08-14 — no rest analytics. Timer still drives the AVG REST stat from `restDurationsThisSession` |
| **Supersets** | retired | Column `superset_group_number` DROPPED 2026-08-24 (schema v2). No UI creates supersets; dormant slot support renders a restored multi-exercise slot as its first exercise |
| **Feelings** | `fact_session.pre_feeling` / `post_feeling` | Pre-workout feeling is shown in logs; `post_feeling` is written but **never displayed yet** — logs screen is the candidate place |
| **Coaching** | `coaching_relationship` + coach RLS policies **+ `coaching_data` stream**, plus `fact_coach_assignment` / `fact_coach_feedback` (2026-10-26, #24) | Invite / accept / revoke (2026-10-26, #22): Profile → Coach invites by friend code, the athlete accepts or declines from the same screen, and either side can end the edge. Consent gate = `accepted_date`; an unaccepted invitation sends no athlete rows (the coach's name does reach the athlete). An accepted athlete's history opens in the existing read-only viewer. **Authoring (#24):** a coach hands an athlete a workout (the assignment carries a frozen `ProgramContent` snapshot + an id→name map; accepting copies it into the athlete's own library, remapping exercise/variation names), and writes feedback on any completed session of theirs — the athlete reads the same card on their own record |
| **Friends** | `dim_friend_code` + `friend_relationship.nickname` | Instant, mutual, by code (2026-10-23). No pending state; completed sessions only in the stream; the existing viewer reads a friend's history read-only. A friend reads **nickname → their name → their code → `Friend`** (2026-10-25); the nickname is the caller's own label on their directed row |
| **Onboarding** | `dim_user.onboarded` | Gate flag for first-run flow |

## Entity relationship quick map

```
dim_user ──< dim_exercise
  │         dim_variation (flat library — no link to exercises)
  │
  ├──< dim_lesson (per-exercise knowledge, session_id attribution)
  ├──< dim_program >──< dim_planned_session_program >── dim_planned_session
  │         │              (join rows carry sequence_order /
  │         │               day_of_week / week_offset)
  │         │                        │
  │         │                        └──< dim_planned_session_exercise
  │         │                                └──< dim_planned_session_exercise_set
  │         ├──< dim_program_block (ordered, duration-bounded phases)
  │         └──< fact_program_review (scope: a set of workouts + goals,
  │                                   legacy block/session; snapshot +
  │                                   baseline + tick map + notes)
  ├──< fact_program_review (STANDALONE since 2026-10-07 — program_id NULL:
  │                        a pass over workouts and goals, started from the
  │                        Library's Reviews tab)
  ├──< fact_program_run ──< dim_program (one current run per user,
  │         │                              progression_mode on the run,
  │         │                              block_id = the phase followed)
  │         ├──< fact_program_review (the review that answered its length)
  │         └──< fact_goal (optional link)
  ├──< dim_friend_code (one shareable code per user; also synced to mutual
  │                      friends as the name fallback, 2026-10-25)
  ├──< friend_relationship >── dim_user (one row per direction, each with the
  │                                           caller's own nickname; the pair is
  │                                           the friendship, 2026-10-23)
  ├──< fact_session ──< fact_session_exercise ──< fact_session_exercise_set
  │         ├── planned_session_id → dim_planned_session (template link)
  │         ├── program_run_id (program context via the run)
  │         └── planned_session_name (snapshot)
  └──< fact_bodyweight
```

## Complete table inventory

Every table that exists, with all columns. PowerSync adds a local `id`
column to every synced table (the sync streams alias the real PK as `id`).
The local-only `upload_failures` table exists on device but NOT on the
server.

### dim_user — profile (owner ALL, coach SELECT)
`user_id` (PK, uuid, default auth.uid()), `user_name`, `user_lastname`,
`user_date_created`, `user_date_of_birth`, `user_gender`, `user_height_cm`,
`user_weight_kg`, `onboarded` (bool). Rows created by the
`handle_new_user` auth trigger, never by the app directly. Never soft- or
hard-deleted (account deletion cascades from auth.users).

### dim_exercise — custom exercises (owner ALL, coach SELECT)
`custom_exercise_id` (PK, client UUID text), `user_id`, `exercise_name`,
`date_archived` (timestamptz, NULL = active).

### dim_variation — variations (owner ALL, coach SELECT)
`custom_variation_id` (PK), `user_id`, `variation_name`, `date_archived`
(timestamptz, NULL = active).
Flat library — no exercise assignment since v2.

### dim_lesson — per-exercise cues (owner ALL, coach SELECT)
`lesson_id` (PK), `user_id`, `custom_exercise_id`, `lesson_text`, `pinned`,
`is_archived`, `lesson_created_date`, `session_id` (nullable FK →
fact_session, ON DELETE SET NULL — which logged session it was created in).

### dim_program — program blueprints (owner ALL, coach SELECT)
`program_id` (PK), `user_id`, `program_name`, `program_description`,
`date_archived` (timestamptz, NULL = active), `program_created_date`,
`program_updated_date` (v2), `uses_blocks` (bool — the program's shape,
fixed at creation), `default_target_sessions` (a simple program's
remembered length; NULL = none set).
No progression mode, no length — those are run properties.

### dim_planned_session — session templates (owner ALL, coach SELECT)
`session_id` (PK), `user_id`, `name`, `notes`, `date_archived` (timestamptz,
NULL = active), `created_date`.
Standalone when no `dim_planned_session_program` row references it.

### dim_planned_session_program — M2M program links (owner ALL, coach SELECT)
`planned_session_program_id` (PK, client UUID), `user_id`, `program_id` (FK),
`planned_session_id` (FK), `sequence_order` (nullable), `day_of_week`
(1–7, nullable), `week_offset` (0/1, nullable — fortnight). UNIQUE
(program_id, planned_session_id). Hard-deleted (nothing references links).

### dim_planned_session_exercise — template exercise groups (owner ALL, coach SELECT)
`planned_exercise_id` (PK), `user_id`, `planned_session_id` (FK),
`custom_exercise_id` (nullable, FK → dim_exercise), `exercise_order`,
`is_archived`.

### dim_planned_session_exercise_set — template target rows (owner ALL, coach SELECT)
`planned_set_id` (PK), `user_id`, `planned_exercise_id` (FK),
`custom_variation_id` (nullable, FK → dim_variation), `set_number`,
`target_weight` (TEXT — free-form hint), `target_reps` (TEXT — free-form
hint), `target_notes`, `is_archived`.

### fact_session — logged sessions (owner ALL, coach SELECT)
`session_id` (PK), `user_id`, `pre_notes`, `post_notes`, `created_datetime`,
`end_datetime` (NULL = in progress — replaced `is_active` in v2),
`planned_session_id` (nullable FK → dim_planned_session, NO ACTION —
templates are never hard-deleted), `planned_session_name` (snapshot),
`program_run_id` (nullable), `pre_feeling` (1–5), `post_feeling` (1–5,
written but not yet displayed anywhere).

### fact_session_exercise — logged session tabs (owner ALL, coach SELECT)
`session_exercise_id` (PK), `user_id`, `session_id` (FK → fact_session),
`custom_exercise_id` (nullable — free tab; FK → dim_exercise since
2026-08-26), `exercise_order` (real column), `planned_exercise_id` (plain
ref → the template group, no FK — ghost-hint anchor).

### fact_session_exercise_set — logged set rows (owner ALL, coach SELECT)
`session_exercise_set_id` (PK), `user_id`, `session_exercise_id` (FK →
fact_session_exercise), `custom_variation_id` (nullable; FK → dim_variation
since 2026-08-26), `set_number`, `weight` (nullable — NULL = bodyweight,
treated as 0), `reps` (int[]), `notes`, `planned_set_id` (plain ref to the
template row, no FK).

**Names resolve live through the FKs** — no name snapshots anywhere since
2026-08-26. Renaming an exercise or variation updates ALL past data (the
rename flows warn about this). Repos hydrate `exercise_name`/
`variation_name` onto the models by joining the dims.

### fact_program_run — program runs (owner ALL, coach SELECT)
`program_run_id` (PK), `program_id` (FK → dim_program), `user_id`,
`started_date`, `ended_date` (NULL = running), `is_current` (partial
unique index — at most one current run per user), `progression_mode`
('frequency' | 'order', nullable for legacy rows — behaves as 'order'),
`target_sessions`, `target_weeks`, `end_date`, `block_id` (nullable — the
block being followed; NULL = a blockless run).

### dim_program_block — ordered phases (owner ALL, coach SELECT)
`block_id` (PK), `user_id`, `program_id` (FK), `name`, `notes`,
`block_order`, `target_weeks`, `target_days`, `target_sessions`,
`start_date`, `end_date`, `date_archived` (timestamptz, NULL = active),
`created_date`, `updated_date`. A run follows one block at a time
(`fact_program_run.block_id`); length runs out on its own day
(weeks × 7 + days).

### fact_program_review — reviews & their snapshots (owner ALL, coach SELECT)
`review_id` (PK), `user_id`, `program_id` (**nullable since 2026-10-07** —
NULL = standalone; a program review keeps the FK), `session_ids_json` (scope —
the ordered planned-session ids a pass covers) / `block_id` / `session_id`
(legacy scope — never both columns, and new rows write neither),
`reviewed_sessions_json` (the tick map — one ISO stamp per Done),
`goal_ids_json` (the goals the pass covers, at any scope — ordered),
`program_run_id` (nullable), `kind` ('review' | 'close'), `title`, `notes`,
`scheduled_for`, `completed_date` (NULL = open — there is no status column),
`outcome`, `snapshot_content` / `snapshot_hash` (written at completion; the
whole program for a program review, the stored set + picked goals for a
standalone one — reads narrow by the resolved set), `baseline_content` /
`baseline_hash` ("as found" at start; idempotent — only ever written where
NULL), `exercise_notes_json` (keyed by `planned_exercise_id`),
`workout_notes_json` (keyed by `planned_session_id` — the workout-level
sibling), `achievements_json` (run close), `created_date`.
`proposed_content` / `proposed_hash` are dormant (proposal path deleted
2026-10-06). Indexed on (user_id, created_date desc) since 2026-10-07 — the
user-wide list the standalone Reviews tab reads.

### fact_goal — goals (owner ALL, coach SELECT, friend SELECT)
`goal_id` (PK), `user_id`, `goal_text`, `custom_exercise_id` (nullable),
`target_weight`, `target_reps`, `program_run_id` (nullable FK →
fact_program_run), `achieved_date` (nullable, revocable),
`goal_created_date`. `target_weight` / `target_reps` hold a single-set goal's
pair; a multi-set goal leaves both NULL and stores its rungs in
`fact_goal_target` (2026-10-26).

### fact_goal_target — a multi-set goal's requirement rungs (owner ALL, coach SELECT, friend SELECT)
`goal_target_id` (PK), `goal_id` (FK → fact_goal, ON DELETE CASCADE),
`user_id` (FK → dim_user, ON DELETE CASCADE), `target_set_order` (1-based,
dense — the order the rungs are listed and matched in), `target_weight`
(numeric, nullable), `target_reps` (nullable). One row per rung, each
meaning "this set or better"; `fact_goal`'s pair stays NULL whenever rows
exist here. Indexed on `(goal_id, target_set_order)` — the only read — and on
`user_id` for the friends stream's per-friend buckets. The client mirrors the
goal's cascade by hand (no local constraints): `deleteGoal`,
`updateGoal`'s rewrite and `hardDeleteProgram` all delete the child rows.

### fact_bodyweight — weight measurements (owner ALL, coach SELECT)
`user_weight_id` (PK), `user_id`, `user_weight`, `user_weight_date`
(measurement date), `created_date` (log date).

### dim_friend_code — shareable codes (owner SELECT only)
`user_id` (PK, FK → dim_user, ON DELETE CASCADE), `friend_code` (TEXT, unique,
`^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$` — no I/O/0/1), `created_date`. One
row per user, written by the SECURITY DEFINER `after insert on dim_user`
trigger and backfilled by the migration. The app never writes it: no grant,
no UI (codes are stable in v1). RLS stays owner-only; the friends_data stream
additionally sends each mutual friend's code (2026-10-25), which the Friends
list falls back to when a friend has no name and no nickname.

### friend_relationship — friendships (own row ALL, either side SELECT)
`user_id` + `friend_user_id` (composite PK, both FK → dim_user, ON DELETE
CASCADE), `created_date`, `nickname` (TEXT, nullable — the caller's private
label for that friend, 120-char rail, 20-character client cap, 2026-10-25),
`share_notes` (boolean, NOT NULL DEFAULT false — the caller's per-friend
choice to send notes, 2026-10-26);
CHECK `user_id <> friend_user_id`. **One row per
direction** — `add_friend_by_code` writes both in one call, `remove_friend`
deletes both, and every read requires the pair (stream CTE and `are_friends()`
RLS). No server-side `id` column: the stream synthesizes
`user_id || '-' || friend_user_id`. The client mirrors only its **own**
directed row (`_compositeKeyTables` in `database.dart`); a nickname or a
privacy tier is a local-first UPDATE on that row. `friend_shares_notes(owner,
viewer)` (SECURITY DEFINER, the `are_friends()` shape plus the flag) is the
REST gate on `dim_lesson`'s friend policy; the notes columns on
`fact_session` cannot be policy-gated (RLS is row-level) and are masked by
the friends stream instead.

### coaching_relationship (RPC-written + both-sides SELECT)
`coach_user_id` + `athlete_user_id` (composite PK), `created_date`,
`accepted_date` (nullable — the consent gate, 2026-10-26). A row without
`accepted_date` is an invitation still waiting on the athlete: the
`coaching_data` stream's `my_athletes` CTE requires it, so nothing about that
athlete reaches the coach's device. The coach's own rows (the column
included) ride `user_data`, so the local mirror can see a pending invitation.
The athlete's name and completed training arrive only through
`coaching_data`.

**Lifecycle (2026-10-26, #22) — three SECURITY DEFINER RPCs are the only
writes:**
- `coach_invite_by_code(p_code)` resolves a friend code the caller cannot
  read by any other route and inserts the pending row. Returns
  `{athlete_user_id, created}`; `created` is false when the row already
  existed, so the client mirrors only a brand-new invitation.
- `accept_coaching_invitation(p_coach_user_id)` stamps `accepted_date` — the
  athlete's consent, and the moment the gate opens.
- `remove_coaching_relationship(p_other_user_id)` deletes the edge from
  either side: decline (a pending row), withdraw (the coach's own pending),
  revoke (the coach's accepted edge) or withdrawal of consent (the athlete's
  accepted edge). One verb, one row.

The client mirrors each RPC locally — the coach's insert under
`coach_user_id || '-' || athlete_user_id`, the athlete's accepted-date
UPDATE, the pair DELETE (whose queued op the uploader then skips, exactly as
on friends). The two surviving client write policies are shaped for those
mirrors alone: **coach INSERT** requires `accepted_date is null` (an
invitation, never consent), **athlete UPDATE** only their own row. There is
no client DELETE policy — removal is the RPC's. Every **coach access**
SELECT policy on the athlete's tables now carries
`cr.accepted_date is not null`, so REST refuses what the stream refuses.

The same screen serves both sides: Profile → Coach lists incoming
invitations (the coach's name arrives while the invitation is still pending
— `coaching_data`'s `my_coaches` slice, because an athlete cannot consent to
an anonymous request), the accepted athletes (opening
`LogsScreen(userId:, readOnly:)` → `SessionDetailScreen(userId:, readOnly:,
navRoute: '/profile')`), the caller's own coaches, and nameless pending-sent
rows — nothing about an unaccepted athlete reaches the coach's device, not
even a name.

### fact_coach_assignment — a workout a coach hands an athlete (2026-10-26, #24)
`assignment_id` (text PK, client-generated uuid), `coach_user_id` /
`athlete_user_id` (FK → dim_user, ON DELETE CASCADE), `planned_session_id`
(the coach's template — provenance, never read by the athlete's copy),
`name` (the workout's name at send time), `note` (nullable prose),
`snapshot_content` (a `ProgramContent` document, schema 2 — the frozen
workout), `names_json` (only the ids that workout uses:
`{"exercises": {id: name}, "variations": {id: name}}`, because dim ids are
per-user), `created_date`, `accepted_date` / `declined_date` (null = pending;
both set = a race the client never intends), `athlete_planned_session_id`
(the copy that landed, for the coach's status line).

An assignment is an **offer, not a shared row**: the athlete's accept
decodes the snapshot, resolves each exercise/variation **by name** against
their own library (create when missing, reactivate when archived; an
unresolvable group is skipped), and writes a fresh `dim_planned_session` +
groups + sets in one local transaction, stamping `coach_assignment_id` on
the new template. `coaches_athlete(coach, athlete)` (SECURITY DEFINER,
accepted rows only) gates the coach's INSERT; the athlete's accept/decline
is an UPDATE on their own row; withdraw is the coach's DELETE while
`accepted_date is null`. Both sides read.

### fact_coach_feedback — a coach's note on one session (2026-10-26, #24)
`feedback_id` (text PK, client-generated uuid), `coach_user_id` /
`athlete_user_id`, `session_id` (FK → fact_session, ON DELETE CASCADE),
`body` (prose, uncapped), `created_date`, `edited_date`. **One row per
(coach, session)** — a unique index enforces it and `saveFeedback` updates
the existing row rather than inserting a second. The coach writes on the
athlete's session viewer (`SessionDetailScreen(canCoach: true)`), the
athlete reads it on their own record; a friend's record never draws it (the
stream sends feedback only to its two parties). RLS: read either side,
insert/update/delete the coach's own row, and INSERT additionally requires an
accepted coaching edge plus that the session belongs to the athlete.

### app_config (public SELECT)
`platform`, `min_version`, `latest_version`, `updated_at`. Read via REST
for the force-update gate. NOT in the PowerSync publication.

### upload_failures — LOCAL-ONLY, never synced
`table_name`, `op_id`, `op_type`, `op_data`, `error_code`, `created_at`.
Quarantine rows for CRUD uploads that failed fatally (RLS / FK / type).
Exists only in the client schema — not on the server, not in sync streams.

## CRUD & lifecycle matrix

What actually happens to each table's rows.

| Table | Create | Update | Delete |
|---|---|---|---|
| dim_user | auth trigger (`handle_new_user`) | profile screen | never (cascade from auth.users) |
| dim_exercise | session add-exercise modal, exercise library | rename | **archive** (`date_archived = now()`), or hard-delete when never used; reactivate clears the date |
| dim_variation | same | rename | same |
| dim_lesson | session / past-session / planner (with `session_id` where a logged session exists) | pin toggle | **archive** |
| dim_program | REST insert in `createProgram` (authoritative write; deliberately NOT written to local mirror — a local write would queue a CRUD entry that blocks the checkpoint) | name/description (+ `program_updated_date` bump) | **archive** (`date_archived = now()`) + hard-delete its join rows; `hardDeleteProgram` (no-sessions only) hard-deletes in dependent-row order: reviews → goals → links → run unlinks → runs → blocks → program |
| dim_planned_session | `createPlannedSession` (local INSERT) | name/notes | **archive** (`date_archived = now()`) + archive its groups/sets, hard-delete join rows |
| dim_planned_session_program | `createProgramLink` (planner creates + links; wizard; copy-into-program) | slots (day_of_week / week_offset / sequence_order) | **hard DELETE** (unlink — template survives standalone) |
| dim_planned_session_exercise | `createPlannedExercise` (on add-exercise in the planner) | `exercise_order` via reorder | **archive** + archive its sets |
| dim_planned_session_exercise_set | `createPlannedSet` | targets | **archive** |
| fact_session | `createSession` (end_datetime NULL) | `endSession` (end_datetime = now, post_notes, post_feeling), `updateSessionNotes` | **hard DELETE** on `cancelSession` (with its exercise rows + sets) |
| fact_session_exercise | `insertSessionExercise` (materialization + add-exercise) | `updateSessionExercise` (tab switching), `reorderSessionExercises` | **hard DELETE** (with its sets) |
| fact_session_exercise_set | `insertSet` | `updateSet`, `reorderSets` | **hard DELETE** |
| fact_program_run | REST insert in `startProgramRun` (ends previous is_current first — required by the partial unique index; takes progressionMode) | `updateRunConfig` (mode + duration), `pauseCurrentRun`/`resumeRun` (is_current) | never in the UI (history); hard-deleted only with `hardDeleteProgram` |
| dim_program_block | `createProgramBlock` (block editor) | `updateBlock`, `reorderBlocks` (block_order) | **archive** (`date_archived = now()`), `reactivateBlock` clears it; hard-deleted only with `hardDeleteProgram` |
| fact_program_review | `beginReview` (row + "as found" baseline, one move; `program_id` null = standalone) or `scheduleReview` (row only — a dated review must not freeze today's plan) | `captureBaseline` (idempotent — only where NULL), `markWorkoutReviewed` / `unmarkWorkoutReviewed` (tick map, read-modify-write, guarded on open), `setExerciseNote` / `setWorkoutNote` (write-through, read-modify-write of the JSON), `completeReview` (snapshot + completed_date + outcome, one transaction), `closeRun` (kind = 'close'), `deleteReview` (hard delete, guarded `completed_date IS NULL` — the Reviews list's cancel), `deleteCompletedReview` (hard delete, guarded `completed_date IS NOT NULL` — deleting a record, 2026-10-19) | never in the UI (history); hard-deleted with `hardDeleteProgram` — and before runs, which they pin via NO ACTION — by `deleteReview` when an open pass is cancelled, and by `deleteCompletedReview` when a record is deleted |
| fact_goal | run-start prompt, `createGoal` | `achieved_date` set/revoked, `updateGoal` | **hard DELETE** |
| fact_goal_target | `createGoal` / `updateGoal` write the rung list (delete-then-insert in one transaction); a single-set goal writes none | — (rewritten wholesale with the goal) | **hard DELETE** with its goal (client-mirrored cascade), `deleteGoal` and `hardDeleteProgram` |
| fact_bodyweight | profile weight logging | — | hard delete (rarely used) |
| dim_friend_code | `after insert on dim_user` trigger (SECURITY DEFINER) + migration backfill | never (codes are stable in v1) | never (cascade from auth.users → dim_user) |
| friend_relationship | `add_friend_by_code` RPC writes BOTH directions; the client mirrors only the caller's own directed row | — | `remove_friend` RPC deletes both directions, callable from either side; the client also deletes its own local row and drops the friend's cached timeline |
| coaching_relationship | `coach_invite_by_code` RPC writes the pending row; the client mirrors it locally only when `created` (coach→athlete). `accept_coaching_invitation` RPC + an accepted-date mirror (athlete) | acceptance only (`accepted_date`), via RPC | `remove_coaching_relationship` RPC from either side (decline / withdraw / revoke / consent withdrawal) + a local pair delete whose queued op the uploader skips |
| fact_coach_assignment | `createAssignment` (coach, local INSERT with a `ProgramContent` snapshot + `names_json`) | athlete's accept (`accepted_date`, `athlete_planned_session_id`) / decline (`declined_date`), local-first on the synced row | `withdrawAssignment` (coach, local DELETE while `accepted_date is null`; the accepted copy is untouched) |
| fact_coach_feedback | `saveFeedback` (local INSERT, id = `feedback_id`) | `saveFeedback` rewrites the author's own row (`body` + `edited_date`) | `deleteFeedback` (author only, local DELETE) |
| app_config | manual/ops | manual/ops | manual/ops |

## RLS policy matrix (verified current state)

Every table has RLS enabled. Three policy shapes:

1. **owner access** (ALL, `user_id = auth.uid()` using + with-check) — on
   every user-owned table.
2. **coach access** (SELECT, `EXISTS (SELECT 1 FROM coaching_relationship cr
   WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = <t>.user_id
   AND cr.accepted_date IS NOT NULL)`) — on every athlete-owned table (the
   gate added 2026-10-26, #22: a pending invitation grants nothing on REST
   either).
3. **friend access** (SELECT, `public.are_friends(auth.uid(), user_id)`,
   2026-10-23) — on the eight tables a friend's history reads:
   `fact_session` (additionally `end_datetime is not null`),
   `fact_session_exercise` / `fact_session_exercise_set` (additionally their
   parent session is completed), `dim_exercise`, `dim_variation`,
   `dim_lesson`, `fact_goal`, and (2026-10-26) `fact_goal_target` — a goal
   row without its rungs reads as a goal with no target, which is why the
   friends stream sends them and the REST defence matches. `are_friends(a, b)` is SECURITY DEFINER and
   requires **both** directed rows, so a half-pair grants nothing; it avoids
   recursive policy evaluation, and its only exposure is a boolean for a pair
   of UUIDs. `dim_lesson`'s policy is the one tier-aware exception: it
   requires `friend_shares_notes(user_id, auth.uid())` instead (2026-10-26,
   #23), the same gate the stream applies. The stream is the real privacy
   boundary — these policies are the REST defence, and for `fact_session`'s
   note COLUMNS the stream is the only gate.

| Table | Owner ALL | Coach SELECT |
|---|---|---|
| dim_user | ✅ | ✅ |
| dim_exercise | ✅ | ✅ |
| dim_variation | ✅ | ✅ |
| dim_lesson | ✅ | ✅ |
| dim_program | ✅ | ✅ |
| dim_planned_session | ✅ | ✅ |
| dim_planned_session_program | ✅ | ✅ |
| dim_planned_session_exercise | ✅ | ✅ |
| dim_planned_session_exercise_set | ✅ | ✅ |
| fact_session | ✅ | ✅ |
| fact_session_exercise | ✅ | ✅ |
| fact_session_exercise_set | ✅ | ✅ |
| fact_program_run | ✅ | ✅ |
| dim_program_block | ✅ | ✅ |
| fact_program_review | ✅ | ✅ |
| fact_goal | ✅ | ✅ |
| fact_goal_target | ✅ | ✅ |
| fact_bodyweight | ✅ | ✅ |
| coaching_relationship | coach INSERT (accepted_date is null) + athlete UPDATE (own row) + read SELECT (either side); removal is the RPC's, so no DELETE policy | — |
| fact_coach_assignment | coach INSERT (own + `coaches_athlete` + both stamps null) + athlete UPDATE (own row) + coach DELETE (own, while `accepted_date is null`) + read SELECT (either side) | — |
| fact_coach_feedback | coach INSERT (own + `coaches_athlete` + the session belongs to the athlete) + coach UPDATE/DELETE (own rows) + read SELECT (either side) | — |
| dim_friend_code | **owner SELECT only** (no insert/update/delete grants; the trigger writes it) | — |
| friend_relationship | own row ALL (`user_id = auth.uid()`) + both-sides SELECT (the reciprocal row is written by the SECURITY DEFINER RPC) | — |
| app_config | public SELECT (true) | — |

Anon never has a matching `auth.uid()`, so table-level grants to anon are
harmless (RLS is the gatekeeper).

## Sync wiring

Every synced table must be registered in four places (see the
`sync-contract` skill for the full contract): server publication (24 tables),
`powersync/sync-streams.yaml` (queries alias the real PK as `id`),
`lib/core/powersync/schema.dart`, and `lib/core/powersync/database.dart`
(`_pkColumns` / `_compositeKeyTables` upload mapping). Three auto-subscribed
streams since 2026-10-26: `user_data` (the user's own rows — since #24 also
the coach assignment and feedback rows on either side of the pair, the
`coaching_relationship` shape), `coaching_data` (a coach's consented view of
an athlete's completed training, #22), and `friends_data`
(`dim_friend_code` own + each mutual friend's, `friend_relationship` own
directed rows with their nicknames and privacy tiers, and each mutual friend's
completed records + names slice — a friend's notes only when they share them,
2026-10-26 — see `sync-contract`).
Local-only: `upload_failures`. REST-only (not synced): `app_config`.

## Cross-references

- Schema / sync wiring changes: see the `sync-contract` skill (every table must
  be registered in schema.dart + database.dart + sync-streams.yaml + server
  publication + RLS).
- DB redesign decisions: `docs/schema_redesign_plan.md` (2026-08-13 v1) and
  `docs/schema_redesign_v2.md` (2026-08-24 v2 — the current schema); migrations
  in `supabase/migrations/` (20260813 redesign, 20260814 cleanup + fact_rest/
  fact_pr drops, 20260824 v2).
