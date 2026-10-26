-- Coaching: authoring, assignment and feedback (2026-10-26, backlog #24).
--
-- The write direction of coaching. Until now the coach only READ an accepted
-- athlete's history (#21/#22); this migration gives the coach a way to author:
--
--   * `fact_coach_assignment` — the coach assigns one of their own workouts to
--     an accepted athlete. The row carries a ProgramContent SNAPSHOT of the
--     workout (the review snapshot's document) plus a names map, because the
--     athlete's accept materializes a COPY into their own library and
--     `dim_exercise` / `dim_variation` ids are per-user — the athlete cannot
--     resolve the coach's ids, so the names travel with the document.
--     Templates are never shared rows: the coach keeps editing theirs, the
--     athlete owns their copy, and the two never collide.
--
--   * `fact_coach_feedback` — the coach's note on one of the athlete's
--     completed sessions. One row per (coach, session); both parties read it,
--     only its author writes it.
--
-- Consent is per item. An assignment lands unstamped and grants the athlete
-- nothing until they accept (which is when the copy is written); declining
-- stamps the row. Both stamped columns live here so a declined assignment
-- stays as history without ever being "pending" again.
--
-- `dim_planned_session.coach_assignment_id` is the copy's provenance: a plain
-- ref (NO FK), the `base_session_id` precedent — an offline accept must not be
-- able to fail an FK on upload.

-- 1. The helper ---------------------------------------------------------------
-- SECURITY DEFINER so the predicate reads the relationship row regardless of
-- the caller's own policies (the same idiom as are_friends/friend_shares_notes).
-- Only an ACCEPTED edge counts: a pending invitation coaches nobody.

create or replace function public.coaches_athlete(p_coach uuid, p_athlete uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.coaching_relationship cr
    where cr.coach_user_id = p_coach
      and cr.athlete_user_id = p_athlete
      and cr.accepted_date is not null
  );
$$;

revoke all on function public.coaches_athlete(uuid, uuid) from public, anon;
grant execute on function public.coaches_athlete(uuid, uuid) to authenticated;

-- 2. The copy's provenance ----------------------------------------------------

alter table public.dim_planned_session
  add column if not exists coach_assignment_id text;

comment on column public.dim_planned_session.coach_assignment_id is
  'The coach assignment this workout was copied from (NULL = the athlete''s '
  'own). Plain ref, no FK: the accept happens offline and the assignment row '
  'may outlive a sync round.';

-- 3. Assignments --------------------------------------------------------------

create table public.fact_coach_assignment (
  assignment_id  text primary key,
  coach_user_id  uuid not null references public.dim_user (user_id) on delete cascade,
  athlete_user_id uuid not null references public.dim_user (user_id) on delete cascade,
  -- The coach's source template. Informational: the snapshot is what the copy
  -- is built from, so editing (or archiving) the template later changes nothing.
  planned_session_id text not null,
  -- The workout's name at assignment time — the copy keeps it.
  name text not null,
  -- The coach's message with the assignment (optional prose).
  note text,
  -- The ProgramContent document for the one workout, frozen at assignment time.
  snapshot_content text not null,
  -- {"exercises": {id: name}, "variations": {id: name}} — the names the athlete
  -- cannot resolve from their own dims (per-user ids). The one deliberate
  -- deviation from "names are not embedded", and only for a cross-user copy.
  names_json text,
  created_date timestamptz not null default now(),
  accepted_date timestamptz,
  declined_date timestamptz,
  -- The athlete's copy once accepted (the row in their own library).
  athlete_planned_session_id text
);

create index fact_coach_assignment_coach_idx
  on public.fact_coach_assignment (coach_user_id, created_date desc);
create index fact_coach_assignment_athlete_idx
  on public.fact_coach_assignment (athlete_user_id, created_date desc);

alter table public.fact_coach_assignment enable row level security;

create policy "fact_coach_assignment read"
  on public.fact_coach_assignment for select to authenticated
  using (coach_user_id = auth.uid() or athlete_user_id = auth.uid());

-- The coach's own insert, only toward an athlete who accepted the coaching
-- edge, and only as an invitation (never pre-stamped).
create policy "fact_coach_assignment coach insert"
  on public.fact_coach_assignment for insert to authenticated
  with check (
    coach_user_id = auth.uid()
    and accepted_date is null
    and declined_date is null
    and public.coaches_athlete(coach_user_id, athlete_user_id)
  );

-- The athlete's decision: accept stamps accepted_date (and their copy's id),
-- decline stamps declined_date. The row is theirs to answer, never to re-author.
create policy "fact_coach_assignment athlete decide"
  on public.fact_coach_assignment for update to authenticated
  using (athlete_user_id = auth.uid())
  with check (athlete_user_id = auth.uid());

-- Withdrawal: the coach may take back what nobody accepted yet. An accepted
-- assignment is history and stays.
create policy "fact_coach_assignment coach withdraw"
  on public.fact_coach_assignment for delete to authenticated
  using (coach_user_id = auth.uid() and accepted_date is null);

grant select, insert, update, delete on public.fact_coach_assignment
  to anon, authenticated;

alter publication powersync add table public.fact_coach_assignment;

comment on table public.fact_coach_assignment is
  'A coach assigning one of their workouts to an accepted athlete: a frozen '
  'ProgramContent snapshot plus the names the athlete cannot resolve. The '
  'athlete accept copies it into their library (dim_planned_session'
  '.coach_assignment_id) and stamps accepted_date; templates are never shared '
  'rows, so neither side''s edits reach the other.';

-- 4. Feedback -----------------------------------------------------------------

create table public.fact_coach_feedback (
  feedback_id    text primary key,
  coach_user_id  uuid not null references public.dim_user (user_id) on delete cascade,
  athlete_user_id uuid not null references public.dim_user (user_id) on delete cascade,
  session_id     text not null references public.fact_session (session_id) on delete cascade,
  body           text not null,
  created_date   timestamptz not null default now(),
  edited_date    timestamptz
);

-- One coach's note per session: the viewer draws one card per side.
create unique index fact_coach_feedback_coach_session_idx
  on public.fact_coach_feedback (coach_user_id, session_id);
create index fact_coach_feedback_athlete_idx
  on public.fact_coach_feedback (athlete_user_id, session_id);

alter table public.fact_coach_feedback enable row level security;

create policy "fact_coach_feedback read"
  on public.fact_coach_feedback for select to authenticated
  using (coach_user_id = auth.uid() or athlete_user_id = auth.uid());

-- The coach writes only on an accepted edge, and only on a session that
-- actually belongs to that athlete.
create policy "fact_coach_feedback coach insert"
  on public.fact_coach_feedback for insert to authenticated
  with check (
    coach_user_id = auth.uid()
    and public.coaches_athlete(coach_user_id, athlete_user_id)
    and exists (
      select 1 from public.fact_session s
      where s.session_id = fact_coach_feedback.session_id
        and s.user_id = fact_coach_feedback.athlete_user_id
    )
  );

create policy "fact_coach_feedback coach update"
  on public.fact_coach_feedback for update to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid());

create policy "fact_coach_feedback coach delete"
  on public.fact_coach_feedback for delete to authenticated
  using (coach_user_id = auth.uid());

grant select, insert, update, delete on public.fact_coach_feedback
  to anon, authenticated;

alter publication powersync add table public.fact_coach_feedback;

comment on table public.fact_coach_feedback is
  'A coach''s note on one of an accepted athlete''s completed sessions. One '
  'row per (coach, session); both parties read it, only its author writes it.';
