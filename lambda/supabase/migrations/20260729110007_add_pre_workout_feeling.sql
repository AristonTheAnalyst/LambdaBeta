-- The pre-workout "How do you expect to perform?" rating was captured in the
-- UI but discarded — never written anywhere. Additive/nullable, mirroring
-- the existing post-workout user_workout_feeling column's shape.
alter table public.fact_workout
  add column if not exists pre_workout_feeling smallint check (pre_workout_feeling between 1 and 5);
