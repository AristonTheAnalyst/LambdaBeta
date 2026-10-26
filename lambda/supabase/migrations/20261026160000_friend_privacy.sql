-- =============================================================================
-- Per-friend privacy tiers (2026-10-26, #23)
--
-- A friendship shares training by default: completed sessions, their sets and
-- each set's notes. NOTES ABOUT THE WORK — the exercise notes in dim_lesson
-- and a session's own pre/post notes — are a second tier the owner opens per
-- friend, on their OWN directed friend_relationship row. The friend never
-- sees the flag; it only decides what the streams send them.
--
-- Why the flag lives HERE: the row IS the per-friend setting, and the owner's
-- half is the only half they may write. The RPC owns friendship itself (it
-- writes both directions), but this preference is unilateral and rides the
-- same composite-key UPDATE as `nickname`.
--
-- Why the gate is in the STREAM, not (only) in RLS: Postgres RLS is row-level
-- and cannot mask a column, so the two note categories are gated differently:
--   * dim_lesson — one row per exercise note, so a ROW policy is enough. The
--     friend-access policy below now requires the flag (and stays the REST
--     defence, mirroring what the friends_data stream sends).
--   * fact_session — its pre_notes/post_notes are COLUMNS among the session's
--     numbers, so the friends_data stream sends two disjoint queries: the
--     full row for friends who share notes, the row with `NULL AS
--     pre_notes/post_notes` for those who don't (powersync/sync-streams.yaml).
--     The REST policy stays row-level: a friend may still read the session —
--     the numbers are theirs to see — and the app never reads local rows from
--     REST anyway.
--
-- The coach path (coaching_data) is deliberately untouched: a coaching
-- relationship is an explicit consent to review training, and its gate is
-- coaching_relationship.accepted_date.
--
-- Tier 3 (a friend planning sessions on your behalf) arrives with the
-- coaching authoring work (#24) and reuses its consent flow.
-- =============================================================================

alter table public.friend_relationship
  add column if not exists share_notes boolean not null default false;

-- SECURITY DEFINER so policy evaluation never recurses into
-- friend_relationship's own RLS — are_friends()'s shape, plus the flag. The
-- only exposure is a boolean for an arbitrary pair of user ids.
create or replace function public.friend_shares_notes(p_owner uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
           select 1 from public.friend_relationship f
           where f.user_id = p_owner and f.friend_user_id = p_viewer
             and f.share_notes
         )
     and exists (
           select 1 from public.friend_relationship f
           where f.user_id = p_viewer and f.friend_user_id = p_owner
         );
$$;

revoke all on function public.friend_shares_notes(uuid, uuid) from public, anon;
grant execute on function public.friend_shares_notes(uuid, uuid) to authenticated;

-- Every dim_lesson row IS a note, so a friend's REST read follows the same
-- gate the stream applies. Replaces the 2026-10-23 policy — this is a
-- tightening, not an addition.
drop policy if exists "dim_lesson friend access" on public.dim_lesson;

create policy "dim_lesson friend access"
  on public.dim_lesson
  for select
  to authenticated
  using (public.friend_shares_notes(user_id, auth.uid()));
