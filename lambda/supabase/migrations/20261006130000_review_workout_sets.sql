-- Reviews, re-scoped: a pass over a set of workouts.
--
-- A review row used to name exactly one thing to examine: the program's own
-- (both scope ids null), a block (`block_id`), or one planned session
-- (`session_id`). A review is now a pass over a SET of workouts, chosen when
-- the pass starts, so the row carries the set itself:
--
--   session_ids_json       the ordered planned-session ids the review covers,
--                          e.g. ["s1","s2","s3"].
--   reviewed_sessions_json the workouts finished inside the pass so far, keyed
--                          by id with the moment each was marked done:
--                          {"s1":"2026-10-06T18:04:11.000Z"}. This is what a
--                          half-done pass resumes with after an app exit.
--
-- Both are nullable and additive, matching this table's existing JSON
-- precedent (exercise_notes_json, snapshot/baseline content): rows written
-- before this change keep their block_id/session_id and are resolved to a set
-- on read, and a row written after it leaves both legacy columns null — a
-- shape the existing fact_program_review_scope_exclusive CHECK already allows,
-- since it only forbids setting BOTH. Nothing is backfilled and nothing is
-- dropped, so an older build reading a new row sees a program-scoped review,
-- which is exactly how it rendered whole-program passes already.
--
-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and these are only new columns
-- on a `SELECT *` stream.

alter table public.fact_program_review
  add column session_ids_json text;

alter table public.fact_program_review
  add column reviewed_sessions_json text;
