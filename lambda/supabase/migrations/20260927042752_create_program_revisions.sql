-- 2026-09-27: program revisions — the version history of a program's contents.
--
-- An immutable snapshot of a program's full contents (workouts, their order,
-- and their exercises/sets), cut at the first save, at every review, and just
-- before a block or the program stops running.
--
-- WHY A JSON DOCUMENT RATHER THAN ROW COPIES:
--   1. Sync surface. Row copies would mean three more tables, each needing
--      registration in all three places of the PowerSync sync contract. A
--      missed registration is the documented root cause of the "data silently
--      disappears" incidents. One table, one set of registrations.
--   2. Volume. A 5-workout program is ~155 rows per revision; eight revisions
--      is ~1,240 cold archive rows per device, forever. As JSON it is ~12-20 KB.
--   3. Immutability by construction. A row-copy snapshot can be torn — a
--      partial transaction, or a ps_crud op quarantined as fatal. For the one
--      feature whose entire value is "this is what it was, immutably", a
--      half-written snapshot is the worst possible failure. A document is one
--      row: it exists or it doesn't.
--
--   The `exercise_order` precedent (JSON blob replaced by a real column) does
--   NOT apply: that was MUTABLE state re-read-modified on every reorder. A
--   revision is write-once and never updated. Mutable state belongs in
--   columns; immutable snapshots belong in a document.
--
-- NAMES ARE NOT EMBEDDED — the document stores ids only, resolved live, the
-- same rule 20260826000000_snapshots_out_fks_in.sql established for sessions.
-- Renaming an exercise therefore changes how old versions display, which is
-- consistent with every other surface in the app.

create table public.fact_program_revision (
  revision_id     text primary key,
  user_id         uuid not null references public.dim_user (user_id),
  program_id      text not null references public.dim_program (program_id),

  -- CONTEXT, not scope: the block that was active when this was cut. A
  -- revision is always a whole-program snapshot; this only lets the history
  -- view filter. Its FK to dim_program_block is added by the blocks migration,
  -- which necessarily runs after this one.
  block_id        text,

  -- Plain refs (deliberately NO foreign keys). Revisions and reviews reference
  -- each other, and a circular FK pair would break PowerSync upload ordering —
  -- whichever row uploaded second could fail on a row the server hasn't seen.
  -- Neither runs nor reviews are ever deleted, so nothing can dangle. Same
  -- reasoning as fact_session_exercise_set.planned_set_id.
  block_run_id    text,
  review_id       text,

  -- 1-based, unique per program — "Version N" in the UI. The unique index below
  -- makes that numbering stable: a cross-device collision surfaces as a
  -- quarantined 23505 in upload_failures rather than a silently misnumbered
  -- history.
  revision_number integer not null,

  reason          text not null check (reason in
                    ('created', 'review', 'block_end', 'program_end', 'manual')),

  content_json    text not null,
  content_hash    text not null,

  -- Flat projections written at capture time so the history timeline renders
  -- (and can show "+2 workouts") without parsing content_json.
  session_count   integer not null default 0,
  exercise_count  integer not null default 0,
  set_count       integer not null default 0,

  created_date    timestamptz not null default now(),

  unique (program_id, revision_number)
);

create index fact_program_revision_program_idx
  on public.fact_program_revision (program_id, revision_number desc);

alter table public.fact_program_revision enable row level security;
create policy "fact_program_revision owner access"
  on public.fact_program_revision for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "fact_program_revision coach access"
  on public.fact_program_revision for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = fact_program_revision.user_id));

alter publication powersync add table public.fact_program_revision;

grant select, insert, update, delete on public.fact_program_revision
  to anon, authenticated;
