-- 2026-10-06: reviews remember what they found, and what was noted along the way.
--
-- A REVIEW IS A PASS OVER THE PLAN, made to decide what to change. Two things
-- that pass needs were not on the row yet.
--
-- 1. THE BASELINE. Compare shows the last finished same-scope review's snapshot
--    beside the plan as it stands. For a review of something never reviewed
--    before there is no previous snapshot, so there is nothing to compare
--    against — and "no earlier version recorded" is a dead end on the one
--    screen whose whole job is the comparison. `baseline_content`/`baseline_hash`
--    are the plan captured when the review STARTS ("as found"), so the first
--    review of a thing compares against where that thing began. It is written
--    once per review and never overwritten (`AND baseline_content IS NULL`),
--    because a baseline that moved with the user's edits would compare the
--    plan to itself and always read "identical".
--
--    Same `ProgramContent` document and same canonical JSON + SHA-256 as
--    snapshot_content — the pair is deliberate, because the comparison reads
--    one against the other and two formats would need keeping in step.
--
-- 2. THE EXERCISE NOTES. A reviewer looking at each exercise wants to say why
--    they left a lift alone or why they changed it. Those notes belong to the
--    REVIEW's record — not to the dim row, not as lessons, and not carried
--    into the next review — so they live here as a JSON object keyed by the
--    planned exercise's id: {"<planned_exercise_id>": "<note>"}. Write-through
--    while the review is open (a user can leave mid-review), read back beside
--    each exercise in the completed record.
--
-- All three columns are nullable, so this migration is safe with old clients
-- still running — an old build simply does not write or read them, and a
-- review row from before this build reads as "no baseline, no notes".
--
-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and these are only new columns
-- on a `SELECT *` stream.

alter table public.fact_program_review add column baseline_content     text;
alter table public.fact_program_review add column baseline_hash        text;
alter table public.fact_program_review add column exercise_notes_json  text;
