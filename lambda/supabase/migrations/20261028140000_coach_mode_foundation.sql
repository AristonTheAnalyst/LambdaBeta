-- Coach mode foundation (2026-10-28)
--
-- The coach acts ON the athlete's account: rows keep the athlete's user_id and
-- record who wrote them in created_by_user_id. This migration is ADDITIVE — it
-- adds the authorship column, moves the coaching grant onto the friendship
-- rows, teaches the policies the new grant, and forbids the coach from
-- deleting anything. Nothing is dropped; the old coaching_relationship table
-- keeps working for the current build and is retired in a later migration.
--
-- Deploy order: this migration, then the sync-stream update (which grows
-- coaching_data and reads the friendship flags), then a build that writes
-- created_by_user_id. The friend-request UI (code owner accepts) lands with
-- the client phase; existing friendships are backfilled as accepted.

-- 1. Friendship state ---------------------------------------------------------
-- accepted_date NULL = a pending request (the request UI lands later). Every
-- row that exists today is a real friendship, so they are accepted as of the
-- day they were made.
alter table public.friend_relationship
  add column if not exists accepted_date timestamptz;
alter table public.friend_relationship
  add column if not exists coaching_requested_at timestamptz;
-- The grant lives on the ATHLETE's directed row: user_id = athlete,
-- friend_user_id = coach. NULL = no coaching.
alter table public.friend_relationship
  add column if not exists coaching_granted_at timestamptz;

update public.friend_relationship
   set accepted_date = created_date
 where accepted_date is null;

-- 2. Move every accepted coaching edge onto the friendship rows --------------
-- The old invite flow never required friendship, so a pair that coached without
-- being friends gains the friendship now (the product model makes coaching a
-- capability of friendship).
insert into public.friend_relationship (user_id, friend_user_id, accepted_date)
select cr.coach_user_id, cr.athlete_user_id, now()
  from public.coaching_relationship cr
 where cr.accepted_date is not null
on conflict (user_id, friend_user_id)
do update set accepted_date = coalesce(friend_relationship.accepted_date, now());

insert into public.friend_relationship (user_id, friend_user_id, accepted_date)
select cr.athlete_user_id, cr.coach_user_id, now()
  from public.coaching_relationship cr
 where cr.accepted_date is not null
on conflict (user_id, friend_user_id)
do update set accepted_date = coalesce(friend_relationship.accepted_date, now());

-- The athlete's own row toward the coach is the grant.
update public.friend_relationship f
   set coaching_requested_at = coalesce(f.coaching_requested_at, cr.created_date),
       coaching_granted_at = cr.accepted_date
  from public.coaching_relationship cr
 where cr.athlete_user_id = f.user_id
   and cr.coach_user_id = f.friend_user_id
   and cr.accepted_date is not null;

-- A pending invitation becomes a pending ask on the athlete's row (the coach
-- still has to accept under the new model; the old row is left in place).
update public.friend_relationship f
   set coaching_requested_at = coalesce(f.coaching_requested_at, cr.created_date)
  from public.coaching_relationship cr
 where cr.athlete_user_id = f.user_id
   and cr.coach_user_id = f.friend_user_id
   and cr.accepted_date is null;

-- 3. Authorship ---------------------------------------------------------------
-- Who put the row down. NULL = the owner wrote it. No FK on purpose: deleting
-- an account must never cascade into another user's rows.
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
      'alter table public.%I add column if not exists created_by_user_id text',
      t);
  end loop;
end $$;

-- 4. The coach predicate ------------------------------------------------------
-- True when the caller is the accepted coach of p_owner: the owner's directed
-- friendship row toward the caller carries a grant, and both rows are accepted.
-- SECURITY DEFINER so policy evaluation never recurses into
-- friend_relationship's own RLS (the are_friends()/friend_shares_notes shape).
create or replace function public.is_coach_of(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.friend_relationship grant_row
      join public.friend_relationship back_row
        on back_row.user_id = grant_row.friend_user_id
       and back_row.friend_user_id = grant_row.user_id
     where grant_row.user_id = p_owner
       and grant_row.friend_user_id = auth.uid()
       and grant_row.accepted_date is not null
       and grant_row.coaching_granted_at is not null
       and back_row.accepted_date is not null
  );
$$;

revoke all on function public.is_coach_of(uuid) from public, anon;
grant execute on function public.is_coach_of(uuid) to authenticated;

-- 5. Immutable row identity ---------------------------------------------------
-- A policy's WITH CHECK cannot compare OLD and NEW, so a coach could otherwise
-- move a row to another athlete or rewrite the author. This trigger is the
-- rail that keeps user_id and created_by_user_id fixed for every update.
create or replace function public.lock_row_identity()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'row identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- 6. Coach write policies, and never a delete --------------------------------
-- The owner's existing policies stay untouched. These add the coach's half:
-- insert keyed to the acting owner and a self-authored row; update on rows the
-- owner holds; NO delete policy anywhere, so a coach DELETE is refused.
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
                   t || ' coach insert', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (public.is_coach_of(user_id) '
      'and created_by_user_id = auth.uid())',
      t || ' coach insert', t);

    execute format('drop policy if exists %I on public.%I',
                   t || ' coach update', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.is_coach_of(user_id)) '
      'with check (public.is_coach_of(user_id))',
      t || ' coach update', t);

    execute format('drop trigger if exists %I on public.%I',
                   t || '_identity_lock', t);
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.lock_row_identity()',
      t || '_identity_lock', t);
  end loop;
end $$;
