-- 2026-09-27: program blocks — an ordered, duration-bounded phase of a program.
--
-- A program either USES blocks or doesn't — never mixed. A block holds workouts
-- (via the join rows) and, from the goals phase, goals. It carries its own
-- targets and its own dates because "how long does this phase run" is a property
-- of the phase, not of the program.
--
-- dim_* NOT fact_*: a block is reference data — a reusable blueprint, the peer
-- of a planned session — not an event. Its RUN is the event, and that is a
-- separate row in fact_program_run.
--
-- WHY date_archived AND NOT is_archived
--
-- CLAUDE.md gives child tables the boolean because their archive state is
-- "internal lifecycle only, never shown to the user". A block is the opposite:
-- it is named, dated, user-visible, and has its own run history and revision
-- trail that must stay browsable after removal. Its closest analogue is
-- dim_planned_session, which uses date_archived. Flagged in the plan as a
-- deliberate deviation.

create table public.dim_program_block (
  block_id        text primary key,
  user_id         uuid not null references public.dim_user (user_id),
  program_id      text not null references public.dim_program (program_id),
  name            text not null,
  notes           text,

  -- 1-based position within the program. Sequence order stays PROGRAM-GLOBAL
  -- (see below), so blocks order among themselves without ever renumbering a
  -- workout.
  block_order     integer not null,

  -- Targets are a property of the phase: "8 weeks", "24 sessions".
  target_weeks    integer check (target_weeks    is null or target_weeks    > 0),
  target_sessions integer check (target_sessions is null or target_sessions > 0),

  -- Planned dates. The dates a run actually STARTED and ENDED live on the run,
  -- never here — a block can be run more than once.
  start_date      timestamptz,
  end_date        timestamptz,

  date_archived   timestamptz,
  created_date    timestamptz not null default now(),
  updated_date    timestamptz not null default now(),

  -- Composite FK target for the membership constraint below: it is what makes
  -- "a workout can only join a block of its own program" enforceable by the
  -- database rather than by every caller remembering to check.
  unique (program_id, block_id)
);

create index dim_program_block_program_idx
  on public.dim_program_block (program_id, block_order);

alter table public.dim_program_block enable row level security;
create policy "dim_program_block owner access"
  on public.dim_program_block for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "dim_program_block coach access"
  on public.dim_program_block for select to authenticated
  using (exists (select 1 from public.coaching_relationship cr
    where cr.coach_user_id = auth.uid()
      and cr.athlete_user_id = dim_program_block.user_id));

alter publication powersync add table public.dim_program_block;

grant select, insert, update, delete on public.dim_program_block
  to anon, authenticated;

-- ── Block membership on the join rows ──────────────────────────────────────
alter table public.dim_planned_session_program add column block_id text;

alter table public.dim_planned_session_program
  add constraint dim_planned_session_program_block_fkey
  foreign key (program_id, block_id)
  references public.dim_program_block (program_id, block_id);

-- MATCH SIMPLE is the default and it is exactly what is wanted: with block_id
-- NULL the constraint is not enforced, so every existing row (and every
-- blockless program) is legal without a backfill. A shared block id from
-- another program cannot be sneaked in: the pair must name a real block of
-- THIS program.

comment on column public.dim_planned_session_program.block_id is
  'The block this workout belongs to. NULL = a blockless program. Composite FK '
  'with program_id: a workout can only join a block of its own program.';

-- ── The run that runs a block ──────────────────────────────────────────────
-- Nullable, so all existing rows are blockless runs and every read path that
-- ignores it returns byte-identical results.
alter table public.fact_program_run add column block_id text;

alter table public.fact_program_run
  add constraint fact_program_run_block_id_fkey
  foreign key (block_id) references public.dim_program_block (block_id);

comment on column public.fact_program_run.block_id is
  'The block being followed, or NULL for a blockless run. Note this is a plain '
  'single-column FK, NOT a composite with program_id: a run already names its '
  'program, and a composite would add a second, redundant way to disagree.';

-- ── Close the loops left open by the earlier migrations ────────────────────
-- Both tables carried block_id from the moment they were created, as a plain
-- text column, because the block table did not exist yet. NOW it does.
-- NO ACTION (the default) is deliberate, matching dim_program: blocks are
-- archived, never hard-deleted, so nothing can dangle.
alter table public.fact_program_revision
  add constraint fact_program_revision_block_id_fkey
  foreign key (block_id) references public.dim_program_block (block_id);

alter table public.fact_program_review
  add constraint fact_program_review_block_id_fkey
  foreign key (block_id) references public.dim_program_block (block_id);

-- NO CHANGES to any existing policy, grant or stream: every new column is
-- nullable and additive, and every sync stream is `SELECT *`.
