-- Coaching groundwork: a relationship table so a coach can read an athlete's
-- training data. This is schema + access only — no coaching UI yet. The sync
-- config (streams) uses this table to push the athlete's rows to the coach.
-- At most one row per (coach, athlete) pair.

create table if not exists public.coaching_relationship (
  coach_user_id   uuid not null references public.dim_user (user_id),
  athlete_user_id uuid not null references public.dim_user (user_id),
  created_date    timestamptz not null default now(),
  primary key (coach_user_id, athlete_user_id)
);

alter table public.coaching_relationship enable row level security;

-- Coach or athlete can read the relationship; only the coach can create/delete.
create policy "coaching_relationship read"
  on public.coaching_relationship
  for select
  to authenticated
  using (coach_user_id = auth.uid() or athlete_user_id = auth.uid());

create policy "coaching_relationship coach manage"
  on public.coaching_relationship
  for all
  to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid());

grant select, insert, update, delete on public.coaching_relationship to anon, authenticated;

-- Let the coach read the athlete's rows too (additive policies — the existing
-- owner policies stay; RLS permissive policies combine with OR). Reads for the
-- coach go through PowerSync local sync; these also make direct REST reads work.
create policy "fact_pr coach access"
  on public.fact_pr
  for select
  to authenticated
  using (exists (
    select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_pr.user_id
  ));

create policy "fact_workout coach access"
  on public.fact_workout
  for select
  to authenticated
  using (exists (
    select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_workout.user_id
  ));

create policy "fact_workout_set coach access"
  on public.fact_workout_set
  for select
  to authenticated
  using (exists (
    select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_workout_set.user_id
  ));

create policy "fact_lesson coach access"
  on public.fact_lesson
  for select
  to authenticated
  using (exists (
    select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_lesson.user_id
  ));

-- Stream the relationship table to clients too.
alter publication powersync add table public.coaching_relationship;
