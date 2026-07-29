-- Logs every rest-timer run as its own event: planned duration vs. actual
-- duration (a rest can be stopped early, restarted, or completed naturally —
-- actual_seconds < planned_seconds captures a skip). Previously this only
-- existed as an in-memory list on the session screen, discarded at session
-- end, with no way to tell a completed rest from a skipped one.
create table if not exists public.fact_rest (
  rest_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  user_workout_id text not null references public.fact_workout (user_workout_id),
  custom_exercise_id text references public.dim_exercise (custom_exercise_id),
  planned_seconds integer not null,
  actual_seconds integer not null,
  rest_created_date timestamptz not null default now()
);

alter table public.fact_rest enable row level security;
create policy "fact_rest owner access"
  on public.fact_rest
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.fact_rest to anon, authenticated;
