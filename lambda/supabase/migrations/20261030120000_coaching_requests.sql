-- Coaching asks, both directions (2026-10-30).
--
-- Coaching is a permission that rides on a friendship: nothing about the
-- coaching edge exists before both directed `friend_relationship` rows are
-- accepted. The old model only let a COACH invite an athlete by code; this
-- migration adds the missing half so either friend can ask the other:
--
--   * request_coaching(coach)  — the athlete asks a friend to coach them;
--   * offer_coaching(athlete)   — a coach offers to coach a friend;
--   * accept_coaching_request(other) — the OTHER side of a pending row
--     accepts, whichever direction it was asked in.
--
-- `requested_by_user_id` is what makes a pending row readable on both
-- devices: the row's SHAPE cannot tell "I asked them" from "they asked me".
-- Rows written before this migration were all coach-initiated (the only flow
-- that existed), so they backfill to the coach.
--
-- Acceptance also stamps the athlete's `friend_relationship` grant
-- (`coaching_requested_at` / `coaching_granted_at`), which is what
-- `is_coach_of()` — and therefore every coach write policy — reads. Removing
-- the edge clears it again. That bridges the two consent models without
-- touching the streams: `coaching_data` keeps gating on this table's
-- `accepted_date`.

-- 1. Who asked ---------------------------------------------------------------

alter table public.coaching_relationship
  add column if not exists requested_by_user_id uuid;

update public.coaching_relationship
   set requested_by_user_id = coach_user_id
 where requested_by_user_id is null;

-- 2. Friendship is the floor -------------------------------------------------

-- `are_friends()` (20261023120000) is left exactly as it is: every RLS policy
-- that reads a friend's rows uses it, and friendship is still instant, so
-- "both directed rows exist" is the whole test. The coaching RPCs below use
-- that same shape.

-- A friendship is accepted the moment it exists (there is no request step
-- yet), so the add path stamps `accepted_date` — the column `is_coach_of`
-- requires on both rows. The 20261028140000 backfill covered every row that
-- existed then; this heals any written since, and keeps new pairs stamping.
update public.friend_relationship
   set accepted_date = coalesce(created_date, now())
 where accepted_date is null;

create or replace function public.add_friend_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller  uuid := auth.uid();
  v_code    text;
  v_friend  public.dim_user%rowtype;
  v_created boolean := false;
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$' then
    raise exception 'friend_code_invalid' using errcode = 'P0001';
  end if;

  select u.* into v_friend
    from public.dim_user u
    join public.dim_friend_code c on c.user_id = u.user_id
   where c.friend_code = v_code;
  if not found then
    raise exception 'friend_code_not_found' using errcode = 'P0001';
  end if;
  if v_friend.user_id = v_caller then
    raise exception 'cannot_add_self' using errcode = 'P0001';
  end if;

  insert into public.friend_relationship (user_id, friend_user_id, accepted_date)
  values (v_caller, v_friend.user_id, now())
  on conflict (user_id, friend_user_id) do nothing;
  v_created := found;

  insert into public.friend_relationship (user_id, friend_user_id, accepted_date)
  values (v_friend.user_id, v_caller, now())
  on conflict (user_id, friend_user_id) do nothing;

  return jsonb_build_object(
    'friend_user_id', v_friend.user_id,
    'friend_user_name', v_friend.user_name,
    'friend_user_lastname', v_friend.user_lastname,
    'created', v_created
  );
end;
$$;

-- 3. Writes ------------------------------------------------------------------

