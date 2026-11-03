-- Soft-delete for planned rows in an ACTIVE session (2026-10-13).
--
-- Deleting a set that came from the plan no longer hard-deletes it mid-session:
-- the row is flagged (is_deleted = 1) so the exercise can be restored and can
-- wear the red minus in the selector. Flagged rows exist only inside an active
-- session — the app hard-deletes them at endSession's prune, and cancelSession
-- hard-deletes the whole session — so completed-history reads never see them.
--
-- Additive only: RLS is whole-row, publication/grants are table-level — no
-- policy or grant changes. Sync streams are SELECT * — no stream change.
alter table public.fact_session_exercise_set
  add column is_deleted integer not null default 0;
