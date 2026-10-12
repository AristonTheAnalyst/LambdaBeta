-- =============================================================================
-- Schema cleanup: drop fact_rest, fix defaults, dead columns, datatypes,
-- clunky names, and inconsistent soft-deletes. Also normalize RLS.
--
-- Decisions (per audit):
--   * fact_rest dropped — rest data isn't worth analyzing.
--   * is_archived defaults flipped to false (0 = active semantics).
--   * fact_session.deleted_locally / fact_session_set.deleted_locally /
--     fact_session_set.program_id dropped — never read or written.
--   * Feeling columns renamed: pre_workout_feeling -> pre_feeling,
--     user_workout_feeling -> post_feeling.
--   * fact_session_set.notes varchar -> text.
--   * fact_pr.is_propagated integer -> boolean; fact_pr.is_active dropped
--     (PRs hard-delete now — facts don't soft-delete).
--   * coaching_relationship.id dropped (sync stream computes the alias).
--   * dim_exercise_variation_bridge.deleted_locally -> is_archived (dims
--     soft-delete consistently).
--   * RLS: stale policy names renamed; coach SELECT access added to every
--     athlete-owned table for parity.
-- =============================================================================

-- ── 1. Drop fact_rest ────────────────────────────────────────────────────────
drop table if exists public.fact_rest cascade;

-- ── 2. is_archived defaults: true -> false (0 = active) ──────────────────────
alter table public.dim_exercise alter column is_archived set default false;
alter table public.dim_variation alter column is_archived set default false;
alter table public.dim_lesson alter column is_archived set default false;
alter table public.dim_program alter column is_archived set default false;
alter table public.dim_planned_session alter column is_archived set default false;
alter table public.dim_planned_session_set alter column is_archived set default false;

-- ── 3. Dead columns ──────────────────────────────────────────────────────────
alter table public.fact_session drop column if exists deleted_locally;
alter table public.fact_session_set drop column if exists deleted_locally;
alter table public.fact_session_set drop column if exists program_id;

-- ── 4. Feeling column renames ────────────────────────────────────────────────
alter table public.fact_session rename column pre_workout_feeling to pre_feeling;
alter table public.fact_session rename column user_workout_feeling to post_feeling;

-- ── 5. Datatype fixes ────────────────────────────────────────────────────────
alter table public.fact_session_set alter column notes type text;
alter table public.fact_pr alter column is_propagated type boolean using (is_propagated <> 0);

-- ── 6. Drop synthetic id on coaching_relationship ────────────────────────────
alter table public.coaching_relationship drop column if exists id;

-- ── 7. Bridge soft-delete naming ─────────────────────────────────────────────
alter table public.dim_exercise_variation_bridge rename column deleted_locally to is_archived;
alter table public.dim_exercise_variation_bridge alter column is_archived set default false;

-- ── 8. PRs hard-delete — drop is_active ──────────────────────────────────────
alter table public.fact_pr drop column if exists is_active;

-- ── 9. Publication: drop fact_rest ───────────────────────────────────────────
alter publication powersync set table
  public.dim_user, public.fact_session, public.dim_exercise, public.dim_variation,
  public.dim_exercise_variation_bridge, public.fact_bodyweight, public.fact_session_set,
  public.dim_program, public.fact_program_run, public.dim_lesson,
  public.fact_pr, public.dim_planned_session, public.dim_planned_session_set,
  public.fact_goal, public.coaching_relationship;

-- ── 10. RLS: rename stale policies ───────────────────────────────────────────
alter policy "fact_workout coach access" on public.fact_session rename to "fact_session coach access";
alter policy "fact_workout_set coach access" on public.fact_session_set rename to "fact_session_set coach access";
alter policy "fact_lesson coach access" on public.dim_lesson rename to "dim_lesson coach access";

-- ── 11. RLS: coach SELECT access on the tables missing it ────────────────────
do $$ begin create policy "dim_user coach access" on public.dim_user for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_user.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_exercise coach access" on public.dim_exercise for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_exercise.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_variation coach access" on public.dim_variation for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_variation.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_program coach access" on public.dim_program for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_program.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_planned_session coach access" on public.dim_planned_session for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_planned_session.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_planned_session_set coach access" on public.dim_planned_session_set for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_planned_session_set.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "fact_goal coach access" on public.fact_goal for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = fact_goal.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "fact_bodyweight coach access" on public.fact_bodyweight for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = fact_bodyweight.user_id)); exception when duplicate_object then null; end $$;
do $$ begin create policy "dim_exercise_variation_bridge coach access" on public.dim_exercise_variation_bridge for select to authenticated using (exists (select 1 from public.coaching_relationship cr where cr.coach_user_id = auth.uid() and cr.athlete_user_id = dim_exercise_variation_bridge.user_id)); exception when duplicate_object then null; end $$;