-- The athlete asks a friend to coach them. Returns whether the edge is new,
-- so the client mirrors locally only when it is (a re-ask queues nothing).
create or replace function public.request_coaching(p_coach_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller  uuid := auth.uid();
  v_created boolean := false;
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_coach_user_id = v_caller then
    raise exception 'cannot_coach_self' using errcode = 'P0001';
  end if;
  if not public.are_friends(v_caller, p_coach_user_id) then
    raise exception 'not_friends' using errcode = 'P0001';
  end if;

  insert into public.coaching_relationship
    (coach_user_id, athlete_user_id, requested_by_user_id)
  values (p_coach_user_id, v_caller, v_caller)
  on conflict (coach_user_id, athlete_user_id) do nothing;
  v_created := found;

  -- The ask is recorded on the athlete's own friendship row; the grant waits
  -- for the coach.
  update public.friend_relationship
     set coaching_requested_at = coalesce(coaching_requested_at, now())
   where user_id = v_caller
     and friend_user_id = p_coach_user_id;

  return jsonb_build_object(
    'coach_user_id', p_coach_user_id,
    'athlete_user_id', v_caller,
    'created', v_created
  );
end;
$$;

-- A coach offers to coach a friend.
create or replace function public.offer_coaching(p_athlete_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller  uuid := auth.uid();
  v_created boolean := false;
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_athlete_user_id = v_caller then
    raise exception 'cannot_coach_self' using errcode = 'P0001';
  end if;
  if not public.are_friends(v_caller, p_athlete_user_id) then
    raise exception 'not_friends' using errcode = 'P0001';
  end if;

  insert into public.coaching_relationship
    (coach_user_id, athlete_user_id, requested_by_user_id)
  values (v_caller, p_athlete_user_id, v_caller)
  on conflict (coach_user_id, athlete_user_id) do nothing;
  v_created := found;

  update public.friend_relationship
     set coaching_requested_at = coalesce(coaching_requested_at, now())
   where user_id = p_athlete_user_id
     and friend_user_id = v_caller;

  return jsonb_build_object(
    'coach_user_id', v_caller,
    'athlete_user_id', p_athlete_user_id,
    'created', v_created
  );
end;
$$;

-- The other side accepts whichever direction was asked. Stamps the consent on
-- the edge and the grant on the athlete's friendship row — the pair the coach
-- write policies read.
create or replace function public.accept_coaching_request(p_other_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller  uuid := auth.uid();
  v_coach   uuid;
  v_athlete uuid;
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  update public.coaching_relationship
     set accepted_date = now()
   where accepted_date is null
     and (
       (coach_user_id = v_caller and athlete_user_id = p_other_user_id)
       or (athlete_user_id = v_caller and coach_user_id = p_other_user_id)
     )
     -- Only the side that did NOT ask may accept.
     and coalesce(requested_by_user_id, coach_user_id) = p_other_user_id
  returning coach_user_id, athlete_user_id into v_coach, v_athlete;

  if not found then
    raise exception 'invitation_not_found' using errcode = 'P0001';
  end if;

  update public.friend_relationship
     set coaching_requested_at = coalesce(coaching_requested_at, now()),
         coaching_granted_at = now()
   where user_id = v_athlete
     and friend_user_id = v_coach;

  return jsonb_build_object(
    'coach_user_id', v_coach,
    'athlete_user_id', v_athlete
  );
end;
$$;

-- The old athlete-accepts-a-coach-invite RPC stays callable (older builds),
-- and now also stamps the grant the write policies read.
create or replace function public.accept_coaching_invitation(p_coach_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  update public.coaching_relationship
     set accepted_date = now()
   where coach_user_id = p_coach_user_id
     and athlete_user_id = v_caller
     and accepted_date is null;
  if not found then
    raise exception 'invitation_not_found' using errcode = 'P0001';
  end if;

  update public.friend_relationship
     set coaching_requested_at = coalesce(coaching_requested_at, now()),
         coaching_granted_at = now()
   where user_id = v_caller
     and friend_user_id = p_coach_user_id;
end;
$$;

-- The old invite-by-code RPC records who asked, like the new pair.
create or replace function public.coach_invite_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller  uuid := auth.uid();
  v_code    text;
  v_athlete uuid;
  v_created boolean := false;
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$' then
    raise exception 'friend_code_invalid' using errcode = 'P0001';
  end if;

  select c.user_id into v_athlete
    from public.dim_friend_code c
   where c.friend_code = v_code;
  if not found then
    raise exception 'friend_code_not_found' using errcode = 'P0001';
  end if;
  if v_athlete = v_caller then
    raise exception 'cannot_coach_self' using errcode = 'P0001';
  end if;

  insert into public.coaching_relationship
    (coach_user_id, athlete_user_id, requested_by_user_id)
  values (v_caller, v_athlete, v_caller)
  on conflict (coach_user_id, athlete_user_id) do nothing;
  v_created := found;

  return jsonb_build_object(
    'athlete_user_id', v_athlete,
    'created', v_created
  );
end;
$$;

-- Ending the edge — declining, withdrawing, revoking or withdrawing consent —
-- also clears the athlete's friendship grant, so `is_coach_of` closes with it.
create or replace function public.remove_coaching_relationship(p_other_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  delete from public.coaching_relationship cr
   where (cr.coach_user_id = v_caller and cr.athlete_user_id = p_other_user_id)
      or (cr.athlete_user_id = v_caller and cr.coach_user_id = p_other_user_id);

  update public.friend_relationship
     set coaching_requested_at = null,
         coaching_granted_at = null
   where (user_id = v_caller and friend_user_id = p_other_user_id)
      or (user_id = p_other_user_id and friend_user_id = v_caller);
end;
$$;

revoke all on function public.request_coaching(uuid) from public, anon;
revoke all on function public.offer_coaching(uuid) from public, anon;
revoke all on function public.accept_coaching_request(uuid) from public, anon;
grant execute on function public.request_coaching(uuid) to authenticated;
grant execute on function public.offer_coaching(uuid) to authenticated;
grant execute on function public.accept_coaching_request(uuid) to authenticated;

-- 4. The table's mirror policies --------------------------------------------

-- The client mirrors each RPC locally: the ask inserts the pending row, the
-- accept stamps it. Both mirrors are shaped so a client can only write the
-- row it asked for, and can only accept a row the OTHER side asked for.
do $$ begin
  drop policy if exists "coaching_relationship coach insert"
    on public.coaching_relationship;
  drop policy if exists "coaching_relationship athlete accept"
    on public.coaching_relationship;
  drop policy if exists "coaching_relationship request insert"
    on public.coaching_relationship;
  drop policy if exists "coaching_relationship request accept"
    on public.coaching_relationship;
end $$;

create policy "coaching_relationship request insert"
  on public.coaching_relationship
  for insert to authenticated
  with check (
    accepted_date is null
    and requested_by_user_id = auth.uid()
    and (coach_user_id = auth.uid() or athlete_user_id = auth.uid())
  );

create policy "coaching_relationship request accept"
  on public.coaching_relationship
  for update to authenticated
  using (
    accepted_date is null
    and coalesce(requested_by_user_id, coach_user_id) <> auth.uid()
    and (coach_user_id = auth.uid() or athlete_user_id = auth.uid())
  )
  with check (coach_user_id = auth.uid() or athlete_user_id = auth.uid());
