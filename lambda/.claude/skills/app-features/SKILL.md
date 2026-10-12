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
| **Goals** | `fact_goal` | Literal |
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
- **A record reads (2026-10-12)**: both lists on a record are doors, into
  readings. A workout card opens `RecordWorkoutScreen` — the **pass's own
  chrome** (header, shared card, the review's bar at the floor) over the
  record's two frozen sides: `baseline_content` as `beginReview` found it and
  `snapshot_content` as the pass completed, both narrowed by `contentInScope`,
  never the live plan (which keeps being edited). The eye flips between the
  two, named on a page caption (`BEFORE · 8 Oct 2026` / `AFTER · 9 Oct 2026`)
  and on the bar's own label, which over a record's workout names the side on
  screen — `kReviewAfterLabel` / `kReviewBeforeLabel`, green rim and words at
  rest turning accent as the eye turns, through the label's usual rise —
  rather than the walk the way a pass's label does ("Review Complete"
  outranks what is on screen, then "In Review" / "Previously"); a record with
  only one side offers no eye.
  **The names carry the sides' disagreement** (2026-10-12): an exercise the
  side on screen holds and the other does not wears a green **plus** (absent
  from the base, so the review added it) or a red **minus** (in the base and
  not on screen, so it dropped it) — `ExerciseMark` on the shared selector
  (each glyph a plus or minus inside a filled disc), in
  the field and in every popover row, one membership test over
  `plannedExerciseId` with two readings so the marks can never disagree across
  the eye. Names both sides hold stay bare, and a record with one side marks
  nothing — there is no second document to have read an edit off.
  The bar is handed the row's `ReviewSession` (`reviewChrome(session:,
  readOnly: true, loadComparison:)`), never publishing one, so Compare and
  Changes read those same two documents through the injected comparison; the
  tick is **drawn wearing the record's answer and disabled** — green
  (`success`) under `GlassButton`'s half opacity when the record ticks it —
  and the note glyph stays greyed. Every other callback is null or inert, with
  exercises switchable because looking is not writing. The review's own notes
  read back: the exercise's box under its sets (`reviewNoteEmptyText` keeps it
  drawn, reading "No note" where the review left none — the pass draws that
  box under every exercise, so the record's furniture does not depend on what
  was typed) and the workout's above the card when it has one. The row is read on the route (`_openRecordWorkout` → `fetchReview`)
  and the screen takes plain data, so it loads nothing and holds no loading
  state; a row with no snapshot (a dismissed completion, a pre-snapshot row)
  arrives as a null record and says so rather than drawing an empty grid.
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

### Goals — `fact_goal`
Goals are **PRs to be beat**: a target weight × reps for an exercise
("bench 100kg × 1" = beat the current 1RM). Achieving a goal means the
derived PR curve has caught up to or passed the target. `program_run_id` is
an optional link to a run (created at run start via prompt). `achieved_date`
marks completion (NULL = still chasing) — but it is **revocable**: the
frontend must let the user clear an achievement (set `achieved_date` back to
NULL), because a data-entry error (1000kg instead of 100kg) can falsely
mark a goal achieved and the mistake should be undone by the user, not
silently. Facts — hard-deleted.

### Bodyweight — `fact_bodyweight`
Weight measurements: `user_weight`, `user_weight_date` (measurement date),
`created_date` (log date). Profile screen logs these.

### PRs — **fully derived, no table**

**What a PR is**: an improvement to the best weight lifted for a given rep
count (rep-max), or the most reps ever lifted at a given weight (weight-max),
for an exercise — optionally filtered by variation. A single set can be many
PRs at once (105kg × 3 beats your 1RM, 2RM AND 3RM).

Since 2026-08-14 `fact_pr` is dropped. PRs are computed on every read by
`PrService` (`lib/features/session/model/pr_service.dart`) from
`fact_session_exercise_set` history (joined through `fact_session_exercise`
for the exercise id), using the rep-max engine
(`lib/features/session/model/pr_engine.dart`). Memoized until `invalidate()`
(call after ANY set write).

**Rep-max values**: `curve[N]` = the highest weight ever lifted for **≥ N
reps**. Tracked N values: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 30.
Anything above 30 reps is not a PR axis. The curve is monotone non-increasing
in N (if you can lift 100 for 5, you can lift 100 for any N < 5).

**Curves are scoped per (exercise × variation)**. A Pause Bench PR never
affects regular Bench: each (exerciseId, variationId) pair has its own
independent rep-max curve and weight-max map. NULL variation is its own
distinct key (a non-variated set does not share a curve with variated sets
of the same exercise).

**Weight-max values**: for each distinct weight W, `maxReps[W]` = the most
reps ever done at exactly W. If you can lift W × R, you can lift any lighter
weight at least R times — so a heavier lift bumps the implied max of all
lighter weights too.

**What a propagated PR is**: a record *implied* by a different, stronger
actual performance, rather than directly achieved. Example: you do 100kg × 5.
The 5RM at 100kg is **explicit** — you actually did it. The 3RM at 100kg is
**propagated** — you never did 100 × 3, but 100 × 5 proves you can. Same for
weight-max: doing 80kg × 5 propagates "most reps at 60kg = 5" — but only if
60kg was already in the map, i.e. the user lifted 60kg before (they just
never got 5 reps at it). **Weights never actually lifted are never
fabricated** — propagation bumps only weights that exist in the history.
`isPropagated` distinguishes these in the UI ("achieved" vs "implied").

**The formula** (walks all logged sets chronologically, per exercise):

```
for each set (weight W, reps R, exercise E, variation V), oldest first:
  # rep-max axis, scoped to the (E, V) curve
  for each tracked N where N ≤ R:
    if W > curve[(E, V)][N]:
      curve[(E, V)][N] = W
      emit PR(E, V, repMax, targetReps=N, weight=W, reps=R, propagated=(N ≠ R))
  # weight-max axis, scoped to the (E, V) map
  if R > maxReps[(E, V)][W]:
    maxReps[(E, V)][W] = R
    emit PR(E, V, weightMax, targetWeight=W, weight=W, reps=R, propagated=false)
    for each lighter weight L ALREADY in the map (a weight explicitly
    lifted before) where maxReps[(E, V)][L] < R:
      maxReps[(E, V)][L] = R
      emit PR(E, V, weightMax, targetWeight=L, weight=L, reps=R, propagated=true)
    # never create map entries for weights between W and L — only explicit
    # lifts exist as keys
