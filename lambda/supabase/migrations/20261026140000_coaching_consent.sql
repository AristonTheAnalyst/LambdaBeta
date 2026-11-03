-- 2026-10-26: coaching consent gate (backlog #21/#22).
--
-- A coaching relationship becomes two-step: the coach's row is an invitation,
-- and the athlete accepts it. Until then the coach sees NOTHING — the
-- coaching_data stream's `my_athletes` CTE requires accepted_date, so an
-- unaccepted row sends no athlete rows to the coach's device. That is the
-- gate #22's accept flow opens.
--
-- NULL means "not accepted". Existing rows are deliberately NOT grandfathered:
-- a row that predates an acceptance step never recorded agreement, and this
-- table has had no UI, so there is nothing a user is waiting to see. #22 adds
-- the invite/accept RPCs; #21 ships the gate and the coach's read surface.
--
-- The athletes index serves the athlete-side read ("my coach", #22) and the
-- accept RPC's lookup; the primary key already covers the coach side.

alter table public.coaching_relationship
  add column if not exists accepted_date timestamptz;

create index if not exists coaching_relationship_athlete_idx
  on public.coaching_relationship (athlete_user_id);

comment on column public.coaching_relationship.accepted_date is
  'When the athlete accepted the coaching invitation. NULL = pending or '
  'revoked — the coach reads no athlete data until this is set.';
