-- =============================================================================
-- Schema redesign v2 (2026-08-24). Plan of record: docs/schema_redesign_v2.md
--
-- One-shot breaking migration (single-user app):
--   * fact_session_exercise inserted between fact_session and its sets;
--     fact_session_set becomes fact_session_exercise_set.
--   * dim_planned_session_set splits into dim_planned_session_exercise +
--     dim_planned_session_exercise_set.
--   * dim_planned_session_program (M2M join) replaces
--     dim_planned_session.program_id / sequence_order / day_of_week.
--   * fact_session: is_active -> end_datetime, created_date -> created_datetime,
--     parent_session_id -> planned_session_id, program attribution dropped,
--     exercise_order JSON blob dropped (replaced by
--     fact_session_exercise.exercise_order).
--   * Progression mode moves from dim_program to fact_program_run
--     ('sequential' -> 'order', 'calendar' -> 'frequency'). Runs are what we
--     analyze; the program no longer decides how it is run.
--   * dim_exercise_variation_bridge dropped — variations are a flat library.
--   * dim_program loses program_length_weeks, gains program_updated_date.
--   * fact_session_set loses superset_group_number, custom_exercise_id and
--     exercise_name (now one level up); parent_set_id becomes planned_set_id
--     (same value — it WAS the planned set id; the new name matches the PK of
--     the table it points at).
--
-- Backfill order matters: the dim side goes first because planned_set_id
-- values are REUSED verbatim, so every historical parent_set_id keeps
-- pointing at the same template row through the rename.
--
-- Client/app updates must land with this migration: powersync/sync-streams.yaml
-- (+ PowerSync Dashboard deploy, app version bump), lib/core/powersync/schema.dart,
-- lib/core/powersync/database.dart — see docs/schema_redesign_v2.md.
-- =============================================================================

-- ── 1. New tables ─────────────────────────────────────────────────────────────

create table public.dim_planned_session_exercise (
  planned_exercise_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  planned_session_id text not null references public.dim_planned_session (session_id),
  custom_exercise_id text references public.dim_exercise (custom_exercise_id),
  exercise_order integer not null,
  exercise_name text,
  is_archived boolean not null default false
);

create table public.dim_planned_session_exercise_set (
  planned_set_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  planned_exercise_id text not null references public.dim_planned_session_exercise (planned_exercise_id),
  custom_variation_id text references public.dim_variation (custom_variation_id),
  set_number integer not null,
  target_weight text,
  target_reps text,
  target_notes text,
  variation_name text,
  is_archived boolean not null default false
);

create table public.dim_planned_session_program (
  planned_session_program_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  program_id text not null references public.dim_program (program_id),
  planned_session_id text not null references public.dim_planned_session (session_id),
  sequence_order integer,
  day_of_week smallint check (day_of_week between 1 and 7),
  week_offset smallint check (week_offset in (0, 1)),
  unique (program_id, planned_session_id)
);

create table public.fact_session_exercise (
  session_exercise_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  session_id text not null references public.fact_session (session_id),
  custom_exercise_id text,
  exercise_order integer not null,
  exercise_name text,
  planned_exercise_id text
);
create index fact_session_exercise_session_idx
  on public.fact_session_exercise (session_id);

create table public.fact_session_exercise_set (
  session_exercise_set_id text primary key,
  user_id uuid not null references public.dim_user (user_id),
  session_exercise_id text not null references public.fact_session_exercise (session_exercise_id),
  custom_variation_id text,
  variation_name text,
  set_number integer not null,
  weight numeric,
  reps integer[],
  notes text,
  planned_set_id text
);
create index fact_session_exercise_set_exercise_idx
  on public.fact_session_exercise_set (session_exercise_id);

-- ── 2. Dim-side backfill ──────────────────────────────────────────────────────

-- One planned-exercise row per (planned session, exercise). Group is archived
-- once every one of its sets is archived (bool_and) — one archived set must
-- not hide a group that still has live rows.
insert into public.dim_planned_session_exercise
  (planned_exercise_id, user_id, planned_session_id, custom_exercise_id,
   exercise_order, exercise_name, is_archived)
select
  gen_random_uuid()::text,
  d.user_id,
  d.session_id,
  d.custom_exercise_id,
  min(d.exercise_sequence_order),
  max(d.exercise_name),
  bool_and(d.is_archived)
from public.dim_planned_session_set d
group by d.user_id, d.session_id, d.custom_exercise_id;

