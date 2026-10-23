-- 2026-10-19: a goal can carry a deadline, and every move of it.
--
-- A goal is a set to beat — exercise, variation, weight, reps — and the one
-- thing it could not say was *when* it should be beaten by. `target_date` is
-- that day. NULL = no deadline; a goal is still worth chasing without a clock
-- on it, so the column is optional and never inferred.
--
-- `target_date_history_json` is every adjustment of that deadline, so moving
-- it is a fact rather than a silent overwrite. An array, oldest first, of
--   {"from": <ISO date|null>, "to": <ISO date|null>, "changed_at": <ISO ts>}
-- where a null side is "no deadline" — so setting one for the first time and
-- clearing it again both round-trip. The focused goal sheet reads the latest
-- change back; nothing derives from the history, it is a record.
--
-- Both columns are nullable and additive, so this is safe with old clients
-- still running: an old build neither writes nor reads them, and a goal from
-- before this build reads as "no deadline, never adjusted".
--
-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and these are two new columns
-- on a `SELECT *` stream.
--
-- PUSH THIS BEFORE SHIPPING A BUILD THAT WRITES THE COLUMNS. Against an
-- unmigrated server the write earns PGRST204, which the client retries
-- forever — a stalled upload checkpoint on that device, never an error the
-- user sees. See powersync/sync-streams.yaml.

alter table public.fact_goal add column target_date text;
alter table public.fact_goal add column target_date_history_json text;

comment on column public.fact_goal.target_date is
  'The day the goal should be hit by, ISO-8601. NULL = no deadline.';
comment on column public.fact_goal.target_date_history_json is
  'Every adjustment to target_date, oldest first: [{from, to, changed_at}]. NULL = never adjusted.';
