# Schema Redesign Plan — Sessions, Programs, Runs, Goals

## Design Principles

1. **Dimensions are reference data** — never hard-deleted, soft-deleted via `is_archived` (1 = archived, 0 = active).
2. **Facts are events** — logged history, immutable (mostly), use `is_active` only for "in progress" session state.
3. **Planned vs logged sessions are separate tables** — a logged session is a snapshot copy of a template, not a state transition. They differ in columns, lifecycle, and operations.
4. **Names must be unambiguous** — "workout" is banned; it's either `planned_session` (template) or `session` (logged).

## Target Schema

```
DIMENSIONS (reference data — soft delete via is_archived)
──────────────────────────────────────────────────────────

dim_user                        (no is_archived — auth lifecycle)
  user_id PK, user_name, user_lastname, user_date_created,
  user_date_of_birth, user_gender, user_height_cm, onboarded, user_weight_kg

dim_exercise
  custom_exercise_id PK, user_id FK→dim_user, exercise_name,
  is_archived  (renamed from is_active)

dim_variation
  custom_variation_id PK, user_id FK→dim_user, variation_name,
  is_archived  (renamed from is_active)

dim_exercise_variation_bridge   (unchanged)
  custom_exercise_id + custom_variation_id PK, user_id, deleted_locally

dim_lesson                      (renamed from fact_lesson — it's knowledge,
  lesson_id PK                  not an event)
  user_id, custom_exercise_id, lesson_text, pinned,
  is_archived  (renamed from is_active), lesson_created_date

dim_program
  program_id PK, user_id, program_name, program_description,
  program_length_weeks, progression_mode,
  is_archived  (renamed from is_active — no longer "current program",
               that's what runs are for)
  program_created_date

dim_planned_session             (renamed from dim_workout — a session template)
  session_id PK                 (renamed from workout_id)
  user_id, program_id FK→dim_program NULLABLE (NULL = standalone),
  name                          (renamed from workout_name)
  notes                         (renamed from workout_notes)
  sequence_order, day_of_week,
  is_archived                   (renamed from is_active)
  created_date                  (renamed from workout_created_date)

dim_planned_session_set         (renamed from dim_workout_set)
  set_id PK                     (renamed from workout_set_id)
  session_id FK→dim_planned_session  (renamed from workout_id)
  user_id, custom_exercise_id, custom_variation_id,
  exercise_sequence_order,
  set_number                    (renamed from workout_set_number)
  target_weight, target_reps, target_duration_seconds, target_notes,
  exercise_name, variation_name,
  is_archived                   (renamed from is_active)

DROPPED: dim_planned_workout, dim_planned_set (dead legacy tables)

FACTS (events)
──────────────

fact_session                    (renamed from fact_workout — a logged session)
  session_id PK                 (renamed from user_workout_id)
  user_id,
  pre_notes                     (renamed from user_pre_workout_notes)
  post_notes                    (renamed from user_post_workout_notes)
  created_date                  (renamed from user_workout_created_date)
  is_active                     (1 = session in progress, 0 = completed)
  deleted_locally               (sync tombstone)
  program_id FK→dim_program     (denormalized + FK)
  program_run_id FK→fact_program_run
  parent_session_id             (renamed from planned_workout_id,
                                 FK→dim_planned_session — "which template")
  pre_workout_feeling, user_workout_feeling
  exercise_order
  parent_session_name           (renamed from planned_workout_name, snapshot)
  program_name                  (snapshot)

fact_session_set                (renamed from fact_workout_set)
  session_set_id PK             (renamed from workout_set_id)
  session_id FK→fact_session    (renamed from user_workout_id)
  user_id, custom_exercise_id, custom_variation_id,
  set_number                    (renamed from workout_set_number)
  weight                        (renamed from workout_set_weight)
  reps                          (renamed from workout_set_reps)
  duration_seconds              (renamed from workout_set_duration_seconds)
  notes                         (renamed from workout_set_notes)
  deleted_locally, program_id, superset_group_number,
  parent_set_id                 (renamed from planned_set_id, no FK — template
                                 sets are soft-deleted but this is a snapshot ref)
  exercise_name, variation_name (snapshots)

fact_program_run                (unchanged — already correct)
  program_run_id PK, program_id FK→dim_program, user_id,
  started_date, ended_date (NULL = running), is_current,
  target_sessions, target_weeks, end_date
  (partial unique index on user_id WHERE is_current stays)

fact_goal                       (renamed from fact_program_goal — independent)
  goal_id PK                    (renamed from program_goal_id)
  user_id,
  goal_text, custom_exercise_id (nullable),
  target_weight, target_reps,
  program_run_id FK→fact_program_run NULLABLE (optional link to a run)
  achieved_date                 (NEW — NULL = still chasing)
  goal_created_date

fact_pr                         (unchanged)
  ... is_propagated (keep — distinguishes explicit PRs from
      rep-max-curve-propagated ones)

fact_rest                       (unchanged)
fact_bodyweight                 (unchanged)
coaching_relationship           (unchanged)
app_config                      (unchanged)
```

