# Schema Redesign v2 — Plan of Record

2026-08-24. Supersedes `docs/schema_redesign_plan.md` (the 2026-08-13 v1 redesign —
kept as history). Driven by user feedback on the current schema; the feedback
digest and rationale for each change are in [Answers to the feedback](#answers-to-the-feedback).

> **2026-08-26 follow-up (migration `20260826000000_snapshots_out_fks_in.sql`):**
> names live in the dims, full stop. FK constraints added on
> `fact_session_exercise.custom_exercise_id → dim_exercise` and
> `fact_session_exercise_set.custom_variation_id → dim_variation` (dims are
> archive-only, so they can never dangle); all four name snapshot columns
> dropped. Renaming an exercise or variation now updates ALL past data (the
> rename flows warn about this). Client pairing: `23503` added to the fatal
> upload codes so a would-be FK violation quarantines instead of stalling the
> checkpoint.

This is a **breaking, one-shot migration** — this app has a single user, so there
is no fleet to support and no need for dual-write compatibility windows. The
migration preserves all training history (≈3 years of data).

---

## Feedback digest

1. Drop `dim_exercise_variation_bridge` — variations and exercises are independent.
2. Drop `dim_program.program_length_weeks`.
3. Move progression mode from the program to the **run**. At run start the user
   picks *frequency split* (assign workouts to days in a week/fortnight) or
   *order split* (workouts done in sequence).
4. Add `dim_program.program_updated_date` (`program_created_date` already exists).
5. New `fact_session_exercise` table between `fact_session` and sets, with a
   clear one-to-many to `fact_session_exercise_set`. Exercise is nullable.
6. `fact_session`: drop `program_id` (the run already carries it), drop the
   `exercise_order` JSON blob (solved by `fact_session_exercise.exercise_order`
   — same name, now a real column),
   replace `parent_session_id`/`parent_session_name`/`program_name` with a single
   `planned_session_id` link, replace `is_active` with `end_datetime`, rename
   `created_date` → `created_datetime`.
7. `fact_session_set`: drop `parent_set_id`, `superset_group_number`, and the
   denormalized `exercise_name`/`variation_name` (exercise name moves up to
   `fact_session_exercise`).
8. Mirror the split on the planned side: `dim_planned_session`,
   `dim_planned_session_exercise`, `dim_planned_session_exercise_set`.
9. New join table `dim_planned_session_program` (M2M) so a planned session can
   belong to several programs.
10. `dim_planned_session`: drop `sequence_order` and `day_of_week` (they move to
    the join table).

---

## Answers to the feedback

**Why are all the primary keys text?** — PowerSync. Rows created offline need
client-generated IDs before they ever reach the server, so every repo INSERT
generates a `uuid.v4()` (`_uuid` in `session_repository.dart` etc.). PowerSync
additionally requires every synced table to expose a text PK aliased as `id` on
the client, and the upload path (PUT/PATCH/DELETE by id) addresses rows with the
same id the client generated. The server tables therefore use `text` PKs to keep
client and server 1:1 — a Postgres `uuid` type would still arrive as text and
just adds cast friction. Composite-key tables (`dim_exercise_variation_bridge`,
`coaching_relationship`) got synthetic client id columns for the same reason.
Not worth changing for this app.

**What is `fact_session.exercise_order` even for?** — It's UI tab state: the
JSON blob stores the order of exercise pills after the user drags them with the
reorder arrows (`saveExerciseOrder`), so a hot-restart and the past-session
viewer show the same tab order. It's device-local UI state stuffed into a synced
column — agreed it's weird. `fact_session_exercise.exercise_order` replaces it
as a real column (same name, no longer a blob), and the logs viewer ordering
bug class (never reading the blob) disappears with it.

**What is `fact_session_set.parent_set_id` for?** — It's the ghost-hint anchor,
and it IS load-bearing today. At session start, planned rows are materialized as
real `fact_session_set` rows carrying `parent_set_id` = the
`dim_planned_session_set.set_id`, and the planned targets ("60-70", "8-15")
render by joining on that id — id-anchored, never positional (the 2026-08-23
fix). In v2 the same mechanism relocates to the new hierarchy:

- `fact_session_exercise.planned_exercise_id` → `dim_planned_session_exercise`
- `fact_session_exercise_set.planned_set_id` → `dim_planned_session_exercise_set`

Same anchor semantics, cleaner home. Naming note: `parent_set_id` IS the planned
set id — it stores `dim_planned_session_set.set_id` verbatim, named "parent" to
match the `parent_session_id` family. The v2 rename is pure naming (backfill is
a straight copy), and it actually restores the pre-2026-08-13 name: that
migration renamed `planned_set_id` → `parent_set_id`. v2 also fixes the
asymmetry — the column now matches the PK it points at
(`planned_set_id` → `planned_set_id`).

**Why do `exercise_name` / `variation_name` exist on fact rows?** — They are
**snapshots**, not lookups: the name as of log time survives later renames of
the dim, and hot-path queries don't join. With `fact_session_exercise` in the
middle, `exercise_name` lives **once per session-exercise** instead of once per
set, and sets drop it entirely. `variation_name` must **stay on the set row**
because variation remains per-set (a paused bench set among normal ones is a
legitimate row), so the snapshot stays at the level where the variation id lives.

**`is_active` vs `end_datetime`** — agreed. `end_datetime IS NULL` = active;
all `is_active = 1/0` queries become `end_datetime IS NULL / IS NOT NULL`.
Cancel keeps today's behavior: cancelled sessions are hard-DELETEd, so they
never get an `end_datetime` and never appear in logs. One caveat: historical
completed rows have no real end time (duration columns were dropped
2026-08-14) — backfill `end_datetime = created_date` for them; duration will
read 0 for pre-migration history. New sessions record the true end time.

**Why is `program_id` on `fact_session`?** — denormalized attribution, and yes
it's redundant: `program_run_id` → run → program, and standalone sessions have
NULL run id. Dropped along with the `program_name` snapshot.

**Bridge removal** — agreed. Variations become a flat per-user library. PR
scoping is untouched: the engine keys curves on `(exercise_id, variation_id)`
directly from set rows, which keep both ids. UI impact: the variation edit
screen loses its exercise-assignment list (assignment was one-way,
variation-first); the set-row variation picker shows all variations instead of
the exercise's assigned set (global "Did you mean?" dedup, which is simpler);
`ExerciseDetail.variations` disappears. The bridge has no downstream consumers
beyond assignment UI, so dropping it loses nothing but the M2M metadata.

**Progression mode at run level** — today `fact_program_run` has **no**
progression column; `getNextPlannedSession` receives `progressionMode` as a
parameter that callers read from the *program*. v2 adds `progression_mode` to
`fact_program_run` ('frequency' | 'order', set in the start-run flow). The
day/sequence assignments themselves live on the **join table** rows — that's
what makes a session able to be Monday in program A and Wednesday in program B.
Fortnight support: `week_offset` (0 = week 1, 1 = week 2, NULL = every week),
computed against `run.started_date` (`floor(days_since / 7) % 2`).

**`program_length_weeks`** — confirmed dead: nothing in the UI writes it; the
only reader is `getProgress`'s fallback `run.targetWeeks ?? program.lengthWeeks`.
After removal that fallback is simply null.

---

## Target schema v2

```
DIMENSIONS (reference data — soft delete via is_archived unless noted)
───────────────────────────────────────────────────────────────────────

dim_exercise                     (unchanged)
  custom_exercise_id PK, user_id, exercise_name, is_archived

dim_variation                    (unchanged)
  custom_variation_id PK, user_id, variation_name, is_archived

dim_program
  program_id PK, user_id, program_name, program_description,
  is_archived, program_created_date,
  program_updated_date            (NEW — bumped by every program UPDATE)
  [removed: program_length_weeks, progression_mode]

dim_planned_session              (template)
  session_id PK, user_id, name, notes, is_archived, created_date
  [removed: program_id, sequence_order, day_of_week]

dim_planned_session_program      (NEW join, M2M — hard-deleted, nothing refs it)
  planned_session_program_id PK (client uuid, synthetic for PowerSync),
  user_id,
  program_id FK → dim_program (NO ACTION),
  planned_session_id FK → dim_planned_session (NO ACTION),
  sequence_order int,            (position in program — order split)
  day_of_week int NULL,          (1–7 — frequency split)
  week_offset int NULL,          (0/1 fortnight week; NULL = every week)
  UNIQUE (program_id, planned_session_id)

dim_planned_session_exercise     (NEW — split out of dim_planned_session_set)
  planned_exercise_id PK, user_id,
  planned_session_id FK → dim_planned_session (NO ACTION),
  custom_exercise_id NULL,       (nullable for parity with fact side)
  exercise_order int,            (renamed from exercise_sequence_order)
  exercise_name,                 (snapshot — one per group, not per row)
  is_archived

dim_planned_session_exercise_set (NEW — renamed dim_planned_session_set)
  planned_set_id PK, user_id,
  planned_exercise_id FK → dim_planned_session_exercise (NO ACTION),
  custom_variation_id NULL,
  set_number int,
  target_weight TEXT NULL,       (free-form hint: "60", "60-70")
  target_reps TEXT NULL,         (free-form hint: "10", "8-15", "AMRAP", "3 RIR")
  target_notes,
  variation_name,                (snapshot — variation stays per set)
  is_archived


FACTS (events — hard-deleted, never soft)
────────────────────────────────────────

fact_session
  session_id PK, user_id,
  pre_notes, post_notes,
  created_datetime,              (renamed from created_date)
  end_datetime NULL,             (NULL = active; replaces is_active)
  planned_session_id NULL FK → dim_planned_session (NO ACTION),
                                 (renamed from parent_session_id)
  planned_session_name,          (name snapshot — survives template rename)
  program_run_id NULL,           (program context via the run)
  pre_feeling (1–5), post_feeling (1–5)
  [removed: is_active, program_id, program_name, parent_session_id,
   parent_session_name, exercise_order]

fact_session_exercise            (NEW — the tab layer)
  session_exercise_id PK, user_id,
  session_id FK → fact_session (NO ACTION),
  custom_exercise_id NULL,       (draft/free tab before an exercise is chosen)
  exercise_order int,            (replaces the fact_session.exercise_order blob)
  exercise_name,                 (snapshot)
  planned_exercise_id NULL,      (plain ref → dim_planned_session_exercise —
                                  the ghost-hint anchor, no DB FK)

fact_session_exercise_set        (renamed fact_session_set)
  session_exercise_set_id PK, user_id,          (renamed from session_set_id)
  session_exercise_id FK → fact_session_exercise (NO ACTION),
  custom_variation_id NULL,
  variation_name,                (snapshot — variation stays per set)
  set_number int,
  weight NULL,                   (NULL = bodyweight)
  reps,                          (int[] server / text client)
  notes,
  planned_set_id NULL,           (plain ref → dim_planned_session_exercise_set —
                                  the relocated parent_set_id, no DB FK)
  [removed: custom_exercise_id, exercise_name, superset_group_number,
   parent_set_id]

fact_program_run
  program_run_id PK, program_id, user_id,
  started_date, ended_date, is_current,
  target_sessions, target_weeks, end_date,
  progression_mode NULL,         (NEW: 'frequency' | 'order' — chosen at run
                                  start; backfilled from the old program column)

DROPPED TABLES: dim_exercise_variation_bridge
```

Session lifecycle with the new hierarchy:

```
start: INSERT fact_session (end_datetime NULL, planned_session_id)
       → materialize one fact_session_exercise per planned exercise
         (planned_exercise_id, sequence_order, exercise_name snapshot)
       → materialize one fact_session_exercise_set per planned set
         (planned_set_id, set_number; weight/reps/variation empty)
log:   keystrokes UPDATE the set row by its own id (unchanged behavior)
end:   end_datetime = now; DELETE untouched planned-origin sets (no weight/reps/
       variation/notes); keep user-added or touched rows, empty ones included
cancel: hard DELETE session + children (unchanged behavior)
restart: load session where end_datetime IS NULL; re-pair by planned_exercise_id
       / planned_set_id
```

---

## Migration plan (single breaking migration)

Order matters — backfill reads old columns before they're dropped.

1. **Create** `dim_planned_session_program`, `dim_planned_session_exercise`,
   `dim_planned_session_exercise_set`, `fact_session_exercise`,
   `fact_session_exercise_set` (new tables, FKs, `user_id` everywhere for RLS).
2. **Backfill planned side** (before touching the old dim table):
   - `dim_planned_session_exercise`: one row per distinct
     `(session_id, custom_exercise_id)` in `dim_planned_session_set`,
     `exercise_order = MIN(exercise_sequence_order)`, `exercise_name` copied.
   - `dim_planned_session_exercise_set`: copy every old set row, mapping to the
     new `planned_exercise_id`; keep `custom_variation_id`, `set_number`,
     targets, `variation_name`, `is_archived`.
   - `dim_planned_session_program`: one row per
     `dim_planned_session WHERE program_id IS NOT NULL`, copying
     `sequence_order` + `day_of_week`.
3. **Backfill fact side**:
   - `fact_session_exercise`: one row per session per distinct exercise, ordered
     by `fact_session.exercise_order` JSON where present (authoritative tab
     order), falling back to first appearance (`MIN(set_number)`); one extra row
     with `custom_exercise_id NULL` for sets with no exercise. `exercise_name`
     copied from the set rows; `planned_exercise_id` derived from
     `parent_set_id` → old dim set → new planned exercise.
   - `fact_session_exercise_set`: copy every `fact_session_set` row, mapping to
     `session_exercise_id`; `planned_set_id = parent_set_id`; drop
     `superset_group_number`.
   - `fact_session`: `planned_session_id = parent_session_id`,
     `planned_session_name = parent_session_name`,
     `created_datetime = created_date`,
     `end_datetime = created_date WHERE is_active = 0`
     (caveat: pre-migration sessions read 0 duration — no end time was ever
     recorded).
   - `fact_program_run.progression_mode`: backfill from the program each run
     references (`dim_program.progression_mode`), before dropping the program
     column.
4. **Drop** old columns and tables: bridge, old `dim_planned_session_set`,
   old `fact_session_set`, and the removed columns on `fact_session`,
   `dim_planned_session`, `dim_program` (after the backfill in step 3; the
   bridge has no downstream consumers).
5. **RLS** — owner ALL + coach SELECT policies on the five new tables (same two
   shapes as every other table), grants to anon/authenticated.
6. **Publication** — `alter publication powersync set table ...` replacing the
   old membership with the new table set (bridge and old set tables out, five
   new tables in).

## Sync contract checklist (every synced table, four places)

Per the `sync-contract` skill — missing any one of these means silent data
loss:

1. **Migration** — above.
2. **`lib/core/powersync/schema.dart`** — add `Table(...)` entries for the five
   new tables; update `fact_session`, `dim_planned_session`, `dim_program`,
   `fact_program_run` columns; delete the bridge and old set entries.
3. **`lib/core/powersync/database.dart`** — `_pkColumns`:
   `'dim_planned_session_program': 'planned_session_program_id'`,
   `'dim_planned_session_exercise': 'planned_exercise_id'`,
   `'dim_planned_session_exercise_set': 'planned_set_id'`,
   `'fact_session_exercise': 'session_exercise_id'`,
   `'fact_session_exercise_set': 'session_exercise_set_id'`; remove the bridge
   from `_compositeKeyTables`.
4. **Sync streams** — repo copy `powersync/sync-streams.yaml` **and** the
   PowerSync Dashboard (user step — the dashboard is the deployed truth). New
   stream lines, e.g.:

   ```yaml
   - SELECT *, session_exercise_id as id FROM fact_session_exercise WHERE user_id = auth.user_id()
   - SELECT *, session_exercise_set_id as id FROM fact_session_exercise_set WHERE user_id = auth.user_id()
   - SELECT *, planned_session_program_id as id FROM dim_planned_session_program WHERE user_id = auth.user_id()
   - SELECT *, planned_exercise_id as id FROM dim_planned_session_exercise WHERE user_id = auth.user_id()
   - SELECT *, planned_set_id as id FROM dim_planned_session_exercise_set WHERE user_id = auth.user_id()
   ```

   Remove the bridge stream. **Bump the app version** — sync rules attach to
   app versions, so the new streams only apply once the app ships with the new
   version number.

## Code impact map

| Layer | Change |
|---|---|
| `models/session.dart` | `plannedSessionId`/`plannedSessionName`, `createdDatetime`, `endDatetime` (active getter = `endDatetime == null`); drop `programId`, `programName`, `parentSessionId`, `parentSessionName`, `isActive`, `exerciseOrder` |
| `models/session_set.dart` | `SessionSet` → `SessionExerciseSet` (drop `exerciseId`, `exerciseName`); new `SessionExercise` model |
| `models/planned_session*.dart` | `PlannedSession` drops `programId`/`sequenceOrder`/`dayOfWeek`; new `PlannedSessionExercise`, `PlannedSessionExerciseSet`, `PlannedSessionProgram` |
| `models/program.dart` | drop `progressionMode`, `lengthWeeks`; add `updatedDate` |
| `models/program_run.dart` | add `progressionMode` |
| `models/exercise_detail.dart` | drop `variations` (bridge gone) |
| `session_repository.dart` | active = `end_datetime IS NULL`; insert/update/deletes through `fact_session_exercise` + `fact_session_exercise_set` (JOIN for session-level queries); `saveExerciseOrder` becomes column writes to `fact_session_exercise.exercise_order` |
| `planned_session_repository.dart` | exercise-level CRUD + join-table CRUD; reorder writes join `sequence_order` / exercise `exercise_order` |
| `program_repository.dart` | `createProgram` without progression/length; `fetchPlannedSessions` via join table; bump `program_updated_date` on updates |
| `program_run_repository.dart` | `startProgramRun` takes `progressionMode`; `getNextPlannedSession` reads mode from the run and day/sequence from the join table (fortnight via `week_offset` vs `started_date`) |
| `exercise_repository.dart` | delete bridge methods (`fetchBridges`, `addBridge`, …) |
| `session_viewmodel.dart` | two-level materialization (planned exercises → planned sets); exercise order via `fact_session_exercise.exercise_order`; restore re-pairs by `planned_exercise_id`/`planned_set_id`; active checks on `end_datetime` |
| `program_detail_viewmodel.dart` | day-of-week picker writes join rows; progression draft moves to the start-run flow |
| `session_detail_viewmodel.dart` | tabs from `fact_session_exercise` (order = `exercise_order`, editing persists back to it) |
| `logs_viewmodel.dart` | session/set queries on new hierarchy |
| `pr_engine.dart` / `pr_service.dart` | reads move to `fact_session_exercise_set` JOIN `fact_session_exercise` (exercise id now on the parent row); `(exercise, variation)` scoping unchanged |
| exercise screens | variation edit screen drops exercise assignment; picker shows all variations |
| `sample_data_service.dart` | bridge writes removed |
| tests | update all 22 + integration to the new tables |

## Phasing & verification

1. Migration up + deploy to Supabase.
2. User deploys updated sync streams in the PowerSync Dashboard (YAML above),
   app version bumped.
3. App code (schema.dart → database.dart → models → repos → VMs → UI).
4. `flutter analyze lib/` clean; `flutter test` green; on-device integration
   test (`flutter test integration_test/... -d <device>`) exercising real
   PowerSync triggers; in-app driver runbook (see planned-set-linkage memory)
   for start → log → end → restart → logs flows.
5. Follow-up cleanup migration to drop legacy tables only after the app ships
   (step 4's drops can also live here for safety).

## Open decisions to confirm

1. **Keep `planned_session_name` snapshot?** Recommended yes — template renames
   must not rewrite past logs. (User flagged `parent_session_name` as weird;
   the rename to `planned_session_name` + `planned_session_id` pair is the
   cleaned-up version, not the same column.)
2. **Cancel stays a hard delete** (no cancelled-session record, no
   `end_datetime` written) — matches today. Alternative: a status column.
3. **Legacy `end_datetime = created_date`** — pre-migration history shows 0
   duration. Acceptable? (There is no real end time in the data.)
4. **Join-table slots are program-level, mode is run-level** — the day/sequence
   assignment UI at run start writes join rows (shared by all runs of that
   program). Confirm that's the intent of "configured at the run level".
5. **Bridge fully dropped, no replacement** — variations become a flat library;
   the variation edit screen loses exercise assignment entirely. Confirm.
6. **Join-table rows hard-delete** (removing a session from a program) — they
   are never referenced by facts. Alternative: `is_archived`.
7. **Progression values renamed** 'sequential'/'calendar' → 'frequency'/'order'
   (user's language) — legacy runs backfill to the mapped value.
