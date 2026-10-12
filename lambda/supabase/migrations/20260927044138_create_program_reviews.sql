-- 2026-09-27: program reviews — the checkpoints a program's run passes through.
--
-- ONE TABLE FOR THREE FLAVOURS. A review is a checkpoint (notes about where the
-- run stands); a change is a checkpoint with a proposed edit attached; a close
-- is the checkpoint written automatically when a run ends. They differ only in
-- what is filled in, so they share a row shape and a `kind` discriminator —
-- three tables would mean three registrations in the sync contract for three
-- things that are always read together.
--
-- NO `status` COLUMN. Status is derived: `completed_date IS NULL` = open,
-- `scheduled_for <= now()` = due, otherwise completed with `outcome` naming what
-- happened. A stored status would be a second source of truth for a question one
-- nullable timestamp already answers, and the two would drift the first time
-- anything wrote one without the other.
--
-- `proposed_content` IS MUTABLE until acted on, and that is correct — it is a
-- PROPOSAL, not a revision. Once the user acts, the outcome is captured
-- immutably as a row in fact_program_revision. Applying a proposal is never
-- automatic: it opens the normal editor pre-filled, and no code path copies
-- proposed_content into live rows. That is what eliminates the whole class of
-- "the proposal referenced a workout that no longer exists" bugs.
--
-- `achievements_json` is the one deliberate exception to the repo's
-- derive-on-read philosophy (see docs / the plan): a finished block's record
-- must not change because someone later corrected a set. The rule is clean —
-- in-progress runs derive, closed runs show the frozen record. Written only by
-- `closeRun`, together with `outcome = 'closed'`.

create table public.fact_program_review (
  review_id        text primary key,
  user_id          uuid not null references public.dim_user (user_id),
  program_id       text not null references public.dim_program (program_id),

  -- Plain text for now: dim_program_block does not exist yet. The blocks
  -- migration adds the FK once the table it points at is real.
  block_id         text,

  program_run_id   text references public.fact_program_run (program_run_id),

  -- 'review' = a checkpoint. 'change' = a checkpoint carrying proposed_content.
  -- 'close'  = the automatic checkpoint at run end.
  kind             text not null check (kind in ('review', 'change', 'close')),

  -- Title and notes are not garnish. A change with no stated rationale is a
  -- diff with no story, and the prompt that surfaces it later is only
  -- actionable if it says what the change was for.
  title            text,
  notes            text,

  -- Null = an unscheduled checkpoint (a review the user just took now, or a
  -- close). Non-null = a promise to come back to it.
  scheduled_for    timestamptz,

  -- Null = open. The partial index below is built on exactly this.
  completed_date   timestamptz,

  outcome          text check (outcome in
                     ('reviewed', 'applied', 'dismissed', 'closed')),
  constraint fact_program_review_outcome_requires_completion check (
    (completed_date is null and outcome is null)
    or (completed_date is not null and outcome is not null)
  ),

  proposed_content text,          -- the snapshot document, kind = 'change'
  proposed_hash    text,

  achievements_json text,         -- frozen at close; NULL while the run is live

  -- Plain ref (deliberately NO foreign key): revisions reference their review
  -- and reviews reference the revision they cut, so an FK pair here would be
  -- circular and break PowerSync upload ordering — whichever row uploaded
  -- second could fail against a row the server has not seen yet. Same
  -- reasoning as fact_program_revision.review_id and
  -- fact_session_exercise_set.planned_set_id. Neither table is ever deleted,
  -- so nothing can dangle.
  revision_id      text,

  created_date     timestamptz not null default now()
);

create index fact_program_review_program_idx
  on public.fact_program_review (program_id, created_date desc);

-- The due-prompt query, and nothing else: `completed_date is null` is what
-- makes it partial and keeps it small forever, since completed reviews are the
-- overwhelming majority within weeks of a program being run.
create index fact_program_review_open_idx
  on public.fact_program_review (user_id, scheduled_for)
  where completed_date is null;

alter table public.fact_program_review enable row level security;
create policy "fact_program_review owner access"
  on public.fact_program_review for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "fact_program_review coach access"
  on public.fact_program_review for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_program_review.user_id));

alter publication powersync add table public.fact_program_review;

grant select, insert, update, delete on public.fact_program_review
  to anon, authenticated;