## FK Policy

| FK | On delete | Why |
|---|---|---|
| all `user_id` → dim_user | CASCADE | account deletion wipes everything |
| fact_session.parent_session_id → dim_planned_session | NO ACTION | dims are soft-deleted only; the parent always exists |
| fact_session.program_id → dim_program | NO ACTION | same — soft delete |
| fact_program_run.program_id → dim_program | NO ACTION | same |
| dim_planned_session_set.session_id → dim_planned_session | CASCADE | hard delete of template cascades its sets (dims CAN be hard-deleted by account deletion flow only) |
| fact_goal.program_run_id → fact_program_run | CASCADE | delete run → its goals go with it (run-scoped goals are part of the run) |

## Migration Steps (single migration file)

1. Rename tables: `dim_workout`→`dim_planned_session`, `dim_workout_set`→`dim_planned_session_set`, `fact_workout`→`fact_session`, `fact_workout_set`→`fact_session_set`, `fact_program_goal`→`fact_goal`, `fact_lesson`→`dim_lesson`
2. Drop legacy: `dim_planned_set`, `dim_planned_workout` (after re-pointing the FKs from fact_session/fact_session_set to the new tables or dropping those FK columns)
3. Column renames (per schema above)
4. `is_active`→`is_archived` on: dim_exercise, dim_variation, dim_lesson, dim_program, dim_planned_session, dim_planned_session_set
5. Add `fact_goal.achieved_date`
6. Update RLS policies + grants + publication for renamed tables
7. Drop FKs to legacy tables; add new FKs per the FK policy

## PowerSync Config Changes

- `powersync/sync-streams.yaml`: replace stream queries with new table names (planned_session aliases PK as id, etc.)
- `lib/core/powersync/schema.dart`: rename tables + columns to match
- Local DB rebuilds automatically on schema mismatch (PowerSync detects and recreates); dev data is on the server so it re-downloads

## App Code Refactor (follows schema migration)

### Models (`lib/data/models/`)
- `workout_plan.dart` → `planned_session.dart` (class `PlannedSession`)
- `workout_plan_set.dart` → `planned_session_set.dart` (class `PlannedSessionSet`)
- `workout.dart` → `session.dart` (class `Session`)
- `workout_set.dart` → `session_set.dart` (class `SessionSet`)
- `program_goal.dart` → `goal.dart` (class `Goal`)
- `planned_workout.dart` / `planned_set.dart` → **deleted** (legacy models)

### Repositories (`lib/data/repositories/`)
- `workout_plan_repository.dart` → `planned_session_repository.dart`
- `workout_repository.dart` → `session_repository.dart`
- `program_repository.dart` → shrinks to program CRUD only (all workout methods gone)
- `lesson_repository.dart` → unchanged (table renamed)
- new `goal_repository.dart` (standalone + run-linked goals)

### ViewModels / Screens
- `SessionViewModel`: single source of truth — reads planned sessions from `dim_planned_session`
- `ProgramDetailViewModel`: uses `PlannedSessionRepository` + `GoalRepository`
- All `is_active` filters on dims → `is_archived = 0`
- Remove all legacy fallback code paths (try unified / try legacy)
- `WorkoutDetailViewModel` (logs screen) → `SessionDetailViewModel` naming follows

### Dev tooling
- Dev screen "rebuild local DB" button already exists — useful after the migration lands

## Verification

1. Apply migration → check `list_tables` shows new names, no legacy tables
2. Update sync streams + schema.dart + app code
3. Fresh app install: create program → create planned session → add sets → start a run → log a session from it
4. Check: session appears in history, program shows correct progress, goals link to run, archived exercise disappears from picker but history intact
5. Duplicate/delete/reorder planned sessions — verify no orphan rows
