-- =============================================================================
-- Friends (2026-10-23)
--
-- One social feature: every user carries a shareable 8-character friend code;
-- entering someone's code makes the friendship instantly and mutually. A
-- friendship is TWO directed rows in friend_relationship — written only by the
-- SECURITY DEFINER RPC below, so a client can never grant itself a one-sided
-- "friendship" that exposes anything. Every read (RLS here, the friends_data
-- sync stream) requires both directions.
--
-- Friend reads of another person's training data go through the sync stream,
-- which is the privacy boundary (streams bypass RLS). The policies added at
-- the end are the REST-side defence in depth, mirroring the coaching
-- migration's shape but MUTUAL.
--
-- The friend code lives in a SIDE TABLE, not a dim_user column: the user_data
-- stream selects `dim_user *`, so a new column would reach old app builds
-- whose local schema does not know it. This row streams only to its owner.
-- =============================================================================

-- 1. Friend codes -------------------------------------------------------------

create table if not exists public.dim_friend_code (
  user_id      uuid primary key references public.dim_user (user_id) on delete cascade,
  friend_code  text not null unique,
  created_date timestamptz not null default now(),
  -- 8 chars from a 32-symbol alphabet: A-H J-N P-Z 2-9 (no I, O, 0, 1 —
  -- the pairs that get misread). 32^8 ≈ 1.1e12 possibilities.
  constraint dim_friend_code_shape check
    (friend_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$')
);

alter table public.dim_friend_code enable row level security;

-- Owner-read only. No write grants: the trigger below is the only writer.
do $$ begin
  create policy "dim_friend_code owner read"
    on public.dim_friend_code
    for select
    to authenticated
    using (user_id = auth.uid());
exception when duplicate_object then null; end $$;

grant select on public.dim_friend_code to authenticated;

-- Picks a random 8-character code, retrying while it already exists. The
-- unique index is the backstop against the (astronomically unlikely) race.
create or replace function public.generate_friend_code()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  i int;
  attempt int;
begin
  for attempt in 1..20 loop
    candidate := '';
    for i in 1..8 loop
      candidate := candidate ||
        substr(alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    if not exists (
      select 1 from public.dim_friend_code where friend_code = candidate
    ) then
      return candidate;
    end if;
  end loop;
  raise exception 'friend_code_generation_failed';
end;
$$;

revoke all on function public.generate_friend_code() from public, anon, authenticated;

-- Every new user gets a code. SECURITY DEFINER so the insert passes
-- dim_friend_code's RLS regardless of the inserting role (handle_new_user,
-- itself SECURITY DEFINER, is the only caller path).
create or replace function public.create_friend_code_for_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.dim_friend_code (user_id, friend_code)
  values (new.user_id, public.generate_friend_code())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_dim_user_created on public.dim_user;
create trigger on_dim_user_created
  after insert on public.dim_user
  for each row execute function public.create_friend_code_for_user();

-- Backfill every user who predates the feature.
do $$
declare r record;
begin
  for r in
    select u.user_id from public.dim_user u
    where not exists (
      select 1 from public.dim_friend_code c where c.user_id = u.user_id
    )
  loop
    insert into public.dim_friend_code (user_id, friend_code)
    values (r.user_id, public.generate_friend_code())
    on conflict (user_id) do nothing;
  end loop;
end $$;

-- 2. The relationship graph ---------------------------------------------------

-- One ROW PER DIRECTION: `user_id` has `friend_user_id` as a friend. The RPC
-- writes both rows in one call, so a friendship is the PAIR; one row alone
-- exposes nothing and lists nobody.
create table if not exists public.friend_relationship (
  user_id        uuid not null references public.dim_user (user_id) on delete cascade,
  friend_user_id uuid not null references public.dim_user (user_id) on delete cascade,
  created_date   timestamptz not null default now(),
  primary key (user_id, friend_user_id),
  constraint friend_relationship_not_self check (user_id <> friend_user_id)
);

create index if not exists friend_relationship_friend_idx
  on public.friend_relationship (friend_user_id);

alter table public.friend_relationship enable row level security;

-- Either side reads the edge (a client's mutual check reads the incoming half).
do $$ begin
  create policy "friend_relationship read"
    on public.friend_relationship
    for select
    to authenticated
    using (user_id = auth.uid() or friend_user_id = auth.uid());
exception when duplicate_object then null; end $$;

-- Own rows only. `for all` includes UPDATE: the uploader PUTs an upsert, and
-- after the RPC has created the pair the mirrored local row arrives as an
-- ON CONFLICT DO UPDATE — that path needs the UPDATE branch or the upload
-- fails 42501 and is quarantined. The check keeps a client from writing the
-- OTHER user's directed row; that half is the RPC's alone.
do $$ begin
  create policy "friend_relationship owner manage"
    on public.friend_relationship
    for all
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;

grant select, insert, update, delete on public.friend_relationship
  to anon, authenticated;

-- 3. Mutual-friend helper -----------------------------------------------------

-- SECURITY DEFINER so policy evaluation never recurses into
-- friend_relationship's own RLS. The authenticated grant is required because
-- policy expressions run as the querying role; the only exposure is a boolean
-- for an arbitrary pair of user ids.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
           select 1 from public.friend_relationship f
           where f.user_id = a and f.friend_user_id = b
         )
     and exists (
           select 1 from public.friend_relationship f
           where f.user_id = b and f.friend_user_id = a
         );
$$;

revoke all on function public.are_friends(uuid, uuid) from public, anon;
grant execute on function public.are_friends(uuid, uuid) to authenticated;

-- 4. RPCs ---------------------------------------------------------------------

-- Instant, mutual, idempotent. Returns one jsonb object:
--   { friend_user_id, friend_user_name, friend_user_lastname, created }
-- `created` is false when the pair already existed (the UI says "already
-- friends"). RAISE EXCEPTION messages are the client's error keys.
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

  -- u.* (never *): the join would otherwise project the code row's columns
  -- into a dim_user%rowtype variable too.
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

  insert into public.friend_relationship (user_id, friend_user_id)
  values (v_caller, v_friend.user_id)
  on conflict (user_id, friend_user_id) do nothing;
  -- `found` is true only when the INSERT actually inserted: the caller's own
  -- half is the one that says whether this add was new.
  v_created := found;

  insert into public.friend_relationship (user_id, friend_user_id)
  values (v_friend.user_id, v_caller)
  on conflict (user_id, friend_user_id) do nothing;

  return jsonb_build_object(
    'friend_user_id', v_friend.user_id,
    'friend_user_name', v_friend.user_name,
    'friend_user_lastname', v_friend.user_lastname,
    'created', v_created
  );
end;
$$;

-- Removal is unilateral and removes BOTH rows — the pair is the friendship.
create or replace function public.remove_friend(p_friend_user_id uuid)
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
  delete from public.friend_relationship fr
   where (fr.user_id = v_caller and fr.friend_user_id = p_friend_user_id)
      or (fr.user_id = p_friend_user_id and fr.friend_user_id = v_caller);
end;
$$;

revoke all on function public.add_friend_by_code(text) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
grant execute on function public.add_friend_by_code(text) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;

-- 5. Friend reads over REST (defence in depth; sync streams are the boundary) -

-- Completed sessions only, and only with a MUTUAL edge. The coaching
-- migration's shape, with are_friends in place of the one-way EXISTS.
do $$ begin
  create policy "fact_session friend access"
    on public.fact_session
    for select
    to authenticated
    using (end_datetime is not null and public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "fact_session_exercise friend access"
    on public.fact_session_exercise
    for select
    to authenticated
    using (
      public.are_friends(auth.uid(), user_id)
      and exists (
        select 1 from public.fact_session s
        where s.session_id = fact_session_exercise.session_id
          and s.end_datetime is not null
      )
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "fact_session_exercise_set friend access"
    on public.fact_session_exercise_set
    for select
    to authenticated
    using (
      public.are_friends(auth.uid(), user_id)
      and exists (
        select 1 from public.fact_session_exercise fe
        join public.fact_session s on s.session_id = fe.session_id
        where fe.session_exercise_id = fact_session_exercise_set.session_exercise_id
          and s.end_datetime is not null
      )
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "dim_exercise friend access"
    on public.dim_exercise
    for select
    to authenticated
    using (public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "dim_variation friend access"
    on public.dim_variation
    for select
    to authenticated
    using (public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "dim_lesson friend access"
    on public.dim_lesson
    for select
    to authenticated
    using (public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "fact_goal friend access"
    on public.fact_goal
    for select
    to authenticated
    using (public.are_friends(auth.uid(), user_id));
exception when duplicate_object then null; end $$;

-- 6. Publication --------------------------------------------------------------

do $$ begin
  alter publication powersync add table public.dim_friend_code;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication powersync add table public.friend_relationship;
exception when duplicate_object then null; end $$;
