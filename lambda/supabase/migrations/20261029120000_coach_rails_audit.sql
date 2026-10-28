-- Coach rails, audit trail and name history (2026-10-29)
--
-- The direct-write model gets its server-side rails:
--   * a coach may edit only rows THEY created — never the athlete's own;
--   * a coach may never soft-delete/archive anything (is_deleted,
--     date_archived, is_archived are frozen for a non-owner writer);
--   * every row records when it was created, who last changed it and when,
--     and exercise/variation/workout renames are logged for history + undo;
--   * write quotas bound an automated client to a human scale;
--   * one coach per athlete, enforced by partial unique indexes.
-- Additive and safe for the current build: it only narrows what a coach may
-- do and adds columns/tables.

-- 1. Audit columns ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'fact_session', 'fact_session_exercise', 'fact_session_exercise_set',
    'dim_exercise', 'dim_variation',
    'dim_planned_session', 'dim_planned_session_exercise',
    'dim_planned_session_exercise_set', 'dim_exercise_note',
    'fact_goal', 'fact_goal_target'
  ] loop
    execute format(
      'alter table public.%I add column if not exists created_at timestamptz', t);
    execute format(
      'alter table public.%I add column if not exists updated_by_user_id text', t);
    execute format(
      'alter table public.%I add column if not exists updated_at timestamptz', t);
  end loop;
end $$;

-- Backfill what the existing creation timestamps can tell us. dim_exercise and
-- dim_variation never carried one; their old rows stay NULL.
update public.dim_planned_session set created_at = created_date
 where created_at is null;
update public.dim_exercise_note set created_at = note_created_date
 where created_at is null;
update public.fact_goal set created_at = goal_created_date
 where created_at is null;
update public.fact_session set created_at = created_datetime
 where created_at is null;

update public.dim_planned_session_exercise e
   set created_at = d.created_date
  from public.dim_planned_session d
 where d.session_id = e.planned_session_id and e.created_at is null;

update public.dim_planned_session_exercise_set ps
   set created_at = d.created_date
  from public.dim_planned_session_exercise e
  join public.dim_planned_session d on d.session_id = e.planned_session_id
 where e.planned_exercise_id = ps.planned_exercise_id
   and ps.created_at is null;

update public.fact_session_exercise e
   set created_at = s.created_datetime
  from public.fact_session s
 where s.session_id = e.session_id and e.created_at is null;

update public.fact_session_exercise_set ss
   set created_at = s.created_datetime
  from public.fact_session_exercise se
  join public.fact_session s on s.session_id = se.session_id
 where se.session_exercise_id = ss.session_exercise_id
   and ss.created_at is null;

update public.fact_goal_target gt
   set created_at = g.goal_created_date
  from public.fact_goal g
 where g.goal_id = gt.goal_id and gt.created_at is null;

-- 2. Audit stamping -----------------------------------------------------------
-- created_at on insert (when the client did not supply one); updated_by/at on
-- every update. The author trigger still owns created_by; the identity lock
-- keeps created_at immutable alongside user_id/created_by.
create or replace function public.stamp_row_audit()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_at is null then new.created_at := now(); end if;
  else
    new.updated_at := now();
    new.updated_by_user_id := auth.uid()::text;
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'fact_session', 'fact_session_exercise', 'fact_session_exercise_set',
    'dim_exercise', 'dim_variation',
    'dim_planned_session', 'dim_planned_session_exercise',
    'dim_planned_session_exercise_set', 'dim_exercise_note',
    'fact_goal', 'fact_goal_target'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   t || '_stamp_audit', t);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.stamp_row_audit()',
      t || '_stamp_audit', t);
  end loop;
end $$;

create or replace function public.lock_row_identity()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'row identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- 3. A coach edits only what they created -------------------------------------
-- Her own rows become read-only to the coach; the coach's own creations stay
-- editable. Hard deletes were already impossible (no DELETE policy).
do $$
declare
  t text;
begin
  foreach t in array array[
    'fact_session', 'fact_session_exercise', 'fact_session_exercise_set',
    'dim_exercise', 'dim_variation',
    'dim_planned_session', 'dim_planned_session_exercise',
    'dim_planned_session_exercise_set', 'dim_exercise_note',
    'fact_goal', 'fact_goal_target'
  ] loop
    execute format('drop policy if exists %I on public.%I',
                   t || ' coach update', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.is_coach_of(user_id) '
      'and created_by_user_id = auth.uid()::text) '
      'with check (public.is_coach_of(user_id) '
      'and created_by_user_id = auth.uid()::text)',
      t || ' coach update', t);
  end loop;
end $$;

-- 4. A coach can never soft-delete --------------------------------------------
-- WITH CHECK cannot compare OLD and NEW, so the flag columns are guarded by a
-- trigger: a non-owner writer may not change is_deleted / date_archived /
-- is_archived on any row — their own creations included.
create or replace function public.forbid_coach_archive_flags()
returns trigger
language plpgsql
as $$
declare
  col text;
  oldv text;
  newv text;
