-- 2026-09-27: goals get a scope, a variation, and lose a column that could
-- never be right.
--
-- A goal used to hang off a single RUN (`program_run_id`). That is the wrong
-- axis: "bench 100 × 1" is a target you are chasing during a PHASE, and the
-- same phase run twice should carry the same goal. So a goal now scopes to a
-- program or to a block of one, and the run link remains only as provenance
-- for goals created before this migration.
--
-- WHY achieved_date IS DROPPED RATHER THAN FINALLY USED
--
-- A goal is now scoped to a program or block, so its achievement is a
-- per-run fact — one column cannot express "achieved in Block 1, missed in
-- Block 3". The outcome is recorded per run in
-- fact_program_review.achievements_json instead, which also stops the goal
-- row carrying derived state it would have to keep in sync with the set rows
-- that decide it. In-progress runs derive; closed runs show the frozen record.
-- The table is empty, so this drop costs nothing.

alter table public.fact_goal add column program_id text;
alter table public.fact_goal add column block_id   text;
alter table public.fact_goal add column custom_variation_id text;

alter table public.fact_goal
  add constraint fact_goal_program_id_fkey
  foreign key (program_id) references public.dim_program (program_id);

alter table public.fact_goal
  add constraint fact_goal_variation_id_fkey
  foreign key (custom_variation_id) references public.dim_variation (custom_variation_id);

-- A goal can only scope to a block of its OWN program — the same integrity
-- guarantee the membership join table gets, and it needs the same two pieces.
--
-- MATCH SIMPLE (the default) skips the check whenever ANY column is null, so
-- the composite FK alone would silently accept a block-scoped goal carrying no
-- program: block_id set, program_id null, constraint not enforced. The CHECK
-- closes exactly that hole and makes the pair total whenever a block is named.
-- Both FKs are NO ACTION, matching dim_program and dim_program_block: those
-- dims are archived, never hard-deleted, so nothing can dangle.

alter table public.fact_goal
  add constraint fact_goal_block_scope_check
  check (block_id is null or program_id is not null);

alter table public.fact_goal
  add constraint fact_goal_block_fkey
  foreign key (program_id, block_id)
  references public.dim_program_block (program_id, block_id);

alter table public.fact_goal drop column achieved_date;

-- The panel asks one question — "what is in force for this program (and this
-- block)" — so the index answers it in that order.
create index fact_goal_scope_idx
  on public.fact_goal (user_id, program_id, block_id);

comment on column public.fact_goal.program_id is
  'The program this goal belongs to, or NULL for a standalone goal. No scope '
  'column means "the whole program"; a block_id means "this phase of it".';
comment on column public.fact_goal.block_id is
  'The block this goal belongs to, or NULL for a program-level goal. Composite '
  'FK with program_id, guarded by fact_goal_block_scope_check so a block scope '
  'cannot arrive without its program.';
comment on column public.fact_goal.custom_variation_id is
  'Narrows the goal to one variation ("Paused Bench" vs Bench). NULL means any '
  'variation of the exercise counts, which is how every goal behaved before '
  'this column existed.';

-- NO CHANGES to any policy, grant or stream: fact_goal already carries both,
-- every new column is nullable and additive, and every sync stream is
-- SELECT *. Dropping achieved_date is safe for builds that still declare it —
-- PowerSync applies the client schema as views over a schemaless wire, so a
-- column the server no longer sends simply stays null.
