-- Coaching: invite, accept, revoke (2026-10-26, backlog #22).
--
-- The coaching edge is now a request/accept pair:
--   * a coach invites an athlete by their friend code — accepted_date NULL;
--   * the athlete accepts (accepted_date = now()) or declines (row deleted);
--   * either side can end the relationship (row deleted).
--
-- Every state change is a SECURITY DEFINER RPC so the guards live in one
-- place: resolution of a code the caller cannot read, "not yourself", and
-- "only the athlete stamps accepted_date". The two client write policies
-- below exist only so the client's local mirror of an RPC's effect uploads
-- cleanly (a mirror PUT/PATCH is a no-op REST-side); they are shaped so a
-- coach can never write an accepted row:
--   * coach INSERT — accepted_date must be NULL (an invitation, nothing more);
--   * athlete UPDATE — the athlete's own row only (their consent to give).
-- The old catch-all "coaching_relationship coach access" (FOR ALL) policy is
-- dropped: it let a coach insert a row with accepted_date already set, which
-- would have bypassed consent entirely — the stream gate honours the column.

-- 1. Writes ------------------------------------------------------------------

-- Invite by friend code. Returns the athlete it resolved, plus whether the
-- row is new, exactly like add_friend_by_code — the client mirrors locally
-- only when `created`, so a re-invite never queues an upsert against a row
-- that may have been accepted since.
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

  insert into public.coaching_relationship (coach_user_id, athlete_user_id)
  values (v_caller, v_athlete)
  on conflict (coach_user_id, athlete_user_id) do nothing;
  v_created := found;

  return jsonb_build_object(
    'athlete_user_id', v_athlete,
    'created', v_created
  );
end;
$$;

-- The athlete's consent. Only a PENDING row where the caller IS the athlete
-- can be stamped; any other pair raises, so a stale card (the coach withdrew
-- a breath earlier) says so instead of silently doing nothing.
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
end;
$$;

-- End the relationship, from either side: the coach's revoke, the athlete's
-- decline (a pending row) or withdrawal of consent (an accepted one). One
-- verb because there is one edge; which side called decides the wording.
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
end;
$$;

revoke all on function public.coach_invite_by_code(text) from public, anon;
revoke all on function public.accept_coaching_invitation(uuid) from public, anon;
revoke all on function public.remove_coaching_relationship(uuid) from public, anon;
grant execute on function public.coach_invite_by_code(text) to authenticated;
grant execute on function public.accept_coaching_invitation(uuid) to authenticated;
grant execute on function public.remove_coaching_relationship(uuid) to authenticated;

-- 2. The relationship table's own policies -----------------------------------

-- The old FOR ALL policy let a coach set accepted_date on insert. Replace it
-- with exactly the two shapes a client's mirror needs, and nothing more.
do $$ begin
  drop policy if exists "coaching_relationship coach access"
    on public.coaching_relationship;
  drop policy if exists "coaching_relationship coach insert"
    on public.coaching_relationship;
  drop policy if exists "coaching_relationship athlete accept"
    on public.coaching_relationship;
end $$;

-- The coach's mirror of an invitation they just sent. Never accepted.
create policy "coaching_relationship coach insert"
  on public.coaching_relationship for insert to authenticated
  with check (coach_user_id = auth.uid() and accepted_date is null);

-- The athlete's mirror of their own acceptance. With check pins the athlete
-- to themselves; the coach id may change (it is the athlete sharing their own
-- training with someone else, which is theirs to do).
create policy "coaching_relationship athlete accept"
  on public.coaching_relationship for update to authenticated
  using (athlete_user_id = auth.uid())
  with check (athlete_user_id = auth.uid());

-- "coaching_relationship read" (SELECT, either side) is unchanged.
-- Removal is the RPC's alone: it is SECURITY DEFINER, so no DELETE policy is
-- needed for it, and the client mirrors the RPC's effect locally.

-- 3. Tighten every coach SELECT policy to the consent gate --------------------
-- A pending invitation grants nothing on REST either — the stream already
-- refuses it, and these policies are the defence when a client queries REST
-- directly. Predicate shape is unchanged except `accepted_date is not null`.
do $$
declare
  t text;
begin
  foreach t in array array[
    'dim_exercise', 'dim_lesson', 'dim_planned_session',
    'dim_planned_session_exercise', 'dim_planned_session_exercise_set',
    'dim_planned_session_program', 'dim_pr_view_setting', 'dim_program',
    'dim_program_block', 'dim_user', 'dim_variation', 'fact_bodyweight',
    'fact_goal', 'fact_goal_target', 'fact_program_review',
    'fact_program_run', 'fact_session', 'fact_session_exercise',
    'fact_session_exercise_set'
  ] loop
    execute format(
      'drop policy if exists %I on public.%I',
      t || ' coach access', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (exists (select 1 from public.coaching_relationship cr '
      'where cr.coach_user_id = auth.uid() '
      'and cr.athlete_user_id = %I.user_id '
      'and cr.accepted_date is not null))',
      t || ' coach access', t, t);
  end loop;
end $$;

-- No column changes: accepted_date already landed in
-- 20261026140000_coaching_consent.sql.
