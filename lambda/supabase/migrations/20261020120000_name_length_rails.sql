-- The rest of the names follow the exercise rule: a name has to fit the place
-- that draws it.
--
-- Cadence: `20260929093155_exercise_name_length_constraints.sql` constrained
-- exercise and variation names at 20. Every other user-typed name kept growing
-- without a limit, so a long workout or program name could overflow the card
-- that held it. The client now caps each kind in
-- `lib/core/utils/name_limit.dart` (40 workout, 40 program, 30 block, 60 goal,
-- 40 review title), and `name_limit_test.dart` pins those numbers — this is the
-- same invariant spelled where it cannot be talked out of: the column.
--
-- The rail is **120 for all five**, deliberately above every client cap (2–3×).
-- The PowerSync mirror is a plain `Column.text` with no CHECK support, so an
-- over-long write would insert locally, render, survive a restart, and then
-- fail to upload — quarantined as a 23514 in `upload_failures`, the device and
-- server silently disagreeing. At 120 the app can never trip it; it only
-- catches a future client that forgets the rule. It is a rail, not the
-- enforcement.
--
-- Surveyed before writing (2026-10-20): the longest live row is 24 characters
-- (`dim_planned_session.name`); the other four are 14, 14, 20 and null. Nothing
-- is near 120, so no existing row is touched — unlike
-- `20260929093148_shorten_long_exercise_names.sql`, which had to shorten names
-- to make room for the 20-character constraint.
--
-- Constraints only, on columns that already exist: no new table, so no PowerSync
-- stream change and no dashboard step. `char_length` rather than `length` so the
-- count is characters and not bytes.

alter table public.dim_planned_session
  add constraint dim_planned_session_name_length_check
  check (name is null or char_length(name) <= 120);

alter table public.dim_program
  add constraint dim_program_name_length_check
  check (program_name is null or char_length(program_name) <= 120);

alter table public.dim_program_block
  add constraint dim_program_block_name_length_check
  check (name is null or char_length(name) <= 120);

alter table public.fact_goal
  add constraint fact_goal_text_length_check
  check (goal_text is null or char_length(goal_text) <= 120);

alter table public.fact_program_review
  add constraint fact_program_review_title_length_check
  check (title is null or char_length(title) <= 120);