-- planned_set_id is REUSED verbatim — historical fact_session_set.parent_set_id
-- values keep pointing at the same template rows after the rename.
insert into public.dim_planned_session_exercise_set
  (planned_set_id, user_id, planned_exercise_id, custom_variation_id,
   set_number, target_weight, target_reps, target_notes, variation_name,
   is_archived)
select
  d.set_id,
  d.user_id,
  pe.planned_exercise_id,
  d.custom_variation_id,
  d.set_number,
  d.target_weight,
  d.target_reps,
  d.target_notes,
  d.variation_name,
  d.is_archived
from public.dim_planned_session_set d
join public.dim_planned_session_exercise pe
  on pe.planned_session_id = d.session_id
 and pe.custom_exercise_id = d.custom_exercise_id;

-- Program membership + schedule slots move to the join table.
insert into public.dim_planned_session_program
  (planned_session_program_id, user_id, program_id, planned_session_id,
   sequence_order, day_of_week)
select
  gen_random_uuid()::text,
  d.user_id,
  d.program_id,
  d.session_id,
  d.sequence_order,
  d.day_of_week
from public.dim_planned_session d
where d.program_id is not null;

-- ── 3. fact_session column reshuffle ──────────────────────────────────────────

alter table public.fact_session
  add column planned_session_id text,
  add column planned_session_name text,
  add column created_datetime timestamptz,
  add column end_datetime timestamptz;

update public.fact_session set
  planned_session_id = parent_session_id,
  planned_session_name = parent_session_name,
  created_datetime = created_date,
  -- Legacy completed sessions never recorded an end time (duration columns
  -- were dropped 2026-08-14) — created_date is the best available stand-in;
  -- their duration reads 0. Active sessions stay NULL = active.
  end_datetime = case when not is_active then created_date else null end;

alter table public.fact_session
  add constraint fact_session_planned_session_id_fkey
    foreign key (planned_session_id) references public.dim_planned_session (session_id);

alter table public.fact_session
  alter column created_datetime set default now(),
  alter column created_datetime set not null,
  drop column is_active,
  drop column program_id,
  drop column program_name,
  drop column parent_session_id,
  drop column parent_session_name,
  drop column created_date;
-- exercise_order drops AFTER the fact-side backfill (step 4 reads it).

-- ── 4. Fact-side backfill ─────────────────────────────────────────────────────

-- exercise_order JSON blob: [{"id":1,"type":"single|superset","exerciseIds":[...]},...].
-- Flatten slots in order as the authoritative tab order; fall back to first
-- appearance in set rows for sessions without a blob (or ids missing from it).
-- The blob may contain rows written by older app versions — tolerate bad JSON.
create or replace function public._lambda_safe_jsonb(t text)
returns jsonb language plpgsql immutable as $$
begin
  return t::jsonb;
exception when others then
  return null;
end $$;

with slots as (
  select
    f.session_id,
    slot.ord as slot_pos,
    eid.ord as id_pos,
    eid.eid as exercise_id
  from public.fact_session f
  cross join lateral jsonb_array_elements(public._lambda_safe_jsonb(f.exercise_order))
    with ordinality as slot(sl, ord)
  cross join lateral jsonb_array_elements_text(slot.sl -> 'exerciseIds')
    with ordinality as eid(eid, ord)
),
ordered_ids as (
  select
    session_id,
    exercise_id,
    min(slot_pos * 1000 + id_pos) as pos
  from slots
  group by session_id, exercise_id
),
groups as (
  select
    fss.session_id,
    fss.custom_exercise_id,
    max(fss.exercise_name) as exercise_name,
    min(fss.set_number) as first_set_number,
    row_number() over (
      partition by fss.session_id
      order by min(fss.set_number)
    ) as base_rank
  from public.fact_session_set fss
  group by fss.session_id, fss.custom_exercise_id
),
planned_map as (
  select distinct
    d.set_id,
    pe.planned_exercise_id
  from public.dim_planned_session_set d
  join public.dim_planned_session_exercise pe
    on pe.planned_session_id = d.session_id
   and pe.custom_exercise_id = d.custom_exercise_id
)
insert into public.fact_session_exercise
  (session_exercise_id, user_id, session_id, custom_exercise_id,
   exercise_order, exercise_name, planned_exercise_id)
select
  gen_random_uuid()::text,
  fs.user_id,
  g.session_id,
  g.custom_exercise_id,
  coalesce(o.pos, g.base_rank),
  g.exercise_name,
  (select pm.planned_exercise_id
     from public.fact_session_set fs0
     join planned_map pm on pm.set_id = fs0.parent_set_id
    where fs0.session_id = g.session_id
      and fs0.custom_exercise_id is not distinct from g.custom_exercise_id
      and fs0.parent_set_id is not null
    limit 1)
