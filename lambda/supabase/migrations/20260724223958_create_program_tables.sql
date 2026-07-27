-- Programs feature: user-authored workout plans, their planned workouts and
-- per-set targets, and the "current program" activation-span tracker.
--
-- Nothing in this hierarchy is ever hard-deleted (is_active soft-delete only)
-- because fact_user_workout/fact_workout_set rows can point back at these
-- rows indefinitely for adherence/performance/enjoyment analytics, even after
-- a user stops following a program.

-- Entity IDs throughout this app are client-generated UUID strings inserted
-- into `text` columns (confirmed via information_schema against every
-- existing table: custom_exercise_id, workout_set_id, etc. are all `text`,
-- not the native `uuid` type) — matched here for FK compatibility and
-- consistency. `user_id` is the one genuine `uuid` column everywhere,
-- referencing dim_user(user_id) — matching the existing FK convention
-- (dim_user itself references auth.users on delete cascade).

create table if not exists public.user_program (
  program_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  program_name text not null,
  program_description text,
  program_length_weeks integer,
  progression_mode text not null default 'sequential'
    check (progression_mode in ('sequential', 'calendar')),
  is_active boolean not null default true,
  program_created_date timestamptz not null default now()
);

create table if not exists public.program_planned_workout (
  planned_workout_id text primary key,
  program_id text not null references public.user_program (program_id),
  user_id uuid not null references public.dim_user (user_id),
  planned_workout_name text not null,
  planned_workout_notes text,
  sequence_order integer not null,
  day_of_week smallint check (day_of_week between 1 and 7),
  is_active boolean not null default true
);

create table if not exists public.program_planned_set (
  planned_set_id text primary key,
  planned_workout_id text not null
    references public.program_planned_workout (planned_workout_id),
  user_id uuid not null references public.dim_user (user_id),
  custom_exercise_id text not null references public.user_custom_exercise (custom_exercise_id),
  custom_variation_id text references public.user_custom_variation (custom_variation_id),
  exercise_sequence_order integer not null,
  planned_set_number integer not null,
  target_weight numeric,
  target_reps integer[],
  target_duration_seconds integer[],
  target_notes text,
  is_active boolean not null default true
);

create table if not exists public.user_program_run (
  program_run_id text primary key,
  program_id text not null references public.user_program (program_id),
  user_id uuid not null references public.dim_user (user_id),
  started_date timestamptz not null default now(),
  ended_date timestamptz,
  is_current boolean not null default true
);

-- Exactly one current run per user at a time.
create unique index if not exists user_program_run_one_current
  on public.user_program_run (user_id)
  where is_current;

-- RLS: owner-only access, same shape on all 4 tables. Each table carries its
-- own user_id (matching the user_custom_exercise_variation_bridge pattern)
-- so no join is needed in the policy.

alter table public.user_program enable row level security;
create policy "user_program owner access"
  on public.user_program
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table public.program_planned_workout enable row level security;
create policy "program_planned_workout owner access"
  on public.program_planned_workout
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table public.program_planned_set enable row level security;
create policy "program_planned_set owner access"
  on public.program_planned_set
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table public.user_program_run enable row level security;
create policy "user_program_run owner access"
  on public.user_program_run
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Matches the existing (dashboard-created) tables' grant shape in this
-- project — anon + authenticated both get table-level privileges, with RLS
-- as the actual gatekeeper (anon never has a matching auth.uid()).
grant select, insert, update, delete on public.user_program to anon, authenticated;
grant select, insert, update, delete on public.program_planned_workout to anon, authenticated;
grant select, insert, update, delete on public.program_planned_set to anon, authenticated;
grant select, insert, update, delete on public.user_program_run to anon, authenticated;
