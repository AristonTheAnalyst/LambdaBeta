-- Replaced 2026-09-30: this file previously held the contents of
-- 20260806034430_schema_hardening_auth_rls_publication instead of its own
-- migration — a leftover from when the history was applied by hand and two
-- migrations were consolidated into one file. The content below is the SQL
-- that was actually applied to the cloud as version 20260806024152,
-- reconstructed from supabase_migrations.schema_migrations.statements.

-- =============================================================================
-- Schema hardening: auth trigger, RLS, and safe NOT NULL constraints.
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

-- 2. RLS for every user-scoped table missing it ---------------------------------
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

-- 3. Publication (idempotent) ---------------------------------------------------
do $$ begin alter publication powersync add table public.dim_user; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.fact_workout; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.dim_exercise; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.dim_variation; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.dim_exercise_variation_bridge; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.fact_bodyweight; exception when duplicate_object then null; end $$;

do $$ begin alter publication powersync add table public.fact_workout_set; exception when duplicate_object then null; end $$;