from groups g
join public.fact_session fs on fs.session_id = g.session_id
left join ordered_ids o
  on o.session_id = g.session_id
 and o.exercise_id is not distinct from g.custom_exercise_id;

-- session_exercise_set_id is REUSED verbatim (one-to-one rename);
-- planned_set_id = parent_set_id, same value, honest name.
insert into public.fact_session_exercise_set
  (session_exercise_set_id, user_id, session_exercise_id, custom_variation_id,
   variation_name, set_number, weight, reps, notes, planned_set_id)
select
  fss.session_set_id,
  fss.user_id,
  fe.session_exercise_id,
  fss.custom_variation_id,
  fss.variation_name,
  fss.set_number,
  fss.weight,
  fss.reps,
  fss.notes,
  fss.parent_set_id
from public.fact_session_set fss
join public.fact_session_exercise fe
  on fe.session_id = fss.session_id
 and fe.custom_exercise_id is not distinct from fss.custom_exercise_id;

drop function public._lambda_safe_jsonb(text);

-- The tab-order blob has served its purpose — exercise_order is a real
-- column on fact_session_exercise now.
alter table public.fact_session drop column exercise_order;

-- ── 5. Progression mode moves to the run ──────────────────────────────────────

alter table public.fact_program_run
  add column progression_mode text
  check (progression_mode in ('frequency', 'order'));

update public.fact_program_run r
set progression_mode =
  case p.progression_mode when 'calendar' then 'frequency' else 'order' end
from public.dim_program p
where p.program_id = r.program_id;

-- ── 6. dim_program / dim_planned_session column drops ─────────────────────────

alter table public.dim_program
  add column program_updated_date timestamptz;
update public.dim_program set program_updated_date = program_created_date;
alter table public.dim_program
  alter column program_updated_date set not null,
  drop column program_length_weeks,
  drop column progression_mode;

alter table public.dim_planned_session
  drop column program_id,
  drop column sequence_order,
  drop column day_of_week;

-- ── 7. Drop the old tables ────────────────────────────────────────────────────

drop table public.fact_session_set;
drop table public.dim_planned_session_set;
drop table public.dim_exercise_variation_bridge;

-- ── 8. RLS for the new tables (owner ALL + coach SELECT, house shapes) ────────

alter table public.dim_planned_session_exercise enable row level security;
create policy "dim_planned_session_exercise owner access"
  on public.dim_planned_session_exercise for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_planned_session_exercise coach access"
  on public.dim_planned_session_exercise for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = dim_planned_session_exercise.user_id));

alter table public.dim_planned_session_exercise_set enable row level security;
create policy "dim_planned_session_exercise_set owner access"
  on public.dim_planned_session_exercise_set for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_planned_session_exercise_set coach access"
  on public.dim_planned_session_exercise_set for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = dim_planned_session_exercise_set.user_id));

alter table public.dim_planned_session_program enable row level security;
create policy "dim_planned_session_program owner access"
  on public.dim_planned_session_program for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_planned_session_program coach access"
  on public.dim_planned_session_program for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = dim_planned_session_program.user_id));

alter table public.fact_session_exercise enable row level security;
create policy "fact_session_exercise owner access"
  on public.fact_session_exercise for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "fact_session_exercise coach access"
  on public.fact_session_exercise for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_session_exercise.user_id));

alter table public.fact_session_exercise_set enable row level security;
create policy "fact_session_exercise_set owner access"
  on public.fact_session_exercise_set for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "fact_session_exercise_set coach access"
  on public.fact_session_exercise_set for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_session_exercise_set.user_id));

-- ── 9. Publication ────────────────────────────────────────────────────────────

alter publication powersync set table
  public.dim_user,
  public.fact_session,
  public.dim_exercise,
  public.dim_variation,
  public.fact_bodyweight,
  public.dim_program,
  public.fact_program_run,
  public.dim_lesson,
  public.dim_planned_session,
  public.fact_goal,
  public.coaching_relationship,
  public.fact_session_exercise,
  public.fact_session_exercise_set,
  public.dim_planned_session_exercise,
  public.dim_planned_session_exercise_set,
  public.dim_planned_session_program;

-- ── 10. Grants ────────────────────────────────────────────────────────────────

grant select, insert, update, delete on
  public.dim_planned_session_exercise,
  public.dim_planned_session_exercise_set,
  public.dim_planned_session_program,
  public.fact_session_exercise,
  public.fact_session_exercise_set
  to anon, authenticated;
