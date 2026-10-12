-- A program's shape is fixed when it is made, and it is a fact about the
-- program, not something inferred from its children.
--
-- Before this column the app read "has blocks" as "is a blocked program" —
-- `blocks.isEmpty` stood in for the shape in the grouping helper, the detail
-- state and the run sheet. That inference breaks the moment a blocked program
-- is created before its first block exists, which is exactly what the wizard
-- now allows: a blocked program with zero blocks is a real state, and it must
-- not read as a simple program (it would offer a whole-program run the shape
-- rule forbids). Shape is therefore stored, set at creation, and never
-- inferred again.
--
-- The backfill is exact rather than a guess: under the old model a program
-- with blocks *was* a blocked program, because blocks were the only way to get
-- them. Archived blocks still count — the program was made with blocks, and
-- archiving one does not turn it into a list of workouts.
--
-- `default_target_sessions` is a simple program's own remembered length: the
-- begin sheet prefills from it and writes the chosen count back, so a program
-- that "runs 12 sessions" remembers that between attempts. The run still
-- copies the number and owns the one it runs against, so editing the default
-- never rewrites an attempt in flight. NULL means "no default yet".
--
-- Column-only, on an existing table: every PowerSync stream is `SELECT *`, so
-- there is no stream or dashboard change to deploy with it.

alter table public.dim_program
  add column uses_blocks boolean not null default false;

alter table public.dim_program
  add column default_target_sessions integer
    check (default_target_sessions is null or default_target_sessions > 0);

update public.dim_program p
   set uses_blocks = true
 where exists (
   select 1 from public.dim_program_block b where b.program_id = p.program_id
 );
