-- Backfilled 2026-09-30: this migration had been applied to the cloud database
-- but its local file was never committed. Reconstructed verbatim from
-- supabase_migrations.schema_migrations.statements.
--
-- Historical note: this file predates the session-model redesign, so it still
-- references the pre-rename table names (fact_workout, dim_planned_workout,
-- fact_lesson, ...). It is kept as applied — it is never re-run.

-- =============================================================================
-- Schema hardening: auth trigger, RLS, and publication.
-- Everything here is idempotent — safe to re-run.
-- =============================================================================

-- 1. on_auth_user_created trigger ---------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.dim_user (user_id, user_date_created, onboarded)
  values (new.id, now(), false)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill any auth.users missing their dim_user row
insert into public.dim_user (user_id, user_date_created, onboarded)
select id, created_at, false from auth.users
where id not in (select user_id from public.dim_user);

-- 2. RLS for every user-scoped table ------------------------------------------
--    All policies are wrapped in DO blocks so they're idempotent.

alter table public.dim_user enable row level security;
do $$ begin create policy "dim_user owner access" on public.dim_user for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_workout enable row level security;
do $$ begin create policy "fact_workout owner access" on public.fact_workout for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_exercise enable row level security;
do $$ begin create policy "dim_exercise owner access" on public.dim_exercise for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_variation enable row level security;
do $$ begin create policy "dim_variation owner access" on public.dim_variation for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_exercise_variation_bridge enable row level security;
do $$ begin create policy "dim_exercise_variation_bridge owner access" on public.dim_exercise_variation_bridge for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_bodyweight enable row level security;
do $$ begin create policy "fact_bodyweight owner access" on public.fact_bodyweight for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_workout_set enable row level security;
do $$ begin create policy "fact_workout_set owner access" on public.fact_workout_set for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_program enable row level security;
do $$ begin create policy "dim_program owner access" on public.dim_program for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_planned_workout enable row level security;
do $$ begin create policy "dim_planned_workout owner access" on public.dim_planned_workout for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_planned_set enable row level security;
do $$ begin create policy "dim_planned_set owner access" on public.dim_planned_set for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_program_run enable row level security;
do $$ begin create policy "fact_program_run owner access" on public.fact_program_run for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_lesson enable row level security;
do $$ begin create policy "fact_lesson owner access" on public.fact_lesson for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_rest enable row level security;
do $$ begin create policy "fact_rest owner access" on public.fact_rest for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.fact_pr enable row level security;
do $$ begin create policy "fact_pr owner access" on public.fact_pr for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_workout enable row level security;
do $$ begin create policy "dim_workout owner access" on public.dim_workout for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_workout_set enable row level security;
do $$ begin create policy "dim_workout_set owner access" on public.dim_workout_set for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

alter table public.dim_program_goal enable row level security;
do $$ begin create policy "dim_program_goal owner access" on public.dim_program_goal for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid()); exception when duplicate_object then null; end $$;

-- coaching_relationship has two user_id columns — a user is either coach or
-- athlete.  Both sides need read access to the rows that involve them.
alter table public.coaching_relationship enable row level security;
do $$ begin create policy "coaching_relationship coach access" on public.coaching_relationship for all to authenticated using (coach_user_id = auth.uid()) with check (coach_user_id = auth.uid()); exception when duplicate_object then null; end $$;
do $$ begin create policy "coaching_relationship athlete access" on public.coaching_relationship for all to authenticated using (athlete_user_id = auth.uid()) with check (athlete_user_id = auth.uid()); exception when duplicate_object then null; end $$;

-- 3. Publication — ensure every synced table is in the powersync publication --
do $$ begin alter publication powersync add table public.dim_user; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_workout; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_exercise; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_variation; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_exercise_variation_bridge; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_bodyweight; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_workout_set; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_program; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_planned_workout; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_planned_set; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_program_run; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_lesson; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_rest; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.fact_pr; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_workout; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_workout_set; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.dim_program_goal; exception when duplicate_object then null; end $$;
do $$ begin alter publication powersync add table public.coaching_relationship; exception when duplicate_object then null; end $$;
