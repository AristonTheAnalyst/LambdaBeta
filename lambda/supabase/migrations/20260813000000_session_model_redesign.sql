-- =============================================================================
-- Session model redesign.
--
-- Domain clarity:
--   * A PLANNED SESSION is a template (dimension) — exercises + target sets.
--   * A SESSION is a logged workout (fact) — a snapshot copy of a template.
--   * A PROGRAM is a group of planned sessions on a schedule (dimension).
--   * A PROGRAM RUN is a commitment to follow a program (fact).
--   * A GOAL is an independent target, optionally linked to a run (fact).
--
-- All dimension tables soft-delete via is_archived (1 = archived, 0 = active)
-- so historical fact rows never dangle. fact_session keeps is_active for its
-- "in progress" lifecycle.
--
-- Renames:
--   dim_workout         -> dim_planned_session
--   dim_workout_set     -> dim_planned_session_set
--   fact_workout        -> fact_session
--   fact_workout_set    -> fact_session_set
--   fact_program_goal   -> fact_goal
--   fact_lesson         -> dim_lesson
--
-- Dropped (dead legacy tables): dim_planned_workout, dim_planned_set
-- =============================================================================

-- ── 1. Drop FKs pointing at legacy tables ─────────────────────────────────────
alter table public.fact_workout
  drop constraint if exists fact_user_workout_planned_workout_id_fkey;
alter table public.fact_workout_set
  drop constraint if exists fact_workout_set_planned_set_id_fkey;

-- ── 2. Drop legacy tables ─────────────────────────────────────────────────────
drop table if exists public.dim_planned_set cascade;
drop table if exists public.dim_planned_workout cascade;

-- ── 3. Rename tables (FKs follow automatically) ───────────────────────────────
alter table public.dim_workout rename to dim_planned_session;
alter table public.dim_workout_set rename to dim_planned_session_set;
alter table public.fact_workout rename to fact_session;
alter table public.fact_workout_set rename to fact_session_set;
alter table public.fact_program_goal rename to fact_goal;
alter table public.fact_lesson rename to dim_lesson;

-- ── 4. Column renames ─────────────────────────────────────────────────────────

-- dim_planned_session (was dim_workout)
alter table public.dim_planned_session rename column workout_id to session_id;
alter table public.dim_planned_session rename column workout_name to name;
alter table public.dim_planned_session rename column workout_notes to notes;
alter table public.dim_planned_session rename column workout_created_date to created_date;

-- dim_planned_session_set (was dim_workout_set)
alter table public.dim_planned_session_set rename column workout_set_id to set_id;
alter table public.dim_planned_session_set rename column workout_id to session_id;
alter table public.dim_planned_session_set rename column workout_set_number to set_number;

-- fact_session (was fact_workout)
alter table public.fact_session rename column user_workout_id to session_id;
alter table public.fact_session rename column user_pre_workout_notes to pre_notes;
alter table public.fact_session rename column user_post_workout_notes to post_notes;
alter table public.fact_session rename column user_workout_created_date to created_date;
alter table public.fact_session rename column planned_workout_id to parent_session_id;
alter table public.fact_session rename column planned_workout_name to parent_session_name;

-- fact_session_set (was fact_workout_set)
alter table public.fact_session_set rename column workout_set_id to session_set_id;
alter table public.fact_session_set rename column user_workout_id to session_id;
alter table public.fact_session_set rename column workout_set_number to set_number;
alter table public.fact_session_set rename column workout_set_weight to weight;
alter table public.fact_session_set rename column workout_set_reps to reps;
alter table public.fact_session_set rename column workout_set_duration_seconds to duration_seconds;
alter table public.fact_session_set rename column workout_set_notes to notes;
alter table public.fact_session_set rename column planned_set_id to parent_set_id;

-- fact_goal (was fact_program_goal)
alter table public.fact_goal rename column program_goal_id to goal_id;

-- ── 5. Soft-delete flag standardization on dims ───────────────────────────────
-- dims: is_active -> is_archived (1 = archived). fact_session keeps is_active
-- for its in-progress lifecycle.

alter table public.dim_exercise rename column is_active to is_archived;
alter table public.dim_variation rename column is_active to is_archived;
alter table public.dim_lesson rename column is_active to is_archived;
alter table public.dim_program rename column is_active to is_archived;
alter table public.dim_planned_session rename column is_active to is_archived;
alter table public.dim_planned_session_set rename column is_active to is_archived;

-- ── 6. New columns ────────────────────────────────────────────────────────────
alter table public.fact_goal
  add column if not exists achieved_date timestamptz;

-- ── 7. New FKs ────────────────────────────────────────────────────────────────
-- fact_session.parent_session_id -> dim_planned_session. Dims are soft-deleted
-- only, so the parent always exists — NO ACTION.
alter table public.fact_session
  add constraint fact_session_parent_session_id_fkey
  foreign key (parent_session_id) references public.dim_planned_session (session_id);

-- ── 8. RLS policies for renamed tables ────────────────────────────────────────
-- Policy names reference the old table names; recreate them cleanly.

drop policy if exists "dim_workout owner access" on public.dim_planned_session;
create policy "dim_planned_session owner access"
  on public.dim_planned_session for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "dim_workout_set owner access" on public.dim_planned_session_set;
create policy "dim_planned_session_set owner access"
  on public.dim_planned_session_set for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "fact_workout owner access" on public.fact_session;
create policy "fact_session owner access"
  on public.fact_session for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "fact_workout_set owner access" on public.fact_session_set;
create policy "fact_session_set owner access"
  on public.fact_session_set for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "dim_program_goal owner access" on public.fact_goal;
create policy "fact_goal owner access"
  on public.fact_goal for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "fact_lesson owner access" on public.dim_lesson;
create policy "dim_lesson owner access"
  on public.dim_lesson for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 9. Publication — replace membership with the new table set ────────────────
alter publication powersync set table
  public.dim_user,
  public.fact_session,
  public.dim_exercise,
  public.dim_variation,
  public.dim_exercise_variation_bridge,
  public.fact_bodyweight,
  public.fact_session_set,
  public.dim_program,
  public.fact_program_run,
  public.dim_lesson,
  public.fact_rest,
  public.fact_pr,
  public.dim_planned_session,
  public.dim_planned_session_set,
  public.fact_goal,
  public.coaching_relationship;

-- ── 10. Grants ────────────────────────────────────────────────────────────────
grant select, insert, update, delete on
  public.dim_planned_session, public.dim_planned_session_set,
  public.fact_session, public.fact_session_set,
  public.fact_goal, public.dim_lesson
  to anon, authenticated;
