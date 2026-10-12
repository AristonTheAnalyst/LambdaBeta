-- 2026-10-07: reviews stand alone — a pass over workouts and goals, not a
-- program.
--
-- WHAT A REVIEW IS. A review contains workouts and goals. Each of them can be
-- viewed; review notes attach to individual exercises inside a workout AND to
-- the workout itself; a review is something you come back to, and nothing is
-- scheduled — you start one and it stays open until you explicitly finish it.
-- That definition does not mention a program, and until now the row did:
-- `program_id` was NOT NULL and every review belonged to one. The library's
-- Reviews tab is the only start surface while the concept is being ironed out,
-- so the row must be able to exist without a program at all.
--
--   program_id NULL = a standalone review. The FK is KEPT — a row that names a
--   program still points at a real one, and nothing hard-deletes programs
--   (archive-only), so the narrow-to-null change loses nothing.
--
--   goal_ids_json  the ordered goal ids the pass covers, e.g. ["g1","g3"]. A
--   column, not a join table, because a goal can carry any scope — a program's,
--   a block's, a run's, or none — and the set is written once at start and only
--   read back.
--
--   workout_notes_json  workout-level notes keyed by planned_session_id:
--   {"s2":"Felt heavy; repeat after the deload."} — the sibling of
--   exercise_notes_json, which keys by planned_exercise_id. Both are plain text
--   in this table's established JSON idiom, and both clear back to NULL when
--   their last entry goes.
--
-- No CHECK change: `fact_program_review_scope_exclusive` only forbids block_id
-- and session_id together, and the completion-requires-snapshot check never
-- looked at program_id. Rows written before this change are untouched and keep
-- resolving exactly as they did.
--
-- PUSH THIS BEFORE SHIPPING A BUILD THAT WRITES THE NEW SHAPE: against an
-- unmigrated server the new columns earn PGRST204 (retried forever — a stalled
-- upload checkpoint, never a user-visible error) and a null program_id earns
-- 23502 (fatal — the row is quarantined into upload_failures).
--
-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and these are only new columns
-- on a `SELECT *` stream.

alter table public.fact_program_review
  alter column program_id drop not null;

alter table public.fact_program_review
  add column goal_ids_json text;

alter table public.fact_program_review
  add column workout_notes_json text;

-- The user-wide review list (the Reviews tab). The two existing indexes are
-- program-keyed and scheduled_for-keyed; neither covers "every review this user
-- has", which is the list the tab renders on every visit.
create index fact_program_review_user_idx
  on public.fact_program_review (user_id, created_date desc);
