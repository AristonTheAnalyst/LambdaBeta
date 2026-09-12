-- 2026-08-26: per-exercise PR journey view settings.
--
-- Stores only HIDDEN axes — presence of a row means the axis is hidden on
-- the exercise insights page. Default (no rows) = everything visible, which
-- is also the account-setup default. Strictly a view preference for the
-- insights page: nothing else (session viewer, PR modals, summary metrics)
-- reads this table.
--
-- axis_type 'reps'  → axis_value is a tracked rep count ("5", "12")
-- axis_type 'weight' → axis_value is a formatted weight ("72.5", "0")

create table public.dim_pr_view_setting (
  pr_view_setting_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  exercise_id text not null references public.dim_exercise (custom_exercise_id),
  axis_type text not null check (axis_type in ('reps', 'weight')),
  axis_value text not null,
  unique (user_id, exercise_id, axis_type, axis_value)
);

alter table public.dim_pr_view_setting enable row level security;
create policy "dim_pr_view_setting owner access"
  on public.dim_pr_view_setting for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_pr_view_setting coach access"
  on public.dim_pr_view_setting for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = dim_pr_view_setting.user_id));

alter publication powersync add table public.dim_pr_view_setting;

grant select, insert, update, delete on public.dim_pr_view_setting
  to anon, authenticated;
