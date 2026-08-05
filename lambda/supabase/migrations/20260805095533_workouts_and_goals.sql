-- Standalone workouts (a single planned session, no program) and structured
-- program goals (free-text OR exercise-specific targets).

create table public.dim_workout (
  workout_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  workout_name text not null,
  workout_notes text,
  is_active integer not null default 1,
  workout_created_date timestamptz not null default now()
);

create table public.dim_workout_set (
  workout_set_id text primary key,
  workout_id text not null references public.dim_workout (workout_id),
  user_id uuid not null references public.dim_user (user_id),
  custom_exercise_id text not null,
  custom_variation_id text,
  exercise_sequence_order integer not null,
  workout_set_number integer not null,
  target_weight numeric,
  target_reps text,
  target_duration_seconds text,
  target_notes text,
  exercise_name text,
  variation_name text,
  is_active integer not null default 1
);

create table public.dim_program_goal (
  program_goal_id text primary key,
  program_id text not null references public.dim_program (program_id),
  user_id uuid not null references public.dim_user (user_id),
  goal_text text,
  custom_exercise_id text,
  target_weight numeric,
  target_reps integer,
  goal_created_date timestamptz not null default now()
);

alter table public.dim_workout enable row level security;
alter table public.dim_workout_set enable row level security;
alter table public.dim_program_goal enable row level security;

create policy "dim_workout owner access"
  on public.dim_workout for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_workout_set owner access"
  on public.dim_workout_set for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_program_goal owner access"
  on public.dim_program_goal for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.dim_workout, public.dim_workout_set, public.dim_program_goal to anon, authenticated;

alter publication powersync add table public.dim_workout, public.dim_workout_set, public.dim_program_goal;
