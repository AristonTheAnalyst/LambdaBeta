-- Persists superset grouping for logged sets. A live session's "superset"
-- (two+ exercises worked back-to-back as one unit) previously existed only
-- as in-memory UI state (SessionExerciseSlot) and was discarded at session
-- end — there was no way to tell "these sets were part of a superset" from
-- "these sets just happened to be logged close together" after the fact.
--
-- Nullable/additive, matching the fact_workout_set attribution columns
-- added in 20260724224000: null means "not part of a superset" (the vast
-- majority of sets), so existing rows and call sites are unaffected. The
-- value only needs to disambiguate groupings within a single workout, not
-- globally — it's stamped from the session's local slot id at log time.
alter table public.fact_workout_set
  add column if not exists superset_group_number integer;
