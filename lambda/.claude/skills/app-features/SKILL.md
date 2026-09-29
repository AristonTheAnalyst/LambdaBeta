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
| **Program runs** | `fact_program_run` (carries `progression_mode`) | Literal |
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
update). **No progression mode
and no length** — how the program is RUN is a property of the run.
Programs are never hard-deleted (archive only). Duplication deep-copies the
program + its planned sessions + groups + sets + links.

### Program runs — `fact_program_run`
The commitment: "I'm doing this program for X." Columns: `program_id` (NO
ACTION FK), `started_date`, `ended_date` (NULL = running), `is_current`
(partial unique index — at most one current run per user),
`progression_mode` ('frequency' | 'order' — chosen at run start, v2;
backfilled from the old program column), `target_sessions` (order),
`target_weeks` / `end_date` (frequency). **Frequency** runs schedule by the
join rows' `day_of_week`/`week_offset` (fortnight week computed from
`started_date`); **order** runs walk the join rows by `sequence_order` with
a completed-session cursor. Starting a run ends the previous current one.
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
  │                        (join rows carry sequence_order /
  │                         day_of_week / week_offset)
  │                                   │
  │                                   └──< dim_planned_session_exercise
  │                                           └──< dim_planned_session_exercise_set
  ├──< fact_program_run ──< dim_program (one current run per user,
  │         │                              progression_mode on the run)
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
`program_updated_date` (v2).
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
`target_sessions`, `target_weeks`, `end_date`.

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
| dim_program | REST insert in `createProgram` (authoritative write; deliberately NOT written to local mirror — a local write would queue a CRUD entry that blocks the checkpoint) | name/description (+ `program_updated_date` bump) | **archive** (`date_archived = now()`) + hard-delete its join rows |
| dim_planned_session | `createPlannedSession` (local INSERT) | name/notes | **archive** (`date_archived = now()`) + archive its groups/sets, hard-delete join rows |
| dim_planned_session_program | `createProgramLink` (planner creates + links; wizard; copy-into-program) | slots (day_of_week / week_offset / sequence_order) | **hard DELETE** (unlink — template survives standalone) |
| dim_planned_session_exercise | `createPlannedExercise` (on add-exercise in the planner) | `exercise_order` via reorder | **archive** + archive its sets |
| dim_planned_session_exercise_set | `createPlannedSet` | targets | **archive** |
| fact_session | `createSession` (end_datetime NULL) | `endSession` (end_datetime = now, post_notes, post_feeling), `updateSessionNotes` | **hard DELETE** on `cancelSession` (with its exercise rows + sets) |
| fact_session_exercise | `insertSessionExercise` (materialization + add-exercise) | `updateSessionExercise` (tab switching), `reorderSessionExercises` | **hard DELETE** (with its sets) |
| fact_session_exercise_set | `insertSet` | `updateSet`, `reorderSets` | **hard DELETE** |
| fact_program_run | REST insert in `startProgramRun` (ends previous is_current first — required by the partial unique index; takes progressionMode) | `updateRunConfig` (mode + duration) | never (history) |
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
| fact_goal | ✅ | ✅ |
| fact_bodyweight | ✅ | ✅ |
| coaching_relationship | coach ALL (coach_user_id = uid) + read SELECT (either side) | — |
| app_config | public SELECT (true) | — |

Anon never has a matching `auth.uid()`, so table-level grants to anon are
harmless (RLS is the gatekeeper).

## Sync wiring

Every synced table must be registered in four places (see the
`sync-contract` skill for the full contract): server publication (16 tables),
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
