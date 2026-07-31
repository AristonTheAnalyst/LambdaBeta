-- Per-exercise pinnable cue/notes ("lessons"). Previously pure in-memory UI
-- state on the session screen, reset every workout — this makes them real,
-- durable, accumulating log entries (many per exercise over time, like
-- fact_bodyweight), so they persist across every future session for the
-- exercise rather than disappearing at session end.
create table if not exists public.fact_lesson (
  lesson_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  custom_exercise_id text not null references public.dim_exercise (custom_exercise_id),
  lesson_text text not null,
  pinned boolean not null default false,
  is_active boolean not null default true,
  lesson_created_date timestamptz not null default now()
);

alter table public.fact_lesson enable row level security;
create policy "fact_lesson owner access"
  on public.fact_lesson
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.fact_lesson to anon, authenticated;
