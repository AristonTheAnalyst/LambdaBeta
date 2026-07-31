-- Personal-record snapshots. Each row is a self-contained PR achievement
-- (exercise, variation, weight, reps, type, date) copied at write time so it
-- survives the source set being edited or deleted. Normal deletes keep the
-- achievement; an explicit data-correction delete removes the record and a
-- targeted recompute promotes the next-best from remaining history.
create table if not exists public.fact_pr (
  pr_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  workout_set_id text, -- plain column, NO FK: snapshots must survive set deletion
  custom_exercise_id text not null references public.dim_exercise (custom_exercise_id),
  custom_variation_id text references public.dim_variation (custom_variation_id),
  weight numeric not null,
  reps integer not null,
  achieved_date timestamptz not null,
  pr_type text not null, -- 'absolute' | 'repMax' | 'weightClass'
  target_reps integer, -- repMax: the N in "N-rep max"
  target_weight numeric, -- weightClass: the weight
  is_active integer not null default 1
);

alter table public.fact_pr enable row level security;
create policy "fact_pr owner access"
  on public.fact_pr
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.fact_pr to anon, authenticated;
