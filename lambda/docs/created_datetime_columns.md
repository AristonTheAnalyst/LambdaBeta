# Created-Datetime Columns — Plan of Record

2026-08-26. Adds a creation timestamp to every table where it earns its keep,
and deliberately skips the rest. Full audit below.

## Convention

New columns are named `created_datetime` (matching `fact_session`). Existing
creation columns keep their legacy names — no renames, churn without value:

`dim_user.user_date_created`, `dim_lesson.lesson_created_date`,
`dim_program.program_created_date`, `dim_planned_session.created_date`,
`fact_session.created_datetime`, `fact_program_run.started_date`,
`fact_goal.goal_created_date`, `fact_bodyweight.created_date`,
`coaching_relationship.created_date`, `upload_failures.created_at` (local).

## Audit result

| Table | Action | Why |
|---|---|---|
| `dim_exercise` | **ADD** | Library ordering for never-used items (usage recency is null for them); "added X ago"; creation date survives archive→reactivate cycles |
| `dim_variation` | **ADD** | Same as exercises; also the flat-library picker's fallback ordering |
| `dim_user` | covered | `user_date_created` via auth trigger |
| `dim_lesson` | covered | `lesson_created_date` |
| `dim_program` | covered | `program_created_date` (+ `program_updated_date`) |
| `dim_planned_session` | covered | `created_date` |
| `dim_planned_session_program` | **skip** | Pure link row; nothing displays link-creation time; slots are the content |
| `dim_planned_session_exercise` | **skip** | Group creation ≈ template creation — `dim_planned_session.created_date` already answers "when did I plan this" |
| `dim_planned_session_exercise_set` | **skip** | Per-target-row time is noise; `set_number`/`exercise_order` order the rows |
| `fact_session` | covered | `created_datetime` (v2) |
| `fact_session_exercise` | **skip** | Created at materialization/add — same moment as the parent session; `exercise_order` orders tabs |
| `fact_session_exercise_set` | **skip** | Same moment as the parent session; `set_number` orders rows. (An intra-session wall-clock `logged_at` for rest analytics is a *different* column and a separate feature decision — AVG REST is in-memory today) |
| `fact_program_run` | covered | `started_date` = creation |
| `fact_goal` | covered | `goal_created_date` |
| `fact_bodyweight` | covered | `created_date` (log date) + `user_weight_date` (measurement date) |
| `coaching_relationship` | covered | `created_date` |
| `app_config` | skip | Ops config; `updated_at` suffices — nothing reads a creation time |

## Migration

```sql
-- 20260826xxxxxx_add_created_datetime_to_exercise_variation.sql

alter table public.dim_exercise
  add column created_datetime timestamptz not null default now();
alter table public.dim_variation
  add column created_datetime timestamptz not null default now();

-- Caveat: no historical creation data exists, so existing rows share the
-- migration timestamp. Only new rows get real values. Accepted — ordering
-- only matters going forward.
```

Publication / RLS / grants: **no changes** (column-level, `SELECT *` covers it).

## Code

1. **Client schema** (`lib/core/powersync/schema.dart`): add
   `Column.text('created_datetime')` to `dim_exercise` and `dim_variation`.
2. **Models** (`custom_exercise.dart`, `custom_variation.dart`): add
   `createdDatetime` (defensive parse — null/epoch fallback for any rows
   synced before the column landed).
3. **Usage** (exercise library, `exercise_viewmodel.dart`):
   - `sortedExercises`/`sortedVariations`: usage-recency first, then
     `createdDatetime` desc, then name — new items stop sinking to name order.
   - Optional "added X ago" label on detail pages (reuse the
     `ExerciseUsage.lastUsedLabel` pattern).
   - Reactivation keeps the original timestamp (archive never resets it).
4. **Streams**: no YAML change; no version bump strictly required (SELECT *
   already ships the column once the client schema knows it). Bump + redeploy
   only if the already-pending v2 streams haven't been deployed yet.

## Verify

`flutter analyze` + `flutter test` green; on-device: create an exercise
offline → force sync → confirm `created_datetime` survives the round-trip
via `ps_data__dim_exercise` in the local DB.
