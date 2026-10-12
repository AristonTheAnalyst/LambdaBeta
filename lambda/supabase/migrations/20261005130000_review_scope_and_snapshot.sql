-- 2026-10-05: reviews carry the snapshot, and gain a session scope.
--
-- VERSIONS ARE BEING RETIRED. `fact_program_revision` held an immutable copy of
-- the whole program, cut by a "Save version" button, by review completion, and
-- by run close. It answered "what changed?" — but so does a review, and the two
-- mechanisms overlapped enough that every review completion wrote both. A review
-- is now the single checkpoint: it is scoped, it carries notes, and it carries
-- the snapshot.
--
-- THE SNAPSHOT MOVES ONTO THE REVIEW ROW. `snapshot_content` is the same
-- `ProgramContent` document the revision table held — unchanged type, unchanged
-- canonical JSON + SHA-256 — now written as part of completing a review rather
-- than as a separate row. Diffs between consecutive completed snapshots at the
-- same scope replace the Versions timeline, and `revision_number` is gone with
-- it: reviews already order by date, and a per-program counter was a second
-- ordering to keep truthful.
--
-- THREE SCOPES, EXACTLY ONE PER ROW. A review looks at the program's own plan
-- (`block_id` and `session_id` both null), at one block (`block_id`), or at one
-- planned session (`session_id`). The two ids are never both set — hence
-- `fact_program_review_scope_exclusive`. `session_id` references the planned
-- session TEMPLATE (`dim_planned_session.session_id`), not a logged session:
-- a review is a pass over the plan, and the plan is what you edit.
--
-- NO ACTION on the FK, deliberately — same reasoning as the block FK added in
-- `20260927051924`. Planned sessions are archive-only (`date_archived`), never
-- hard-deleted, so a cascade would never fire; and the review is a historical
-- record that should not disappear if one ever were.
--
-- All three columns are nullable, so this migration is safe with old clients
-- still running. `fact_program_review_completion_requires_snapshot` is NOT
-- VALID for the same reason: reviews completed before this build have no
-- snapshot and cannot get one — the revision rows that could have backfilled
-- them are dropped in `20261005130100`. The constraint applies to new rows only.

alter table public.fact_program_review add column snapshot_content text;
alter table public.fact_program_review add column snapshot_hash    text;
alter table public.fact_program_review add column session_id       text;

alter table public.fact_program_review
  add constraint fact_program_review_scope_exclusive
  check (not (session_id is not null and block_id is not null));

alter table public.fact_program_review
  add constraint fact_program_review_session_id_fkey
  foreign key (session_id) references public.dim_planned_session (session_id);

alter table public.fact_program_review
  add constraint fact_program_review_completion_requires_snapshot
  check (completed_date is null or outcome = 'dismissed' or snapshot_content is not null)
  not valid;

-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and these are only new columns
-- on a `SELECT *` stream.