```

Bodyweight is just weight 0 — it feeds the rep-max curve like any other
weight (a 13-rep dips set is a 12RM at 0kg), and its weight-max propagation
only bumps the 0kg key. Reps that fall between tracked values claim the
highest tracked value below them as the explicit record (13 reps → explicit
12RM); lower tracked Ns stay propagated.

**Display & counting rules (2026-08-26)**: propagated records appear NOWHERE —
`achievedRecords` filters the timeline and before-chains. Weight-max records
(bodyweight 0kg included — bodyweight is just a weight) are **display-only**:
visible in PR detail/timeline surfaces, never counted. Counts, badges, session
totals, and insights charts use explicit rep-max only (`countableRecords`).

Edit-past-data needs no recompute — the next read is correct by construction.
**Data-entry errors self-heal**: a typo'd 1000kg set creates a bogus 1000kg
PR while the bad data exists, but correcting the set removes the PR on the
next derivation — nothing stale persists to clean up. This is a direct
consequence of derive-only and the main reason goals (persisted) need an
explicit revoke action while PRs don't.

### History / training logs — **derived read view**
The Training Logs screen and past-session viewer read `fact_session` +
`fact_session_exercise` + `fact_session_exercise_set` joined with current
exercise/variation names. No table of its own. `PastSetRow` (a
`SessionExerciseSet` + session date) powers the per-exercise history
timeline.

### Analytics / insights — **derived, client-side**
Statistics, PR catalog, PR exercise detail, and insights screens aggregate
the local PowerSync mirror (all reads are local SQLite). No server-side
analytics, no aggregates tables. At this scale a dedicated OLAP store is
not justified; if analytics ever get slow, a client-computed daily-summary
table is the fix.

## Features you didn't list (worth remembering)

| Feature | Where | Notes |
|---|---|---|
| **User profile** | `dim_user` | name, DOB, gender, height, weight, `onboarded` flag. `user_`-prefixed columns (legacy naming) |
| **Rest timer** | in-memory only | `fact_rest` was dropped 2026-08-14 — no rest analytics. Timer still drives the AVG REST stat from `restDurationsThisSession` |
| **Supersets** | retired | Column `superset_group_number` DROPPED 2026-08-24 (schema v2). No UI creates supersets; dormant slot support renders a restored multi-exercise slot as its first exercise |
| **Feelings** | `fact_session.pre_feeling` / `post_feeling` | Pre-workout feeling is shown in logs; `post_feeling` is written but **never displayed yet** — logs screen is the candidate place |
| **Coaching** | `coaching_relationship` + coach RLS policies | Table + policies exist; no coach UI. Coach SELECT access exists on every athlete-owned table |
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

### fact_goal — goals (owner ALL, coach SELECT)
`goal_id` (PK), `user_id`, `goal_text`, `custom_exercise_id` (nullable),
`target_weight`, `target_reps`, `program_run_id` (nullable FK →
fact_program_run), `achieved_date` (nullable, revocable),
`goal_created_date`.

### fact_bodyweight — weight measurements (owner ALL, coach SELECT)
`user_weight_id` (PK), `user_id`, `user_weight`, `user_weight_date`
(measurement date), `created_date` (log date).

### coaching_relationship (coach ALL + both-sides SELECT)
`coach_user_id` + `athlete_user_id` (composite PK), `created_date`. No app
UI yet.

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
| fact_program_review | `beginReview` (row + "as found" baseline, one move; `program_id` null = standalone) or `scheduleReview` (row only — a dated review must not freeze today's plan) | `captureBaseline` (idempotent — only where NULL), `markWorkoutReviewed` (tick map, read-modify-write, guarded on open), `setExerciseNote` / `setWorkoutNote` (write-through, read-modify-write of the JSON), `completeReview` (snapshot + completed_date + outcome, one transaction), `closeRun` (kind = 'close'), `deleteReview` (hard delete, guarded `completed_date IS NULL` — the Reviews list's cancel) | never in the UI (history); hard-deleted with `hardDeleteProgram` — and before runs, which they pin via NO ACTION — and by `deleteReview` when an open pass is cancelled |
| fact_goal | run-start prompt, `createGoal` | `achieved_date` set/revoked | **hard DELETE** |
| fact_bodyweight | profile weight logging | — | hard delete (rarely used) |
| coaching_relationship | (no UI yet) | — | hard delete |
| app_config | manual/ops | manual/ops | manual/ops |

## RLS policy matrix (verified current state)

Every table has RLS enabled. Two policy shapes:

1. **owner access** (ALL, `user_id = auth.uid()` using + with-check) — on
   every user-owned table.
2. **coach access** (SELECT, `EXISTS (SELECT 1 FROM coaching_relationship cr
   WHERE cr.coach_user_id = auth.uid() AND cr.athlete_user_id = <t>.user_id)`)
   — on every athlete-owned table.

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
| fact_bodyweight | ✅ | ✅ |
| coaching_relationship | coach ALL (coach_user_id = uid) + read SELECT (either side) | — |
| app_config | public SELECT (true) | — |

Anon never has a matching `auth.uid()`, so table-level grants to anon are
harmless (RLS is the gatekeeper).

## Sync wiring

Every synced table must be registered in four places (see the
`sync-contract` skill for the full contract): server publication (19 tables),
`powersync/sync-streams.yaml` (queries alias the real PK as `id`),
`lib/core/powersync/schema.dart`, and `lib/core/powersync/database.dart`
(`_pkColumns` upload mapping). Local-only: `upload_failures`.
REST-only (not synced): `app_config`.

## Cross-references

- Schema / sync wiring changes: see the `sync-contract` skill (every table must
  be registered in schema.dart + database.dart + sync-streams.yaml + server
  publication + RLS).
- DB redesign decisions: `docs/schema_redesign_plan.md` (2026-08-13 v1) and
  `docs/schema_redesign_v2.md` (2026-08-24 v2 — the current schema); migrations
  in `supabase/migrations/` (20260813 redesign, 20260814 cleanup + fact_rest/
  fact_pr drops, 20260824 v2).