begin
  -- Server-side maintenance (no JWT) is not a coach.
  if auth.uid() is null then return new; end if;
  if old.user_id is distinct from auth.uid() then
    foreach col in array tg_argv loop
      oldv := to_jsonb(old) ->> col;
      newv := to_jsonb(new) ->> col;
      if oldv is distinct from newv then
        raise exception 'a coach cannot archive or delete rows'
          using errcode = '42501';
      end if;
    end loop;
  end if;
  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('dim_exercise', 'date_archived'),
      ('dim_variation', 'date_archived'),
      ('dim_planned_session', 'date_archived'),
      ('dim_planned_session_exercise', 'is_archived'),
      ('dim_planned_session_exercise_set', 'is_archived'),
      ('dim_exercise_note', 'is_archived'),
      ('fact_session_exercise_set', 'is_deleted')
    ) as v(tbl, col)
  loop
    execute format('drop trigger if exists %I on public.%I',
                   r.tbl || '_coach_archive_guard', r.tbl);
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.forbid_coach_archive_flags(%L)',
      r.tbl || '_coach_archive_guard', r.tbl, r.col);
  end loop;
end $$;

-- 5. Write quotas -------------------------------------------------------------
-- An automated client with the coach's token is the real threat, not a thumb.
-- Human-scale bounds: 500 rows/hour per actor per table, 5,000 coach-created
-- rows per athlete per table. Owner writes are never counted.
create or replace function public.enforce_coach_write_quota()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recent bigint;
  total bigint;
begin
  -- Server-side maintenance (no JWT) and the owner's own writes are never
  -- quota'd.
  if auth.uid() is null then return new; end if;
  if new.user_id = auth.uid() then return new; end if;

  execute format(
    'select count(*) from public.%I '
    'where created_by_user_id = $1 and created_at > now() - interval ''1 hour''',
    tg_table_name) into recent using auth.uid()::text;
  if recent >= 500 then
    raise exception 'coach write rate limit reached' using errcode = 'P0001';
  end if;

  execute format(
    'select count(*) from public.%I '
    'where user_id = $1 and created_by_user_id is not null',
    tg_table_name) into total using new.user_id;
  if total >= 5000 then
    raise exception 'coach write cap reached for this athlete'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'fact_session', 'fact_session_exercise', 'fact_session_exercise_set',
    'dim_exercise', 'dim_variation',
    'dim_planned_session', 'dim_planned_session_exercise',
    'dim_planned_session_exercise_set', 'dim_exercise_note',
    'fact_goal', 'fact_goal_target'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
                   t || '_coach_quota', t);
    execute format(
      'create trigger %I before insert on public.%I '
      'for each row execute function public.enforce_coach_write_quota()',
      t || '_coach_quota', t);
  end loop;
end $$;

-- 6. One coach per athlete ----------------------------------------------------
-- A second accepted edge would give one athlete two coaches writing into the
-- same library; the product caps it at one. The same cap on the friend-row
-- grant, which is what the write policies actually read.
create unique index if not exists coaching_relationship_one_coach_per_athlete
  on public.coaching_relationship (athlete_user_id)
  where accepted_date is not null;
create unique index if not exists friend_relationship_one_coach_grant
  on public.friend_relationship (user_id)
  where coaching_granted_at is not null;

-- 7. Name history -------------------------------------------------------------
create table if not exists public.fact_name_change (
  name_change_id text primary key,
  user_id uuid not null references public.dim_user (user_id) on delete cascade,
  entity_type text not null check (entity_type in ('exercise', 'variation', 'workout')),
  entity_id text not null,
  old_name text,
  new_name text,
  changed_by_user_id text,
  changed_at timestamptz not null default now()
);
alter table public.fact_name_change enable row level security;
drop policy if exists "fact_name_change owner access" on public.fact_name_change;
create policy "fact_name_change owner access"
  on public.fact_name_change for select to authenticated
  using (user_id = auth.uid());
grant select on public.fact_name_change to authenticated;
create index if not exists fact_name_change_entity_idx
  on public.fact_name_change (user_id, entity_type, entity_id, changed_at);
do $$ begin
  alter publication powersync add table public.fact_name_change;
exception when duplicate_object then null; end $$;

create or replace function public.log_name_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  kind text;
  ent text;
  oldv text;
  newv text;
begin
  if tg_table_name = 'dim_exercise' then
    kind := 'exercise';
    ent := new.custom_exercise_id;
    oldv := old.exercise_name;
    newv := new.exercise_name;
  elsif tg_table_name = 'dim_variation' then
    kind := 'variation';
    ent := new.custom_variation_id;
    oldv := old.variation_name;
    newv := new.variation_name;
  elsif tg_table_name = 'dim_planned_session' then
    kind := 'workout';
    ent := new.session_id;
    oldv := old.name;
    newv := new.name;
  else
    return new;
  end if;
  if oldv is distinct from newv then
    insert into public.fact_name_change (
      name_change_id, user_id, entity_type, entity_id,
      old_name, new_name, changed_by_user_id, changed_at
    ) values (
      gen_random_uuid()::text, new.user_id, kind, ent,
      oldv, newv, auth.uid()::text, now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists dim_exercise_log_name on public.dim_exercise;
create trigger dim_exercise_log_name
  after update of exercise_name on public.dim_exercise
  for each row execute function public.log_name_change();
drop trigger if exists dim_variation_log_name on public.dim_variation;
create trigger dim_variation_log_name
  after update of variation_name on public.dim_variation
  for each row execute function public.log_name_change();
drop trigger if exists dim_planned_session_log_name on public.dim_planned_session;
create trigger dim_planned_session_log_name
  after update of name on public.dim_planned_session
  for each row execute function public.log_name_change();
