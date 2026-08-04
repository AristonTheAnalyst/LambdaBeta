-- Persist the active session's exercise tab structure (order + superset
-- grouping) so it survives a hot restart. Stored as a JSON string describing
-- the slot list: [{"id":1,"type":"single|superset","exerciseIds":[...]},...].
-- Nullable — existing workouts simply rebuild tabs from their sets.
alter table public.fact_workout add column exercise_order text;
