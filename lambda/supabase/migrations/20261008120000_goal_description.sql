-- 2026-10-08: a goal can say something about itself.
--
-- A GOAL IS A SET TO BEAT — exercise, variation, weight, reps — and nothing
-- else. What it could not carry was a word about why it is being chased, or
-- what to watch while chasing it ("beltless", "catch is the limiter, not the
-- pull"). `goal_text` could not be that: for an exercise goal it holds the
-- exercise's name, captured as the label's fallback so a deleted exercise
-- never leaves the row blank.
--
-- `goal_description` is free-form notes, read and written by the focused goal
-- sheet — the view a goal row opens into, which also shows the pair's history
-- at the goal's weight and at its reps. NULL = no notes; blank is normalized
-- to NULL on write, so "nothing to say" has one spelling on the row.
--
-- Nullable and additive, so this is safe with old clients still running: an
-- old build neither writes nor reads it, and a goal from before this build
-- reads as "no notes".
--
-- No policy, grant or publication change: the table is already published and
-- already carries owner-all plus coach-select, and this is one new column on a
-- `SELECT *` stream.
--
-- PUSH THIS BEFORE SHIPPING A BUILD THAT WRITES THE COLUMN. Against an
-- unmigrated server the write earns PGRST204, which the client retries
-- forever — a stalled upload checkpoint on that device, never an error the
-- user sees. See powersync/sync-streams.yaml.

alter table public.fact_goal add column goal_description text;

comment on column public.fact_goal.goal_description is
  'Free-form notes about the goal itself. NULL = no notes.';
