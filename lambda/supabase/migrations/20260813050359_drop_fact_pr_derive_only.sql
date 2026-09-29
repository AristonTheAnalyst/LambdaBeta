-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.

-- PRs are now derived client-side from fact_session_set on every read.
-- fact_pr (and its dedup machinery) is dropped — no more cache invalidation.
drop trigger if exists fact_pr_dedup_trigger on public.fact_pr;
drop function if exists public.fact_pr_dedup();
drop table if exists public.fact_pr cascade;
alter publication powersync set table
  public.dim_user, public.fact_session, public.dim_exercise, public.dim_variation,
  public.dim_exercise_variation_bridge, public.fact_bodyweight, public.fact_session_set,
  public.dim_program, public.fact_program_run, public.dim_lesson,
  public.dim_planned_session, public.dim_planned_session_set,
  public.fact_goal, public.coaching_relationship;
