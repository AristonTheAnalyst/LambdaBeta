-- 2026-10-05: drop the version trail.
--
-- SEPARATE FILE FROM THE ADDITIVE HALF ON PURPOSE. This is the only destructive
-- statement in the reviews rework, and it must not run while a build that still
-- writes `revision_id` is live. `database.dart`'s `_fatalCodes` does not treat
-- `PGRST204` ("column not found") as fatal — a client UPDATEing a column the
-- server no longer has retries forever and stalls that device's checkpoint
-- behind a row that will never succeed. So the order is:
--
--   1. `20261005130000` (additive — safe with old and new clients)
--   2. deploy the sync-stream YAML that drops the revision query
--   3. ship the build that stops touching `fact_program_revision`
--   4. run this file
--
-- Step 2 must precede this one: a stream naming a table that no longer exists
-- fails validation and can take the whole stream down with it.
--
-- THE ROWS ARE BEING DISCARDED. Existing revisions have no home in the new
-- model — they are whole-program documents with no review to attach to, and
-- reviews carry their own snapshots going forward. Their product value ("what
-- changed between two checkpoints") is answered by diffing consecutive
-- completed reviews at the same scope.

alter table public.fact_program_review drop column revision_id;

drop table public.fact_program_revision;
